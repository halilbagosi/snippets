#include <metal_stdlib>
using namespace metal;

float2 genieDistortion(float2 position, float2 size, float progress) {
    float2 center = size * 0.5;
    float2 p = position - center;
    float dist = length(p);
    float maxDist = length(size * 0.5);
    
    // Exponential pinch: to shrink the image, we blow up the sample coordinates.
    // The further from center, the faster it blows up.
    float normalizedDist = dist / maxDist;
    
    // Swirl effect
    float angle = atan2(p.y, p.x);
    float swirl = progress * 6.0 * (1.0 - normalizedDist);
    
    float scale = 1.0 + (progress * 8.0) + (pow(progress, 2.0) * 20.0 * normalizedDist);
    
    float2 swirled = float2(cos(angle + swirl), sin(angle + swirl)) * (dist * scale);
    
    return center + swirled;
}

half4 genieColor(float2 position, half4 color, float2 size, float progress) {
    // Add a glowing energy rim as it gets sucked in
    float2 p = position - (size * 0.5);
    float dist = length(p);
    float maxDist = length(size * 0.5);
    float normalizedDist = dist / maxDist;
    
    float edgeGlow = smoothstep(0.4, 0.9, progress) * smoothstep(0.3, 0.8, normalizedDist);
    half3 glowColor = half3(0.9h, 0.2h, 0.1h); // reddish energy glow
    
    color.rgb += glowColor * half(edgeGlow * 1.5);
    
    // Fade out as it reaches the singularity
    color.a *= half(1.0 - pow(progress, 4.0));
    return color;
}

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
    float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    float2 p = positions[vid];
    VertexOut out;
    out.position = float4(p, 0.0, 1.0);
    out.uv = p * 0.5 + 0.5;
    return out;
}

struct Uniforms {
    float4 sizeAndProgress; // x = width, y = height, z = progress
    float4 baseColor;
    float4 accentColor;
};

fragment half4 fragment_main(VertexOut in [[stage_in]], texture2d<float> inputTexture [[texture(0)]], sampler inputSampler [[sampler(0)]], constant Uniforms &u [[ buffer(0) ]]) {
    float2 size = u.sizeAndProgress.xy;
    float progress = u.sizeAndProgress.z;
    float2 position = in.uv * size;

    float2 distorted = genieDistortion(position, size, progress);
    float2 uv = distorted / size;
    
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return half4(0.0);
    }

    float4 sampled = inputTexture.sample(inputSampler, uv);
    half4 color = half4(half(sampled.x), half(sampled.y), half(sampled.z), half(sampled.w));

    half4 finalColor = genieColor(distorted, color, size, progress);

    // Blend a subtle accent color into the highlights based on progress
    half3 accent = half3(u.accentColor.x, u.accentColor.y, u.accentColor.z);
    finalColor.rgb = mix(finalColor.rgb, accent, half(0.35 * progress));

    return finalColor;
}

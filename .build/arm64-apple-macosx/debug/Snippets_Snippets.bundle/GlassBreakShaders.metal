#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float shardNoise(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

[[ stitchable ]] float2 glassBreakDistortion(float2 position, float2 size, float progress) {
    float2 center = size * 0.5;
    float2 p = position - center;
    float distanceFromCenter = max(length(p), 1.0);
    float2 direction = p / distanceFromCenter;

    float angle = atan2(p.y, p.x);
    float shardBand = floor((angle + 3.14159265) * 5.75);
    float shard = shardNoise(float2(shardBand, floor(distanceFromCenter * 0.018)));
    float crackWave = sin(distanceFromCenter * 0.085 - progress * 11.0 + shard * 6.28318);
    float burst = smoothstep(0.02, 0.82, progress) * (1.0 - smoothstep(0.70, 1.0, progress));

    float radialSplit = (10.0 + shard * 22.0) * burst;
    float ripple = crackWave * (4.0 + shard * 5.0) * burst;
    float2 tangent = float2(-direction.y, direction.x);

    return position - direction * radialSplit - tangent * ripple;
}

[[ stitchable ]] half4 glassBreakColor(float2 position, half4 color, float2 size, float progress) {
    float2 center = size * 0.5;
    float2 p = position - center;
    float distanceFromCenter = length(p);
    float angle = atan2(p.y, p.x);
    float shardBand = floor((angle + 3.14159265) * 7.5);
    float crack = abs(sin(angle * 11.0 + distanceFromCenter * 0.055));
    float crackLine = 1.0 - smoothstep(0.012, 0.055, crack);
    float ring = 1.0 - smoothstep(0.0, 0.08, abs(fract(distanceFromCenter * 0.035 - progress * 1.6) - 0.5));
    float shard = shardNoise(float2(shardBand, floor(distanceFromCenter * 0.024)));
    float energy = smoothstep(0.0, 0.55, progress) * (1.0 - smoothstep(0.78, 1.0, progress));

    half3 coldEdge = half3(0.72h, 0.90h, 1.0h);
    half3 warmFlash = half3(1.0h, 0.96h, 0.82h);
    half highlight = half((crackLine * 0.42 + ring * 0.08 + shard * 0.10) * energy);

    color.rgb = mix(color.rgb, coldEdge, highlight);
    color.rgb += warmFlash * half(crackLine * energy * 0.22);
    color.a *= half(1.0 - smoothstep(0.72, 1.0, progress) * 0.82);
    return color;
}

// Simple fullscreen vertex/fragment entrypoints to drive the stitchable functions
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

    // Distort sample coordinate using shatter distortion
    float2 distorted = glassBreakDistortion(position, size, progress);
    float2 uv = distorted / size;
    uv = clamp(uv, float2(0.0, 0.0), float2(1.0, 1.0));

    float4 sampled = inputTexture.sample(inputSampler, uv);
    half4 color = half4(half(sampled.x), half(sampled.y), half(sampled.z), half(sampled.w));

    half4 finalColor = glassBreakColor(distorted, color, size, progress);

    // Blend a subtle accent color into the highlights based on progress
    half3 accent = half3(u.accentColor.x, u.accentColor.y, u.accentColor.z);
    finalColor.rgb = mix(finalColor.rgb, accent, half(0.25 * progress));

    return finalColor;
}

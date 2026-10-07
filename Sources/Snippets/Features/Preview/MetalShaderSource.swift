import Foundation

/// Prepares Metal snippet source for runtime compilation. Pure string logic,
/// unit-testable without a GPU.
///
/// Convention for fragment-only snippets (shadertoy-style): the prelude
/// supplies `VertexOut { position, uv }`, `SnippetUniforms { time, resolution,
/// mouse }` (bound at fragment buffer 0) and a fullscreen-triangle vertex
/// function. Full shaders that include metal_stdlib themselves pass through
/// untouched and may bring their own vertex function.
enum MetalShaderSource {
    struct Prepared: Equatable {
        let source: String
        let fragmentFunction: String
        let vertexFunction: String
    }

    enum PreparationError: LocalizedError {
        case noFragmentFunction

        var errorDescription: String? {
            "No fragment function found. Define one, e.g. `fragment float4 mainImage(VertexOut in [[stage_in]], constant SnippetUniforms& u [[buffer(0)]])`."
        }
    }

    static let prelude = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    struct SnippetUniforms {
        float time;
        float2 resolution;
        float4 mouse;
    };

    vertex VertexOut __snippet_vertex(uint vid [[vertex_id]]) {
        float2 positions[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
        VertexOut out;
        out.position = float4(positions[vid], 0.0, 1.0);
        out.uv = positions[vid] * 0.5 + 0.5;
        return out;
    }

    """

    static func prepare(_ code: String) throws -> Prepared {
        try prepare(entry: code, helpers: [])
    }

    /// Helpers (resolved dependencies) are concatenated above the entry.
    /// The fragment function is picked from the entry only; a helper may
    /// supply the vertex function or the stdlib include.
    static func prepare(entry: String, helpers: [String]) throws -> Prepared {
        guard let fragmentName = firstCapture(#"fragment\s+\w+\s+(\w+)\s*\("#, in: entry) else {
            throw PreparationError.noFragmentFunction
        }
        let combined = (helpers + [entry]).joined(separator: "\n\n")
        let userVertex = firstCapture(#"vertex\s+\w+\s+(\w+)\s*\("#, in: combined)
        return Prepared(
            source: combined.contains("metal_stdlib") ? combined : prelude + combined,
            fragmentFunction: fragmentName,
            vertexFunction: userVertex ?? "__snippet_vertex"
        )
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

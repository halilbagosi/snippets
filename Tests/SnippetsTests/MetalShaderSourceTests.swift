import XCTest
@testable import Snippets

final class MetalShaderSourceTests: XCTestCase {
    func test_extractsFragmentFunctionName_basicSignature() throws {
        let prepared = try MetalShaderSource.prepare(
            "fragment float4 mainImage(VertexOut in [[stage_in]]) { return float4(1); }"
        )
        XCTAssertEqual(prepared.fragmentFunction, "mainImage")
    }

    func test_extractsFragmentFunctionName_half4AndSpacing() throws {
        let prepared = try MetalShaderSource.prepare(
            "fragment   half4   shade  (VertexOut in [[stage_in]]) { return half4(0); }"
        )
        XCTAssertEqual(prepared.fragmentFunction, "shade")
    }

    func test_fragmentOnlySnippet_getsPreludeAndBuiltInVertex() throws {
        let prepared = try MetalShaderSource.prepare(
            "fragment float4 mainImage(VertexOut in [[stage_in]]) { return float4(1); }"
        )
        XCTAssertTrue(prepared.source.contains("#include <metal_stdlib>"))
        XCTAssertTrue(prepared.source.contains("SnippetUniforms"))
        XCTAssertEqual(prepared.vertexFunction, "__snippet_vertex")
        XCTAssertTrue(prepared.source.contains("vertex VertexOut __snippet_vertex"))
    }

    func test_fullShaderWithOwnStdlibAndVertex_passesThroughAndUsesOwnVertex() throws {
        let code = """
        #include <metal_stdlib>
        using namespace metal;
        struct VOut { float4 position [[position]]; };
        vertex VOut myVertex(uint vid [[vertex_id]]) { VOut o; o.position = float4(0); return o; }
        fragment float4 myFragment(VOut in [[stage_in]]) { return float4(1); }
        """
        let prepared = try MetalShaderSource.prepare(code)
        XCTAssertEqual(prepared.source, code)
        XCTAssertEqual(prepared.vertexFunction, "myVertex")
        XCTAssertEqual(prepared.fragmentFunction, "myFragment")
    }

    func test_helpers_areConcatenatedBeforeEntry_fragmentFromEntry() throws {
        let prepared = try MetalShaderSource.prepare(
            entry: "fragment float4 mainImage(VertexOut in [[stage_in]]) { return float4(glow(0.5)); }",
            helpers: ["float4 glow(float x) { return float4(x); }"]
        )
        XCTAssertEqual(prepared.fragmentFunction, "mainImage")
        XCTAssertLessThan(prepared.source.range(of: "float4 glow")!.lowerBound,
                          prepared.source.range(of: "fragment float4 mainImage")!.lowerBound)
    }

    func test_noFragmentFunction_throwsDescriptiveError() {
        XCTAssertThrowsError(try MetalShaderSource.prepare("float4 helper() { return float4(0); }")) { error in
            XCTAssertTrue(String(describing: error).lowercased().contains("fragment"))
        }
    }
}

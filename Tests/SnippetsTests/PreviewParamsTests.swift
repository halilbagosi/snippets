import XCTest
@testable import Snippets

final class PreviewParamsTests: XCTestCase {
    func test_detectsScalarDefaultsFromArrowComponent() {
        let params = PreviewParamDetector.reactParams(in: """
        const Strands = ({ amplitude = 1.4, glow = true, tint = "#ff94b8", label = 'waves', stops = [1, 2] }) => {
            return <div>{label}</div>;
        };
        export default Strands;
        """)
        XCTAssertEqual(params.map(\.name), ["amplitude", "glow", "tint", "label"])
        XCTAssertEqual(params[0].kind, .number(default: 1.4))
        XCTAssertEqual(params[1].kind, .boolean(default: true))
        XCTAssertEqual(params[2].kind, .color(defaultHex: "#ff94b8"))
        XCTAssertEqual(params[3].kind, .text(default: "waves"))
    }

    func test_detectsDefaultsFromFunctionComponent() {
        let params = PreviewParamDetector.reactParams(in: """
        export default function App({ size = 40, rounded = false }) {
            return <div style={{ width: size }} />;
        }
        """)
        XCTAssertEqual(params.map(\.name), ["size", "rounded"])
        XCTAssertEqual(params[0].kind, .number(default: 40))
    }

    func test_componentWithoutDestructuredProps_hasNoParams() {
        XCTAssertTrue(PreviewParamDetector.reactParams(in:
            "export default function App() { return <p>hi</p> }"
        ).isEmpty)
        XCTAssertTrue(PreviewParamDetector.reactParams(in:
            "const App = (props) => <p>{props.x}</p>; export default App;"
        ).isEmpty)
    }

    func test_objectAndFunctionDefaults_areSkipped() {
        let params = PreviewParamDetector.reactParams(in: """
        const App = ({ config = { a: 1 }, onTap = () => {}, speed = 2 }) => <p/>;
        export default App;
        """)
        XCTAssertEqual(params.map(\.name), ["speed"])
    }

    func test_nonColorShortString_isTextParam_hexIsColor() {
        let params = PreviewParamDetector.reactParams(in: """
        const App = ({ mode = "wave", accent = "#0af" }) => <p/>;
        export default App;
        """)
        XCTAssertEqual(params[0].kind, .text(default: "wave"))
        XCTAssertEqual(params[1].kind, .color(defaultHex: "#0af"))
    }

    // MARK: Dropdown inference

    func test_stringPropWithTSUnion_becomesChoice() {
        let params = PreviewParamDetector.reactParams(in: """
        interface Props { falloff?: "linear" | "exponential" | "gaussian"; }
        const CursorGrid = ({ falloff = "gaussian" }: Props) => <div/>;
        export default CursorGrid;
        """)
        XCTAssertEqual(params[0].kind, .choice(
            default: "gaussian", options: ["gaussian", "linear", "exponential"]
        ))
    }

    func test_stringPropWithComparisons_becomesChoice() {
        let params = PreviewParamDetector.reactParams(in: """
        const Grid = ({ falloff = "linear" }) => {
            const power = falloff === "exponential" ? 2 : falloff !== "gaussian" ? 1 : 3;
            return <div>{power}</div>;
        };
        export default Grid;
        """)
        XCTAssertEqual(params[0].kind, .choice(
            default: "linear", options: ["linear", "exponential", "gaussian"]
        ))
    }

    func test_stringPropWithoutDiscoverableOptions_staysTextField() {
        let params = PreviewParamDetector.reactParams(in: """
        const App = ({ label = "hello" }) => <p>{label}</p>;
        export default App;
        """)
        XCTAssertEqual(params[0].kind, .text(default: "hello"))
    }

    // MARK: GLSL uniforms

    func test_glslParams_detectsCustomUniformsWithDefaults_skipsBuiltins() {
        let params = PreviewParamDetector.glslParams(in: """
        uniform float iTime;
        uniform vec2 iResolution;
        uniform vec4 iMouse;
        uniform float uSpeed; // = 1.5
        uniform int uCount; // = 6
        uniform bool uGlow; // = true
        uniform vec3 uTint; // = #ff0044
        uniform vec4 uHalo;
        void main() {}
        """)
        XCTAssertEqual(params.map(\.name), ["uSpeed", "uCount", "uGlow", "uTint", "uHalo"])
        XCTAssertEqual(params[0].kind, .number(default: 1.5))
        XCTAssertEqual(params[1].kind, .integer(default: 6))
        XCTAssertEqual(params[2].kind, .boolean(default: true))
        XCTAssertEqual(params[3].kind, .color(defaultHex: "#ff0044"))
        XCTAssertEqual(params[4].kind, .color(defaultHex: "#000000"))
    }

    func test_glslDocument_embedsUniformTableAndRenderHook() {
        let doc = WebPreviewHTMLBuilder.document(
            code: "uniform float uSpeed; // = 2\nvoid main() { fragColor = vec4(uSpeed); }",
            flavor: .glsl,
            appearance: .init(isDark: true, backgroundHex: "#000", textHex: "#fff"),
            runtime: .init(react: "", reactDOM: "", babel: "")
        )
        XCTAssertTrue(doc.contains(#"{"name": "uSpeed", "type": "float", "def": 2.0}"#))
        XCTAssertTrue(doc.contains("window.__snippetRender = (overrides)"))
        XCTAssertTrue(doc.contains("__applyCustomUniforms(gl)"))
    }

    // MARK: Metal params

    func test_metalParams_parsesSnippetParamsStruct() {
        let params = PreviewParamDetector.metalParams(in: """
        struct SnippetParams {
            float speed; // = 2.5
            int rings; // = 4
            float3 tint; // = #00ff88
        };
        fragment float4 mainImage(VertexOut in [[stage_in]],
                                  constant SnippetUniforms& u [[buffer(0)]],
                                  constant SnippetParams& p [[buffer(1)]]) { return float4(1); }
        """)
        XCTAssertEqual(params.map(\.name), ["speed", "rings", "tint"])
        XCTAssertEqual(params[0].kind, .number(default: 2.5))
        XCTAssertEqual(params[1].kind, .integer(default: 4))
        XCTAssertEqual(params[2].kind, .color(defaultHex: "#00ff88"))
    }

    func test_metalParams_absentStruct_meansNoParams() {
        XCTAssertTrue(PreviewParamDetector.metalParams(in:
            "fragment float4 f() { return float4(1); }"
        ).isEmpty)
    }

    func test_packMetalParams_matchesMSLAlignment() {
        let params = [
            PreviewParam(name: "speed", kind: .number(default: 2)),
            PreviewParam(name: "tint", kind: .color(defaultHex: "#ff0000")),
            PreviewParam(name: "rings", kind: .integer(default: 3))
        ]
        let bytes = PreviewParamDetector.packMetalParams(params, overrides: [:])
        // float @0 (4B), float3 aligned to 16 @16 (16B), int @32, stride
        // padded to 48 (16-byte struct alignment).
        XCTAssertEqual(bytes.count, 48)
        let floats = bytes.withUnsafeBytes { $0.bindMemory(to: Float.self) }
        XCTAssertEqual(floats[0], 2)
        XCTAssertEqual(floats[4], 1)   // tint.r at byte 16
        XCTAssertEqual(floats[5], 0)
        let rings = bytes.withUnsafeBytes { $0.load(fromByteOffset: 32, as: Int32.self) }
        XCTAssertEqual(rings, 3)
    }

    func test_packMetalParams_appliesOverrides() {
        let params = [PreviewParam(name: "speed", kind: .number(default: 2))]
        let bytes = PreviewParamDetector.packMetalParams(params, overrides: ["speed": .number(7)])
        XCTAssertEqual(bytes.withUnsafeBytes { $0.load(as: Float.self) }, 7)
    }

    func test_paramValueJSONLiterals() {
        XCTAssertEqual(PreviewParamValue.number(2).jsonLiteral, "2")
        XCTAssertEqual(PreviewParamValue.number(1.4).jsonLiteral, "1.4")
        XCTAssertEqual(PreviewParamValue.boolean(false).jsonLiteral, "false")
        XCTAssertEqual(PreviewParamValue.string("#ff0<\"/script>").jsonLiteral, "\"#ff0<\\\"\\/script>\"")
    }

    func test_propsUpdateScript_rendersMergedOverrides() {
        let script = WebPreviewHTMLBuilder.propsUpdateScript(
            overrides: ["amplitude": .number(2), "tint": .string("#00ff88")]
        )
        XCTAssertTrue(script.contains("window.__snippetRender({ \"amplitude\": 2, \"tint\": \"#00ff88\" })"))
        XCTAssertTrue(script.contains("typeof window.__snippetRender === \"function\""))
    }

    func test_reactDocument_mountRendersThroughOverridableRenderFunction() {
        let doc = WebPreviewHTMLBuilder.document(
            code: "export default function App({ size = 4 }) { return <p>{size}</p> }",
            flavor: .react,
            appearance: .init(isDark: true, backgroundHex: "#000", textHex: "#fff"),
            runtime: .init(react: "", reactDOM: "", babel: "")
        )
        XCTAssertTrue(doc.contains("window.__snippetRender = (overrides)"))
        XCTAssertTrue(doc.contains("window.__snippetPropOverrides || null"))
    }
}

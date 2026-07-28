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

    func test_stringPropIndexingLookupTable_becomesChoice() {
        let params = PreviewParamDetector.reactParams(in: """
        const FALLOFF_CURVES = {
          linear: p => p,
          smooth: p => p * p * (3 - 2 * p),
          sharp: p => p * p * p
        };
        const LineSidebar = ({ falloff = 'smooth' }) => {
          const ease = FALLOFF_CURVES[falloff] ?? FALLOFF_CURVES.linear;
          return <div>{ease(1)}</div>;
        };
        export default LineSidebar;
        """)
        XCTAssertEqual(params[0].kind, .choice(
            default: "smooth", options: ["smooth", "linear", "sharp"]
        ))
    }

    /// Nested values must not contribute their own keys, and quoted keys must
    /// read the same as bare ones.
    func test_lookupTableOptions_readOnlyTopLevelKeys() {
        let params = PreviewParamDetector.reactParams(in: """
        const PRESETS = {
          'soft': { blur: 4, spread: 2 },
          hard: { blur: 0, spread: 0 }
        };
        const Card = ({ preset = 'soft' }) => <div style={PRESETS[preset]} />;
        export default Card;
        """)
        XCTAssertEqual(params[0].kind, .choice(default: "soft", options: ["soft", "hard"]))
    }

    /// A component that bundles its props into one object still names the prop
    /// where it indexes the table.
    func test_lookupTableIndexedThroughPropsObject_becomesChoice() {
        let params = PreviewParamDetector.reactParams(in: """
        const FALLOFF_CURVES = { linear: p => p, smooth: p => p * p, sharp: p => p * p * p };
        const CursorGrid = ({ falloff = 'smooth' }) => {
          const draw = p => FALLOFF_CURVES[p.falloff] ?? FALLOFF_CURVES.linear;
          return <canvas ref={draw({ falloff })} />;
        };
        export default CursorGrid;
        """)
        XCTAssertEqual(params[0].kind, .choice(
            default: "smooth", options: ["smooth", "linear", "sharp"]
        ))
    }

    func test_stringPropSwitchedOn_becomesChoice() {
        let params = PreviewParamDetector.reactParams(in: """
        const Easing = ({ curve = 'linear' }) => {
          switch (curve) {
            case 'linear': return <A/>;
            case 'ease-in': return <B/>;
            default: return null;
          }
        };
        export default Easing;
        """)
        XCTAssertEqual(params[0].kind, .choice(
            default: "linear", options: ["linear", "ease-in"]
        ))
    }

    /// The options live in the component; the usage only pins a value. Merging
    /// has to keep the dropdown rather than let the usage's bare string win.
    func test_usagePinnedChoice_keepsComponentOptions() {
        let component = PreviewParamDetector.detectReact(in: """
        const FALLOFF_CURVES = { linear: p => p, smooth: p => p * p, sharp: p => p * p * p };
        const LineSidebar = ({ falloff = 'linear' }) => <div>{FALLOFF_CURVES[falloff](1)}</div>;
        export default LineSidebar;
        """)
        let usage = PreviewParamDetector.detectJSXUsage(in: #"<LineSidebar falloff="smooth" />"#)
        let merged = PreviewParamDetector.merging(usage: usage, into: component)

        XCTAssertEqual(merged.map(\.param.kind), [
            .choice(default: "smooth", options: ["linear", "smooth", "sharp"])
        ])
        // The usage owns the write target, so a saved config still lands where
        // the value that renders actually lives.
        XCTAssertEqual(merged.map(\.target), usage.map(\.target))
    }

    /// A usage pinning something the component never lists still has to show
    /// what is on screen.
    func test_usagePinnedValueOutsideOptions_leadsTheList() {
        let component = PreviewParamDetector.detectReact(in: """
        const CURVES = { linear: 1, smooth: 2 };
        const Line = ({ falloff = 'linear' }) => <div>{CURVES[falloff]}</div>;
        export default Line;
        """)
        let usage = PreviewParamDetector.detectJSXUsage(in: #"<Line falloff="custom" />"#)
        XCTAssertEqual(
            PreviewParamDetector.merging(usage: usage, into: component).map(\.param.kind),
            [.choice(default: "custom", options: ["custom", "linear", "smooth"])]
        )
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

    // MARK: Write targets

    func test_detectGLSL_reportsLiteralRangeOfAnnotatedDefault() {
        let code = "uniform float amplitude; // = 1.5\n"
        let detected = PreviewParamDetector.detectGLSL(in: code)
        XCTAssertEqual(detected.count, 1)
        guard case .literal(let range) = detected[0].target else {
            return XCTFail("expected .literal target, got \(detected[0].target)")
        }
        XCTAssertEqual(String(code[range]), "1.5")
    }

    func test_detectGLSL_reportsInsertionPointWhenAnnotationMissing() {
        let code = "uniform float amplitude;\n"
        let detected = PreviewParamDetector.detectGLSL(in: code)
        XCTAssertEqual(detected.count, 1)
        guard case .annotation(let index) = detected[0].target else {
            return XCTFail("expected .annotation target, got \(detected[0].target)")
        }
        XCTAssertEqual(String(code[code.startIndex..<index]), "uniform float amplitude;")
    }

    func test_detectMetal_rangesAreValidInFullSource() {
        let code = """
        struct SnippetParams {
            float speed; // = 2.0
        };
        """
        let detected = PreviewParamDetector.detectMetal(in: code)
        XCTAssertEqual(detected.count, 1)
        guard case .literal(let range) = detected[0].target else {
            return XCTFail("expected .literal target")
        }
        XCTAssertEqual(String(code[range]), "2.0")
    }

    func test_detectReact_reportsLiteralRangeIncludingQuotes() {
        let code = ##"const App = ({ amplitude = 1.4, tint = "#ff94b8" }) => <p/>; export default App;"##
        let detected = PreviewParamDetector.detectReact(in: code)
        XCTAssertEqual(detected.map(\.param.name), ["amplitude", "tint"])
        guard case .literal(let numberRange) = detected[0].target,
              case .literal(let stringRange) = detected[1].target else {
            return XCTFail("expected .literal targets")
        }
        XCTAssertEqual(String(code[numberRange]), "1.4")
        XCTAssertEqual(String(code[stringRange]), "\"#ff94b8\"")
    }

    func test_legacyParamAPIs_stillReturnSameParams() {
        let code = "uniform float amplitude; // = 1.5\n"
        XCTAssertEqual(PreviewParamDetector.glslParams(in: code).map(\.name), ["amplitude"])
        XCTAssertEqual(PreviewParamDetector.glslParams(in: code), PreviewParamDetector.detectGLSL(in: code).map(\.param))
    }

    func test_detectForLanguage_routesGLSLToUniformDetection() {
        let resolution = SnippetLinker.Resolution(
            sources: [LinkedSource(language: .glsl, code: "uniform float amplitude; // = 2.0")],
            excluded: []
        )
        let detected = PreviewParamDetector.detect(for: .glsl, resolution: resolution)
        XCTAssertEqual(detected.map(\.param.name), ["amplitude"])
    }

    func test_detectForLanguage_combinesHelperAndEntrySourcesForGLSL() {
        let resolution = SnippetLinker.Resolution(
            sources: [
                LinkedSource(language: .glsl, code: "uniform float helperKnob; // = 1.0"),
                LinkedSource(language: .glsl, code: "uniform float entryKnob; // = 2.0")
            ],
            excluded: []
        )
        let detected = PreviewParamDetector.detect(for: .glsl, resolution: resolution)
        XCTAssertEqual(detected.map(\.param.name), ["helperKnob", "entryKnob"])
    }

    func test_detectForLanguage_returnsNothingForUnsupportedLanguage() {
        let resolution = SnippetLinker.Resolution(
            sources: [LinkedSource(language: .swift, code: "let x = 1")],
            excluded: []
        )
        XCTAssertTrue(PreviewParamDetector.detect(for: .swift, resolution: resolution).isEmpty)
    }
}

// MARK: - Config write-back with a connected usage snippet

extension PreviewParamsTests {
    private var strandsEntry: String {
        """
        const Strands = ({
          count = 3,
          speed = 0.5,
          glass = false
        }) => null;
        export default Strands;
        """
    }
    private var strandsUsage: String {
        """
        import Strands from './Strands';

        <Strands
          count={3}
          speed={0.5}
          glass={false}
        />
        """
    }

    /// The bug: a saved config rewrote the component's *defaults*, but the
    /// preview mounts the usage snippet, whose explicit props win — so the
    /// preview kept showing the old values.
    func test_usageSnippet_ownsTheValuesAConfigMustWrite() {
        let usageParams = PreviewParamDetector.detectJSXUsage(in: strandsUsage)
        XCTAssertEqual(Set(usageParams.map(\.param.name)), ["count", "speed", "glass"])

        let written = PreviewParamWriter.apply(
            ["count": .number(7), "speed": .number(2), "glass": .boolean(true)],
            to: strandsUsage, params: usageParams
        )
        XCTAssertTrue(written.contains("count={7}"))
        XCTAssertTrue(written.contains("speed={2}"))
        XCTAssertTrue(written.contains("glass={true}"))
    }

    func test_detectJSXUsage_readsEffectiveValuesNotComponentDefaults() {
        let usage = """
        <Strands count={9} label="hi" tint="#ff0044" glass loop={false} />
        """
        let byName = Dictionary(
            uniqueKeysWithValues: PreviewParamDetector.detectJSXUsage(in: usage).map { ($0.param.name, $0.param.kind) }
        )
        XCTAssertEqual(byName["count"], .number(default: 9))
        XCTAssertEqual(byName["label"], .text(default: "hi"))
        XCTAssertEqual(byName["tint"], .color(defaultHex: "#ff0044"))
        // A bare JSX attribute is `true`.
        XCTAssertEqual(byName["glass"], .boolean(default: true))
        XCTAssertEqual(byName["loop"], .boolean(default: false))
    }

    func test_detectJSXUsage_ignoresNonUsageSources() {
        XCTAssertTrue(PreviewParamDetector.detectJSXUsage(in: strandsEntry).isEmpty)
        XCTAssertTrue(PreviewParamDetector.detectJSXUsage(in: "<div class=\"card\">plain</div>").isEmpty)
    }
}

extension PreviewParamsTests {
    /// The full loop the bug broke: save a config → write it back → the
    /// generated preview document must carry the new values.
    func test_configWriteBack_changesWhatThePreviewRenders() {
        let entry = """
        const Strands = ({ count = 3, speed = 0.5, glass = false, hidden = 1 }) => null;
        export default Strands;
        """
        let usage = """
        import Strands from './Strands';

        <Strands
          count={3}
          speed={0.5}
          glass={false}
        />
        """
        let values: [String: PreviewParamValue] = [
            "count": .number(9), "speed": .number(2), "glass": .boolean(true), "hidden": .number(42)
        ]
        // Params the usage pins go to the usage; the rest to the component.
        let usageParams = PreviewParamDetector.detectJSXUsage(in: usage)
        let pinned = Set(usageParams.map(\.param.name))
        XCTAssertEqual(pinned, ["count", "speed", "glass"])

        let newUsage = PreviewParamWriter.apply(
            values.filter { pinned.contains($0.key) }, to: usage, params: usageParams
        )
        let newEntry = PreviewParamWriter.apply(
            values.filter { !pinned.contains($0.key) }, to: entry,
            params: PreviewParamDetector.detectReact(in: entry)
        )
        XCTAssertTrue(newEntry.contains("hidden = 42"), "unpinned param still writes to the component")
        XCTAssertTrue(newEntry.contains("count = 3"), "pinned param must NOT be written to the component")

        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .react, code: newUsage),
                LinkedSource(language: .react, code: newEntry)
            ],
            entryFlavor: .react,
            appearance: .init(isDark: true, backgroundHex: "#000", textHex: "#fff"),
            runtime: .init(react: "", reactDOM: "", babel: "")
        )
        // The mounted usage element carries the saved values.
        XCTAssertTrue(doc.contains("count={9}"))
        XCTAssertTrue(doc.contains("speed={2}"))
        XCTAssertTrue(doc.contains("glass={true}"))
        XCTAssertFalse(doc.contains("count={3}"))
    }
}

extension PreviewParamsTests {
    /// Regression: an array prop was read as a bare attribute, and the scan
    /// then walked *into* the array and minted params from its contents —
    /// `colors={["#F97316", …]}` produced params named `F97316`, `C3AED`, …
    func test_detectJSXUsage_stepsOverExpressionPropsInsteadOfIntoThem() {
        let usage = """
        <Strands
          colors={["#F97316","#7C3AED","#06B6D4"]}
          onChange={(index, item) => console.log(index, item)}
          items={DEFAULT_ITEMS}
          style={{ width: '100%' }}
          {...rest}
          count={3}
        />
        """
        let names = PreviewParamDetector.detectJSXUsage(in: usage).map(\.param.name)
        XCTAssertEqual(names, ["count"])
        XCTAssertFalse(names.contains { $0.contains("F97316") })
    }

    func test_jsxWriteBack_preservesEachAttributeShape() {
        let usage = #"<OptionWheel side="left" fontSize={3} draggable soundVolume={0.5} />"#
        let out = PreviewParamWriter.apply(
            ["side": .string("right"), "fontSize": .number(4),
             "draggable": .boolean(false), "soundVolume": .number(0.2)],
            to: usage, params: PreviewParamDetector.detectJSXUsage(in: usage)
        )
        XCTAssertEqual(out, #"<OptionWheel side="right" fontSize={4} draggable={false} soundVolume={0.2} />"#)
    }

    func test_jsxWriteBack_leavesUntouchedPropsByteIdentical() {
        let usage = """
        <Strands
          colors={["#F97316","#7C3AED"]}
          count={3}
          onChange={(i) => console.log(i)}
        />
        """
        let out = PreviewParamWriter.apply(
            ["count": .number(7)], to: usage,
            params: PreviewParamDetector.detectJSXUsage(in: usage)
        )
        XCTAssertEqual(out, usage.replacingOccurrences(of: "count={3}", with: "count={7}"))
    }
}

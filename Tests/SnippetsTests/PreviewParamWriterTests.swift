import XCTest
@testable import Snippets

final class PreviewParamWriterTests: XCTestCase {
    func test_replacesGLSLAnnotationInPlace() {
        let code = "uniform float amplitude; // = 1.5\nuniform vec3 tint; // = #ff0000\n"
        let result = PreviewParamWriter.apply(
            ["amplitude": .number(2.25), "tint": .string("#00ff88")],
            to: code,
            params: PreviewParamDetector.detectGLSL(in: code)
        )
        XCTAssertEqual(result, "uniform float amplitude; // = 2.25\nuniform vec3 tint; // = #00ff88\n")
    }

    func test_writesIntegralNumbersWithoutDecimalPoint() {
        let code = "uniform float amplitude; // = 1.5\n"
        let result = PreviewParamWriter.apply(
            ["amplitude": .number(3)], to: code, params: PreviewParamDetector.detectGLSL(in: code)
        )
        XCTAssertEqual(result, "uniform float amplitude; // = 3\n")
    }

    func test_insertsAnnotationWhenMissing() {
        let code = "uniform float amplitude;\n"
        let result = PreviewParamWriter.apply(
            ["amplitude": .number(2)], to: code, params: PreviewParamDetector.detectGLSL(in: code)
        )
        XCTAssertEqual(result, "uniform float amplitude;  // = 2\n")
    }

    func test_preservesReactQuoteStyleAndSurroundingCode() {
        let code = #"const App = ({ amplitude = 1.4, tint = '#ff94b8' }) => <p/>; export default App;"#
        let result = PreviewParamWriter.apply(
            ["amplitude": .number(9), "tint": .string("#000000")],
            to: code,
            params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(result, #"const App = ({ amplitude = 9, tint = '#000000' }) => <p/>; export default App;"#)
    }

    func test_writesBooleans() {
        let code = "export default function App({ rounded = false }) { return <p/> }"
        let result = PreviewParamWriter.apply(
            ["rounded": .boolean(true)], to: code, params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(result, "export default function App({ rounded = true }) { return <p/> }")
    }

    func test_ignoresKeysTheCodeNoLongerDeclares() {
        let code = "uniform float amplitude; // = 1.5\n"
        let result = PreviewParamWriter.apply(
            ["amplitude": .number(2), "removedParam": .number(99)],
            to: code,
            params: PreviewParamDetector.detectGLSL(in: code)
        )
        XCTAssertEqual(result, "uniform float amplitude; // = 2\n")
    }

    func test_leavesUnmentionedParamsUntouched() {
        let code = "uniform float a; // = 1\nuniform float b; // = 2\n"
        let result = PreviewParamWriter.apply(
            ["a": .number(5)], to: code, params: PreviewParamDetector.detectGLSL(in: code)
        )
        XCTAssertEqual(result, "uniform float a; // = 5\nuniform float b; // = 2\n")
    }

    func test_roundTripsThroughDetection() {
        let code = """
        struct SnippetParams {
            float speed; // = 2.0
            float3 tint; // = #112233
        };
        """
        let rewritten = PreviewParamWriter.apply(
            ["speed": .number(4.5), "tint": .string("#aabbcc")],
            to: code,
            params: PreviewParamDetector.detectMetal(in: code)
        )
        let reDetected = PreviewParamDetector.metalParams(in: rewritten)
        XCTAssertEqual(reDetected[0].kind, .number(default: 4.5))
        XCTAssertEqual(reDetected[1].kind, .color(defaultHex: "#aabbcc"))
    }

    // MARK: - Escaping
    //
    // A `.text` param is edited through a free-form TextField, so its value can
    // contain the very delimiter it is written back inside. Without escaping,
    // saving such a value emits invalid source AND breaks re-detection, which
    // makes the parameter controls disappear — leaving no way to fix it in-app.

    private static let textSnippet = #"const App = ({ label = "waves" }) => <p/>; export default App;"#

    func test_escapesDoubleQuoteInsideDoubleQuotedLiteral() {
        let code = Self.textSnippet
        let result = PreviewParamWriter.apply(
            ["label": .string("he said \"hi\"")],
            to: code, params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(
            result,
            #"const App = ({ label = "he said \"hi\"" }) => <p/>; export default App;"#
        )
    }

    func test_escapesSingleQuoteInsideSingleQuotedLiteral() {
        let code = #"const App = ({ label = 'waves' }) => <p/>; export default App;"#
        let result = PreviewParamWriter.apply(
            ["label": .string("it's fine")],
            to: code, params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(
            result,
            #"const App = ({ label = 'it\'s fine' }) => <p/>; export default App;"#
        )
    }

    func test_escapesBackslash() {
        let code = Self.textSnippet
        let result = PreviewParamWriter.apply(
            ["label": .string(#"a\b"#)],
            to: code, params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(
            result,
            #"const App = ({ label = "a\\b" }) => <p/>; export default App;"#
        )
    }

    func test_escapesNewlineRatherThanBreakingTheLiteral() {
        let code = Self.textSnippet
        let result = PreviewParamWriter.apply(
            ["label": .string("line1\nline2")],
            to: code, params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(
            result,
            #"const App = ({ label = "line1\nline2" }) => <p/>; export default App;"#
        )
        XCTAssertFalse(result.contains("\n"), "the literal must stay on one line")
    }

    /// The regression that matters most: a quote-containing value must not
    /// destroy detection, or the controls vanish and the value is unfixable.
    func test_paramStillDetectableAfterWritingQuotedValue() {
        let code = Self.textSnippet
        let result = PreviewParamWriter.apply(
            ["label": .string("he said \"hi\"")],
            to: code, params: PreviewParamDetector.detectReact(in: code)
        )
        XCTAssertEqual(PreviewParamDetector.reactParams(in: result).map(\.name), ["label"])
    }

    /// The `// = value` annotation path has no delimiter to escape, but a
    /// newline would still swallow the rest of the declaration into a comment.
    /// Escaping on write is only half the contract — the detector must decode
    /// it again, or the value the user sees drifts from the value stored.
    func test_awkwardValueSurvivesFullRoundTrip() {
        let code = Self.textSnippet
        for awkward in ["he said \"hi\"", "it's fine", #"a\b"#, "line1\nline2", "plain"] {
            let rewritten = PreviewParamWriter.apply(
                ["label": .string(awkward)],
                to: code, params: PreviewParamDetector.detectReact(in: code)
            )
            let redetected = PreviewParamDetector.reactParams(in: rewritten)
            XCTAssertEqual(redetected.count, 1, "lost the param for \(awkward.debugDescription)")
            XCTAssertEqual(
                redetected.first?.kind,
                .text(default: awkward),
                "value drifted for \(awkward.debugDescription)"
            )
        }
    }

    func test_annotationValueNeverBreaksItsLine() {
        let code = "uniform float amplitude;\n"
        let result = PreviewParamWriter.apply(
            ["amplitude": .string("1\n2")],
            to: code, params: PreviewParamDetector.detectGLSL(in: code)
        )
        XCTAssertEqual(result, "uniform float amplitude;  // = 1 2\n")
    }
}

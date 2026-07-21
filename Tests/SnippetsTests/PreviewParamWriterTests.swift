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
}

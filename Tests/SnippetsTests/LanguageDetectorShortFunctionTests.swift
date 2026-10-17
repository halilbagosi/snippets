import XCTest
@testable import Snippets

/// One-function snippets copied out of another app. They carry almost no
/// evidence, so a single shared shape — `name: Type` parameters — used to
/// outvote Swift and tag a Swift function as TypeScript.
final class LanguageDetectorShortFunctionTests: XCTestCase {

    // MARK: Swift

    func test_swiftLerp_isSwift() {
        let code = """
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            a + (b - a) * t
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .swift)
    }

    func test_swiftLerp_clipboardCandidateIsSwift() {
        let code = """
        func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
            a + (b - a) * t
        }
        """
        let candidate = ClipboardCapture.candidate(text: code, types: [], isOwnWrite: false)
        XCTAssertEqual(candidate?.language, .swift)
    }

    func test_swiftLabelledParameters_isSwift() {
        let code = """
        func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
            min(max(value, range.lowerBound), range.upperBound)
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .swift)
    }

    func test_swiftFuncWithReturnArrow_isSwift() {
        let code = """
        func greeting(for name: String, count: Int) -> String {
            "Hello, \\(name) ×\\(count)"
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .swift)
    }

    // MARK: TypeScript

    func test_typeScriptLerp_isTypeScript() {
        let code = """
        function lerp(a: number, b: number, t: number): number {
            return a + (b - a) * t;
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .typescript)
    }

    func test_typeScriptArrowWithClassTypes_isTypeScript() {
        let code = """
        const distance = (a: Point, b: Point): number => {
            return Math.hypot(a.x - b.x, a.y - b.y);
        };
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .typescript)
    }

    func test_typeScriptFunctionReturningClassType_isTypeScript() {
        let code = """
        function toDate(value: string, fallback: Date): Date {
            const parsed = new Date(value);
            return isNaN(parsed.getTime()) ? fallback : parsed;
        }
        """
        XCTAssertEqual(LanguageDetector.detect(code: code), .typescript)
    }
}

import XCTest
@testable import Snippets

/// The structural gate in front of `LanguageDetector`.
///
/// `LanguageDetector` answers "which language is this code?" and was tuned on
/// a corpus already known to be code, so arbitrary clipboard text is out of
/// distribution for it. These negative cases are what stop the capture prompt
/// from firing on ordinary copied prose.
final class CodeShapeHeuristicsTests: XCTestCase {

    // MARK: Positives

    func test_swiftFunction_isCode() {
        let text = """
        func parse(_ input: String) -> Int {
            return input.count
        }
        """
        XCTAssertTrue(CodeShapeHeuristics.isLikelyCode(text))
    }

    func test_pythonFunction_isCode() {
        let text = """
        def greet(name):
            print(f"hello {name}")
        """
        XCTAssertTrue(CodeShapeHeuristics.isLikelyCode(text))
    }

    func test_javascriptOneLiner_isCode() {
        XCTAssertTrue(CodeShapeHeuristics.isLikelyCode(
            "const x = items.filter(i => i.active).map(i => i.id);"
        ))
    }

    func test_json_isCode() {
        XCTAssertTrue(CodeShapeHeuristics.isLikelyCode(
            #"{"name": "snippets", "version": "1.0.0", "private": true}"#
        ))
    }

    /// Shell one-liners have low symbol density and no keywords — the flag
    /// signal is what carries them.
    func test_shellCommandWithFlag_isCode() {
        XCTAssertTrue(CodeShapeHeuristics.isLikelyCode(
            #"git commit -m "fix the parser" && git push origin main"#
        ))
    }

    func test_fencedBlock_isCode() {
        let text = """
        ```
        SELECT name FROM users
        ```
        """
        XCTAssertTrue(CodeShapeHeuristics.isLikelyCode(text))
    }

    // MARK: Negatives

    func test_plainProse_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode(
            "The quick brown fox jumps over the lazy dog and keeps running."
        ))
    }

    /// A stray bracket in a sentence must not be enough on its own.
    func test_proseWithParentheses_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode(
            "We met at the cafe (the one on Fifth) and talked for hours about it."
        ))
    }

    func test_bareURL_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode(
            "https://example.com/some/very/long/path?query=value"
        ))
    }

    func test_singleWord_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode("Snippets"))
    }

    func test_personName_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode("Halil Bagosi"))
    }

    func test_shortText_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode("x = 1"))
    }

    func test_markdownProse_isNotCode() {
        let text = """
        ## Installation

        Run the installer and follow the prompts.
        """
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode(text))
    }

    func test_emptyAndWhitespace_isNotCode() {
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode(""))
        XCTAssertFalse(CodeShapeHeuristics.isLikelyCode("        \n\n   "))
    }
}

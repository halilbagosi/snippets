#if !APP_STORE
import XCTest
@testable import Snippets

final class EfficiencyResponseParserTests: XCTestCase {
    private let code = "for i in 0..<n { work(i) }\nlet x = 1\n"

    private func sugg(before: String = "let x = 1", after: String = "let x = 2", impact: String = "high") -> String {
        #"{"title":"T","impact":"\#(impact)","explanation":"E","before":"\#(before)","after":"\#(after)"}"#
    }

    private func report(score: String = "80", summary: String = #""ok""#, suggestions: [String] = []) -> String {
        #"{"applicable":true,"score":\#(score),"summary":\#(summary),"suggestions":[\#(suggestions.joined(separator: ","))]}"#
    }

    private func assertInvalid(_ json: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try EfficiencyResponseParser.parse(json, ratedCode: code), file: file, line: line) {
            guard case .invalidResponse = $0 as? EfficiencyRatingError else {
                return XCTFail("expected invalidResponse, got \($0)", file: file, line: line)
            }
        }
    }

    func test_validResponseParses() throws {
        let r = try EfficiencyResponseParser.parse(report(suggestions: [sugg()]), ratedCode: code)
        XCTAssertEqual(r.score, 80)
        XCTAssertEqual(r.summary, "ok")
        XCTAssertEqual(r.suggestions.count, 1)
        XCTAssertEqual(r.suggestions[0].impact, .high)
        XCTAssertEqual(r.suggestions[0].after, "let x = 2")
    }

    func test_notApplicableParses() throws {
        let r = try EfficiencyResponseParser.parse(
            #"{"applicable":false,"notApplicableReason":"pure config","summary":"n/a"}"#, ratedCode: code)
        XCTAssertNil(r.score)
        XCTAssertEqual(r.notApplicableReason, "pure config")
        XCTAssertTrue(r.suggestions.isEmpty)
    }

    func test_notApplicableIgnoresScore() throws {
        let r = try EfficiencyResponseParser.parse(
            #"{"applicable":false,"notApplicableReason":"r","score":50,"summary":"s"}"#, ratedCode: "x")
        XCTAssertNil(r.score)
        XCTAssertEqual(r.notApplicableReason, "r")
    }

    func test_notApplicableNeedsReason() {
        assertInvalid(#"{"applicable":false,"summary":"s"}"#)
        assertInvalid(#"{"applicable":false,"notApplicableReason":" ","summary":"s"}"#)
    }

    func test_badScoreIsInvalid() {
        assertInvalid(report(score: "101"))
        assertInvalid(report(score: "-1"))
        assertInvalid(report(score: "7.5"))
        assertInvalid(report(score: "true"))
        assertInvalid(report(score: #""80""#))
        assertInvalid(#"{"applicable":true,"summary":"s"}"#)
    }

    func test_summaryRules() {
        assertInvalid(#"{"applicable":true,"score":5}"#)
        assertInvalid(report(summary: "\"\(String(repeating: "a", count: 201))\""))
    }

    func test_wrongImpactIsInvalid() {
        assertInvalid(report(suggestions: [sugg(impact: "critical")]))
    }

    func test_notJSONIsInvalid() {
        assertInvalid("sure, here you go")
        assertInvalid("[1,2]")
    }

    func test_tooManySuggestionsIsInvalid() {
        assertInvalid(report(suggestions: Array(repeating: sugg(), count: 9)))
    }

    func test_overlongTitleIsInvalid() {
        let long = String(repeating: "a", count: 81)
        assertInvalid(report(suggestions: [sugg().replacingOccurrences(of: #""T""#, with: "\"\(long)\"")]))
    }

    func test_absentAmbiguousEmptyAndNoopSuggestionsAreDroppedOthersSurvive() throws {
        let dup = "let x = 1\nlet x = 1\n"
        let r = try EfficiencyResponseParser.parse(
            report(suggestions: [
                sugg(before: "not in code"),
                sugg(before: ""),
                sugg(before: "let x = 1", after: "let x = 1"),
                sugg(before: "work(i)", after: "work2(i)"),
            ]), ratedCode: code)
        XCTAssertEqual(r.suggestions.map(\.before), ["work(i)"])

        let ambiguous = try EfficiencyResponseParser.parse(
            report(suggestions: [sugg(before: "let x = 1")]), ratedCode: dup)
        XCTAssertTrue(ambiguous.suggestions.isEmpty)
        XCTAssertEqual(ambiguous.score, 80)
    }

    func test_overlongExplanationIsInvalid() {
        let long = String(repeating: "a", count: 601)
        assertInvalid(report(suggestions: [sugg().replacingOccurrences(of: #""E""#, with: "\"\(long)\"")]))
    }

    func test_suggestionNotAnObjectIsInvalid() {
        assertInvalid(report(suggestions: ["\"nope\""]))
    }

    func test_suggestionsNotAnArrayIsInvalid() {
        assertInvalid(#"{"applicable":true,"score":5,"summary":"s","suggestions":"x"}"#)
    }
}
#endif

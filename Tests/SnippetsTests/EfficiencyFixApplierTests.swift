import SwiftData
import XCTest
@testable import Snippets

final class EfficiencyFixApplierTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Snippet.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
    }

    private func makeSnippet(code: String = "a = 1") -> Snippet {
        let snippet = Snippet(title: "s", language: "Swift", code: code)
        snippet.uuid = UUID()
        context.insert(snippet)
        return snippet
    }

    private func review(
        rated: String, before: String = "1", after: String = "2"
    ) -> (EfficiencyReview, EfficiencyReview.Suggestion) {
        let suggestion = EfficiencyReview.Suggestion(
            id: UUID(), title: "Faster", impact: .high, explanation: "", before: before, after: after)
        let review = EfficiencyReview(
            id: UUID(), codeHash: EfficiencyReviewStore.hash(of: rated), ratedCode: rated,
            rubricVersion: EfficiencyRubric.version, score: 60, notApplicableReason: nil,
            summary: "", suggestions: [suggestion], agent: "claudeCode", model: nil, date: .now)
        return (review, suggestion)
    }

    @discardableResult
    private func saveAsNew(
        _ snippet: Snippet, _ review: EfficiencyReview, _ suggestion: EfficiencyReview.Suggestion,
        name: String = "Fast", forget: @escaping (UUID?) -> Void = { _ in }
    ) -> Bool {
        EfficiencyFixApplier.saveAsNew(
            snippet: snippet, review: review, suggestion: suggestion, name: name, overrides: [:],
            declared: { [] }, applyValues: { _ in }, forgetTrust: forget)
    }

    private func select(_ id: UUID, _ snippet: Snippet, applying values: @escaping ([String: PreviewParamValue]) -> Void = { _ in }) {
        EfficiencyFixApplier.select(id: id, in: snippet, declared: { [] }, applyValues: values)
    }

    private func config(_ name: String, in snippet: Snippet) -> PreviewParamConfig {
        snippet.paramConfigs.first { $0.name == name }!
    }

    func test_saveAsNew_buildsFromRatedCodeEvenWhileAnotherVariantIsActive() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1")
        saveAsNew(snippet, r, s, name: "One")
        XCTAssertEqual(snippet.code, "a = 2")
        // User drifts the active variant, then applies a second fix from the same rating.
        snippet.code = "a = 2 // edited"
        let (_, other) = review(rated: "a = 1", before: "a = 1", after: "a = 3")
        saveAsNew(snippet, r, other, name: "Two")
        XCTAssertEqual(snippet.code, "a = 3")
        XCTAssertEqual(config("Two", in: snippet).code, "a = 3")
        XCTAssertEqual(snippet.activeParamConfigID, config("Two", in: snippet).id)
        XCTAssertEqual(config("Two", in: snippet).sourceReviewID, r.id)
        // The outgoing variant was flushed, not lost.
        XCTAssertEqual(config("One", in: snippet).code, "a = 2 // edited")
    }

    func test_saveAsNew_defaultCapturesPreFixCode() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1")
        saveAsNew(snippet, r, s)
        XCTAssertEqual(snippet.paramConfigs.first(where: \.isDefault)?.code, "a = 1")
    }

    func test_saveAsNew_refusedWhenBeforeNoLongerMatchesRatedCode() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1", before: "zzz")
        XCTAssertFalse(saveAsNew(snippet, r, s))
        XCTAssertEqual(snippet.code, "a = 1")
        XCTAssertTrue(snippet.paramConfigs.isEmpty)
    }

    func test_switchingAToDefaultToA_roundTripsAnEditMadeWhileAWasActive() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1")
        saveAsNew(snippet, r, s, name: "A")
        let a = config("A", in: snippet).id, def = config("Default", in: snippet).id
        snippet.code = "a = 2 // my edit"
        select(def, snippet)
        XCTAssertEqual(snippet.code, "a = 1")
        select(a, snippet)
        XCTAssertEqual(snippet.code, "a = 2 // my edit")
    }

    func test_selectingValuesOnlyConfigAfterCodeConfig_restoresDefaultCodeFirst() {
        let snippet = makeSnippet(code: "a = 1")
        let valuesOnly = PreviewParamConfig(
            id: UUID(), name: "Big", values: ["size": .number(4)], isDefault: false)
        snippet.paramConfigs = [valuesOnly]
        let (r, s) = review(rated: "a = 1")
        saveAsNew(snippet, r, s, name: "A")
        XCTAssertEqual(snippet.code, "a = 2")
        var codeSeenWhenApplyingValues: String?
        select(valuesOnly.id, snippet) { _ in codeSeenWhenApplyingValues = snippet.code }
        XCTAssertEqual(codeSeenWhenApplyingValues, "a = 1")
        XCTAssertEqual(snippet.code, "a = 1")
    }

    func test_selectingValuesOnlyConfig_withNoCodeConfigs_leavesCodeAlone() {
        let snippet = makeSnippet(code: "a = 1")
        let big = PreviewParamConfig(id: UUID(), name: "Big", values: [:], isDefault: false)
        snippet.paramConfigs = [big]
        select(big.id, snippet)
        XCTAssertEqual(snippet.code, "a = 1")
    }

    func test_deletingActiveCodeConfig_restoresDefaultCode() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1")
        saveAsNew(snippet, r, s, name: "A")
        EfficiencyFixApplier.delete(id: config("A", in: snippet).id, from: snippet)
        XCTAssertEqual(snippet.code, "a = 1")
        XCTAssertEqual(snippet.activeParamConfigID, config("Default", in: snippet).id)
        XCTAssertNil(snippet.paramConfigs.first { $0.name == "A" })
    }

    func test_deletingAnotherConfig_flushesActiveCode() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1")
        saveAsNew(snippet, r, s, name: "A")
        let (_, other) = review(rated: "a = 1", before: "a = 1", after: "a = 3")
        saveAsNew(snippet, r, other, name: "B")
        snippet.code = "a = 3 // edit"
        EfficiencyFixApplier.delete(id: config("A", in: snippet).id, from: snippet)
        XCTAssertEqual(config("B", in: snippet).code, "a = 3 // edit")
        XCTAssertEqual(snippet.code, "a = 3 // edit")
    }

    func test_addToActive_appliesToCurrentCode_andRefusedWhenBeforeNoLongerMatches() {
        let snippet = makeSnippet(code: "a = 1\nb = 5")
        let (r, s) = review(rated: "a = 1\nb = 5")
        saveAsNew(snippet, r, s, name: "A")
        let second = EfficiencyReview.Suggestion(
            id: UUID(), title: "t", impact: .low, explanation: "", before: "b = 5", after: "b = 6")
        XCTAssertTrue(EfficiencyFixApplier.addToActive(
            snippet: snippet, review: r, suggestion: second, forgetTrust: { _ in }))
        XCTAssertEqual(snippet.code, "a = 2\nb = 6")

        snippet.code = "totally different"
        let third = EfficiencyReview.Suggestion(
            id: UUID(), title: "t", impact: .low, explanation: "", before: "b = 6", after: "b = 7")
        XCTAssertFalse(EfficiencyFixApplier.addToActive(
            snippet: snippet, review: r, suggestion: third, forgetTrust: { _ in }))
        XCTAssertEqual(snippet.code, "totally different")
    }

    func test_addToActive_refusedWhenActiveConfigCameFromAnotherRating() {
        let snippet = makeSnippet(code: "a = 1\nb = 5")
        let (r, s) = review(rated: "a = 1\nb = 5")
        saveAsNew(snippet, r, s, name: "A")
        let (otherReview, _) = review(rated: "a = 1\nb = 5")
        let second = EfficiencyReview.Suggestion(
            id: UUID(), title: "t", impact: .low, explanation: "", before: "b = 5", after: "b = 6")
        XCTAssertFalse(EfficiencyFixApplier.addToActive(
            snippet: snippet, review: otherReview, suggestion: second, forgetTrust: { _ in }))
    }

    func test_apply_revokesTrust_forEveryAffectedSnippet() {
        let dependency = makeSnippet(code: "a = 1")
        let dependent = makeSnippet(code: "use")
        dependent.dependencies = [dependency]
        let (r, s) = review(rated: "a = 1")
        var forgotten: [UUID?] = []
        saveAsNew(dependency, r, s, forget: { forgotten.append($0) })
        XCTAssertEqual(Set(forgotten.compactMap { $0 }), [dependency.uuid!, dependent.uuid!])

        forgotten = []
        let again = EfficiencyReview.Suggestion(
            id: UUID(), title: "t", impact: .low, explanation: "", before: "a = 2", after: "a = 9")
        XCTAssertTrue(EfficiencyFixApplier.addToActive(
            snippet: dependency, review: r, suggestion: again, forgetTrust: { forgotten.append($0) }))
        XCTAssertEqual(Set(forgotten.compactMap { $0 }), [dependency.uuid!, dependent.uuid!])
    }

    func test_apply_prunesRatingsNothingReferences() {
        let snippet = makeSnippet(code: "a = 1")
        let (r, s) = review(rated: "a = 1")
        let (stray, _) = review(rated: "old code")
        var newer = r; newer.date = .now.addingTimeInterval(10)
        var oldStray = stray; oldStray.date = .now.addingTimeInterval(-100)
        snippet.efficiencyReviews = [oldStray, newer]
        saveAsNew(snippet, newer, s)
        XCTAssertEqual(snippet.efficiencyReviews.map(\.id), [newer.id])
    }
}

#if !APP_STORE
import XCTest
@testable import Snippets

final class EfficiencyPanelStateTests: XCTestCase {
    private func suggestion(before: String = "a", after: String = "b") -> EfficiencyReview.Suggestion {
        EfficiencyReview.Suggestion(
            id: UUID(), title: "t", impact: .high, explanation: "", before: before, after: after)
    }

    private func review(
        code: String = "a = 1", score: Int? = 60, date: Date = .now,
        suggestions: [EfficiencyReview.Suggestion] = []
    ) -> EfficiencyReview {
        EfficiencyReview(
            id: UUID(), codeHash: EfficiencyReviewStore.hash(of: code), ratedCode: code,
            rubricVersion: EfficiencyRubric.version, score: score,
            notApplicableReason: score == nil ? "tiny" : nil, summary: "s",
            suggestions: suggestions, agent: "claudeCode", model: nil, date: date)
    }

    private func derive(
        job: EfficiencyRatingCenter.Job.State? = nil, fresh: EfficiencyReview? = nil,
        latest: EfficiencyReview? = nil, active: PreviewParamConfig? = nil,
        reviews: [EfficiencyReview] = []
    ) -> EfficiencyPanelState {
        .derive(job: job, fresh: fresh, latest: latest, activeConfig: active, reviews: reviews)
    }

    private func config(source: UUID?) -> PreviewParamConfig {
        PreviewParamConfig(id: UUID(), name: "Fast", values: [:], isDefault: false, code: "x", sourceReviewID: source)
    }

    func testNothingStoredIsNotRated() {
        XCTAssertEqual(derive().content, .notRated)
    }

    func testRunningWinsOverEverything() {
        let r = review()
        XCTAssertEqual(derive(job: .running, fresh: r, latest: r).content, .rating)
    }

    func testFreshScoredIsRatedAndNotApplicableHasItsOwnState() {
        let scored = review(), na = review(score: nil)
        XCTAssertEqual(derive(fresh: scored, latest: scored).content, .rated(scored))
        XCTAssertEqual(derive(fresh: na, latest: na).content, .notApplicable(na))
    }

    func testOldRatingOfOtherCodeIsStale() {
        let old = review(code: "old")
        XCTAssertEqual(derive(latest: old).content, .stale(old))
    }

    func testFailureKeepsPreviousRatingVisible() {
        let r = review()
        let state = derive(job: .failed(.timedOut), fresh: r, latest: r)
        XCTAssertEqual(state.content, .rated(r))
        XCTAssertEqual(state.failure, .timedOut)
    }

    func testFailureWithoutRatingStaysNotRated() {
        let state = derive(job: .failed(.cancelled))
        XCTAssertEqual(state.content, .notRated)
        XCTAssertEqual(state.failure, .cancelled)
    }

    func testSucceededJobCarriesNoFailure() {
        XCTAssertNil(derive(job: .succeeded(score: 80, band: .good)).failure)
    }

    func testConfigBornFromRatingShowsNotRatedWithInheritedSource() {
        let source = review(code: "src")
        let active = config(source: source.id)
        let state = derive(latest: source, active: active, reviews: [source])
        XCTAssertEqual(state.content, .notRated)
        XCTAssertEqual(state.inherited, .init(review: source, configName: "Fast"))
    }

    func testOwnFreshRatingBeatsInheritedSource() {
        let source = review(code: "src"), own = review()
        let state = derive(fresh: own, latest: own, active: config(source: source.id), reviews: [source, own])
        XCTAssertEqual(state.content, .rated(own))
        XCTAssertNil(state.inherited)
    }

    func testMissingSourceFallsBackToStale() {
        let old = review(code: "old")
        let state = derive(latest: old, active: config(source: UUID()), reviews: [old])
        XCTAssertEqual(state.content, .stale(old))
        XCTAssertNil(state.inherited)
    }

    func testVisibility() {
        func v(_ l: SupportedLanguage, enabled: Bool = true, cli: Bool = true, expanded: Bool = false) -> Bool {
            EfficiencyPanelState.isVisible(language: l, enabled: enabled, cliFound: cli, previewExpanded: expanded)
        }
        XCTAssertTrue(v(.swift))
        XCTAssertFalse(v(.json))
        XCTAssertFalse(v(.unknown))
        XCTAssertFalse(v(.swift, enabled: false))
        XCTAssertFalse(v(.swift, cli: false))
        XCTAssertFalse(v(.swift, expanded: true))
    }

    func testFailureLines() {
        let line = EfficiencyPanelState.failureLine
        XCTAssertEqual(line(.agentNotFound), "Agent not installed")
        XCTAssertEqual(line(.notSignedIn), "Not signed in to the agent")
        XCTAssertEqual(line(.timedOut), "Timed out")
        XCTAssertEqual(line(.invalidResponse("x")), "Invalid response from the agent")
        XCTAssertEqual(line(.cancelled), "Cancelled")
        XCTAssertEqual(line(.failed("boom\nstack")), "boom")
        XCTAssertEqual(line(.failed("  ")), "Rating failed")
        XCTAssertEqual(line(.failed(String(repeating: "x", count: 200))).count, 91)
    }

    private func act(
        _ s: EfficiencyReview.Suggestion, rated: String, active: String,
        _ context: EfficiencyPanelState.Context, canAdd: Bool = false
    ) -> EfficiencyPanelState.SuggestionAction {
        EfficiencyPanelState.action(
            for: s, in: review(code: rated, suggestions: [s]), context: context,
            activeCode: active, canAddToActive: canAdd)
    }

    func testFreshActionChecksRatedCode() {
        let s = suggestion(before: "a")
        XCTAssertEqual(act(s, rated: "a = 1", active: "a = 1", .fresh, canAdd: true), .offer(addToActive: true))
        XCTAssertEqual(act(s, rated: "a = 1", active: "a = 1", .fresh), .offer(addToActive: false))
        XCTAssertEqual(act(suggestion(before: "nope"), rated: "a = 1", active: "a = 1", .fresh), .noLongerApplies)
    }

    func testStaleActionChecksCurrentCodeAndNeverOffersAddToActive() {
        let s = suggestion(before: "loop")
        XCTAssertEqual(act(s, rated: "loop", active: "loop // edited", .stale, canAdd: true), .offer(addToActive: false))
        XCTAssertEqual(act(s, rated: "loop", active: "rewritten", .stale), .noLongerApplies)
        XCTAssertEqual(act(s, rated: "loop", active: "loop loop", .stale), .noLongerApplies)
    }

    func testInheritedActionBranches() {
        let s = suggestion(before: "slow", after: "fast")
        // Already in the active code.
        XCTAssertEqual(act(s, rated: "slow", active: "fast", .inherited), .applied)
        // Still matches the active code: both actions.
        XCTAssertEqual(act(s, rated: "slow", active: "slow x", .inherited, canAdd: true), .offer(addToActive: true))
        // Only the rated code matches: save as new only.
        XCTAssertEqual(act(s, rated: "slow", active: "other", .inherited, canAdd: true), .offer(addToActive: false))
        // Matches nowhere.
        XCTAssertEqual(act(s, rated: "gone", active: "other", .inherited), .noLongerApplies)
        // `after` present but `before` too: not applied.
        XCTAssertEqual(act(s, rated: "slow", active: "fast slow", .inherited, canAdd: true), .offer(addToActive: true))
    }

    func testInheritedDeletionCountsAsAppliedWhenBeforeIsGone() {
        let s = suggestion(before: "debugPrint(x)\n", after: "")
        XCTAssertEqual(act(s, rated: "a\ndebugPrint(x)\nb", active: "a\nb", .inherited), .applied)
        // Still present: not applied.
        XCTAssertNotEqual(act(s, rated: "a\ndebugPrint(x)\nb", active: "a\ndebugPrint(x)\nb", .inherited), .applied)
        // `before` was not unique in the rated code: cannot tell.
        XCTAssertNotEqual(act(s, rated: "debugPrint(x)\ndebugPrint(x)\n", active: "", .inherited), .applied)
    }

    func testSaveBase() {
        XCTAssertEqual(EfficiencyPanelState.saveBase(for: .fresh), .ratedCode)
        XCTAssertEqual(EfficiencyPanelState.saveBase(for: .inherited), .ratedCode)
        XCTAssertEqual(EfficiencyPanelState.saveBase(for: .stale), .currentCode)
    }
}
#endif

import XCTest
@testable import Snippets

final class EfficiencyReviewStoreTests: XCTestCase {
    private func review(
        code: String = "code", version: Int = EfficiencyRubric.version,
        date: TimeInterval = 0, id: UUID = UUID()
    ) -> EfficiencyReview {
        EfficiencyReview(
            id: id, codeHash: EfficiencyReviewStore.hash(of: code), ratedCode: code,
            rubricVersion: version, score: 80, notApplicableReason: nil, summary: "",
            suggestions: [], agent: "claudeCode", model: nil,
            date: Date(timeIntervalSince1970: date)
        )
    }

    private func suggestion(before: String, after: String = "NEW") -> EfficiencyReview.Suggestion {
        .init(id: UUID(), title: "t", impact: .high, explanation: "", before: before, after: after)
    }

    func test_hashIsLowercaseHexSHA256() {
        XCTAssertEqual(
            EfficiencyReviewStore.hash(of: "abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func test_bandCutoffs() {
        let expected: [(Int, EfficiencyBand)] = [
            (0, .poor), (49, .poor), (50, .fair), (74, .fair),
            (75, .good), (89, .good), (90, .excellent), (100, .excellent)
        ]
        for (score, band) in expected {
            XCTAssertEqual(EfficiencyBand(score: score), band, "score \(score)")
        }
        XCTAssertEqual(EfficiencyBand.excellent.label, "Excellent")
        XCTAssertEqual(EfficiencyBand.good.label, "Good")
        XCTAssertEqual(EfficiencyBand.fair.label, "Fair")
        XCTAssertEqual(EfficiencyBand.poor.label, "Poor")
    }

    func test_stalenessOnCodeChangeAndRubricBumpOnly() {
        let fresh = review(code: "a")
        XCTAssertFalse(EfficiencyReviewStore.isStale(fresh, currentCode: "a"))
        XCTAssertTrue(EfficiencyReviewStore.isStale(fresh, currentCode: "b"))
        XCTAssertTrue(EfficiencyReviewStore.isStale(
            review(code: "a", version: EfficiencyRubric.version + 1), currentCode: "a"
        ))
        var other = fresh
        other.agent = "codex"
        other.model = "x"
        XCTAssertFalse(EfficiencyReviewStore.isStale(other, currentCode: "a"))
    }

    func test_reviewMatchingAndLatest() {
        let old = review(code: "a", date: 1)
        let newer = review(code: "a", date: 5)
        let other = review(code: "b", date: 9)
        let all = [old, newer, other]
        XCTAssertEqual(
            EfficiencyReviewStore.review(matching: "a", rubricVersion: 1, in: all)?.id, newer.id
        )
        XCTAssertNil(EfficiencyReviewStore.review(matching: "a", rubricVersion: 2, in: all))
        XCTAssertNil(EfficiencyReviewStore.review(matching: "zzz", rubricVersion: 1, in: all))
        XCTAssertEqual(EfficiencyReviewStore.latest(in: all)?.id, other.id)
        XCTAssertNil(EfficiencyReviewStore.latest(in: []))
    }

    func test_pruningKeepsLatestHashMatchedAndSourceReferenced() {
        let sourceID = UUID()
        let referenced = review(code: "r", date: 1, id: sourceID)
        let configMatched = review(code: "variant", date: 2)
        let currentMatched = review(code: "current", date: 3)
        let orphan = review(code: "gone", date: 4)
        let latest = review(code: "newest", date: 10)
        let configs = [
            PreviewParamConfig(
                id: UUID(), name: "V", values: [:], isDefault: false,
                code: "variant", sourceReviewID: sourceID
            )
        ]
        let kept = EfficiencyReviewStore.pruned(
            [referenced, configMatched, currentMatched, orphan, latest],
            configs: configs, currentCode: "current"
        )
        XCTAssertEqual(
            Set(kept.map(\.id)),
            Set([referenced.id, configMatched.id, currentMatched.id, latest.id])
        )
        XCTAssertFalse(kept.contains { $0.id == orphan.id })
    }

    func test_pruningDropsReferenceWhenConfigGone() {
        let a = review(code: "x", date: 1)
        let b = review(code: "y", date: 2)
        let kept = EfficiencyReviewStore.pruned([a, b], configs: [], currentCode: "z")
        XCTAssertEqual(kept.map(\.id), [b.id])
    }

    func test_matchStateExactlyOnce() {
        XCTAssertEqual(
            EfficiencyReviewStore.matchState(of: suggestion(before: "foo"), in: "a bar b"),
            .noLongerApplies
        )
        XCTAssertEqual(
            EfficiencyReviewStore.matchState(of: suggestion(before: "foo"), in: "a foo b"), .applies
        )
        XCTAssertEqual(
            EfficiencyReviewStore.matchState(of: suggestion(before: "foo"), in: "foo foo"),
            .noLongerApplies
        )
        XCTAssertEqual(
            EfficiencyReviewStore.matchState(of: suggestion(before: "aa"), in: "aaa"),
            .noLongerApplies
        )
        XCTAssertEqual(
            EfficiencyReviewStore.matchState(of: suggestion(before: ""), in: "abc"), .noLongerApplies
        )
    }

    func test_applyingReplacesOnlyThatOccurrence() {
        let s = suggestion(before: "slow()", after: "fast()")
        XCTAssertEqual(
            EfficiencyReviewStore.applying(s, to: "x = slow()\ny = ok()"), "x = fast()\ny = ok()"
        )
        XCTAssertNil(EfficiencyReviewStore.applying(s, to: "slow() slow()"))
        XCTAssertNil(EfficiencyReviewStore.applying(s, to: "nothing"))
    }
}

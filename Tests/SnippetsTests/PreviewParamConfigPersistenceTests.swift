import XCTest
import SwiftData
@testable import Snippets

final class PreviewParamConfigPersistenceTests: XCTestCase {
    func test_configsSurviveSaveAndFetch() throws {
        let container = try ModelContainer(
            for: Snippet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let snippet = Snippet(title: "Waves", language: "Metal", code: "uniform float a; // = 1")
        snippet.paramConfigs = [
            PreviewParamConfig(id: UUID(), name: "Default", values: ["a": .number(1)], isDefault: true)
        ]
        snippet.activeParamConfigID = snippet.paramConfigs[0].id
        context.insert(snippet)
        try context.save()

        let fetched = try ModelContext(container).fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].paramConfigs.count, 1)
        XCTAssertEqual(fetched[0].paramConfigs[0].values["a"], .number(1))
        XCTAssertEqual(fetched[0].activeParamConfigID, snippet.paramConfigs[0].id)
    }

    func test_existingSnippetsDefaultToNoConfigs() throws {
        let container = try ModelContainer(
            for: Snippet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let snippet = Snippet(title: "Plain", language: "Swift", code: "let x = 1")
        context.insert(snippet)
        try context.save()
        XCTAssertTrue(snippet.paramConfigs.isEmpty)
        XCTAssertNil(snippet.activeParamConfigID)
    }

    func test_codeConfigAndReviewSurviveSaveAndFetch() throws {
        let container = try ModelContainer(
            for: Snippet.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let snippet = Snippet(title: "Loop", language: "Swift", code: "for i in 0..<n { work(i) }")
        let review = EfficiencyReview(
            id: UUID(), codeHash: EfficiencyReviewStore.hash(of: snippet.code), ratedCode: snippet.code,
            rubricVersion: EfficiencyRubric.version, score: nil, notApplicableReason: "Too small to judge",
            summary: "Nothing to improve",
            suggestions: [.init(id: UUID(), title: "Hoist", impact: .high, explanation: "Why", before: "work(i)", after: "work2(i)")],
            agent: "claudeCode", model: nil, date: .now)
        let config = PreviewParamConfig(
            id: UUID(), name: "Optimized", values: [:], isDefault: false,
            code: "for i in 0..<n { work2(i) }", sourceReviewID: review.id)
        snippet.paramConfigs = [config]
        snippet.efficiencyReviews = [review]
        context.insert(snippet)
        try context.save()

        let fetched = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(fetched.paramConfigs, [config])
        XCTAssertEqual(fetched.efficiencyReviews, [review])
        XCTAssertNil(fetched.efficiencyReviews[0].score)
    }
}

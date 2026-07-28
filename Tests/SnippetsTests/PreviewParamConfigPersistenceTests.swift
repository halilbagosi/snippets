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

        let fetched = try context.fetch(FetchDescriptor<Snippet>())
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
}

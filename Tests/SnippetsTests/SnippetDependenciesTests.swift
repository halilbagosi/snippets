import XCTest
import SwiftData
@testable import Snippets

final class SnippetDependenciesTests: XCTestCase {
    @MainActor
    func test_dependenciesRelationship_persistsAndInverses() throws {
        let container = try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let css = Snippet(title: "Theme", language: "CSS", code: ".a{}")
        let entry = Snippet(title: "Card", language: "React", code: "export default function App(){}")
        context.insert(css)
        context.insert(entry)
        entry.dependencies = [css]
        try context.save()

        XCTAssertEqual(entry.dependencies.map(\.title), ["Theme"])
        XCTAssertEqual(css.dependents.map(\.title), ["Card"])
    }
}

import SwiftData
import XCTest
@testable import Snippets

/// Covers what the pure ranking types cannot: the fetch itself.
@MainActor
final class QuickCopyViewModelTests: XCTestCase {

    /// A throwaway defaults suite, so running the suite never touches the
    /// user's remembered scope.
    private func makeDefaults() -> UserDefaults {
        let suite = "QuickCopyViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return defaults
    }

    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A trashed snippet must never be offered for copying, in any scope.
    func test_trashedSnippetsAreNeverListed() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        context.insert(Snippet(title: "Live", code: "a"))
        context.insert(Snippet(title: "Trashed", code: "b", deletedAt: .now))
        try context.save()

        let model = QuickCopyViewModel(context: context, defaults: makeDefaults())
        model.scope = .recent

        XCTAssertEqual(model.flatResults.map(\.title), ["Live"])
    }

    func test_copySelected_bumpsCopyCountOfTheSelectedSnippet() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        context.insert(Snippet(title: "Only", code: "a"))
        try context.save()

        let model = QuickCopyViewModel(context: context, defaults: makeDefaults())
        model.scope = .recent
        let copied = model.copySelected()

        XCTAssertEqual(copied?.title, "Only")
        XCTAssertEqual(copied?.copyCount, 1)
    }
}

import SwiftData
import XCTest
@testable import Snippets

/// Characterization tests for the App Intents' core logic via the
/// context-injected `execute` twins — they pin current behavior, including
/// error branches, and never touch the shared on-disk container.
@MainActor
final class SnippetIntentLogicTests: XCTestCase {
    // Returns the container: the context alone does not keep it alive, and
    // inserting into a context whose container was deallocated traps.
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: Create

    func test_create_insertsAndPersistsSnippet() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        let created = try CreateSnippetIntent.execute(
            title: "Parser", code: "func parse() {}", language: "Swift",
            collectionID: nil, in: context
        )

        XCTAssertEqual(created.title, "Parser")
        let fetched = try context.fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(fetched.map(\.title), ["Parser"])
        XCTAssertEqual(fetched[0].language, "Swift")
        XCTAssertEqual(fetched[0].code, "func parse() {}")
    }

    func test_create_intoCollection_appendsAndBumpsUpdatedAt() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let collection = SnippetCollection(name: "Utils", updatedAt: .distantPast)
        context.insert(collection)
        try context.save()

        let created = try CreateSnippetIntent.execute(
            title: "Parser", code: "c", language: "Swift",
            collectionID: collection.uuid, in: context
        )

        XCTAssertEqual(created.collections.map(\.name), ["Utils"])
        XCTAssertEqual(collection.snippets.map(\.title), ["Parser"])
        XCTAssertGreaterThan(collection.updatedAt, .distantPast)
    }

    func test_create_withUnknownCollection_throwsCollectionNotFound() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        XCTAssertThrowsError(
            try CreateSnippetIntent.execute(
                title: "Orphan", code: "c", language: "Swift",
                collectionID: UUID(), in: context
            )
        ) { error in
            XCTAssertEqual(error as? SnippetIntentError, .collectionNotFound)
        }

        // Characterization: the snippet is inserted before the collection
        // lookup, so on failure it remains in the (unsaved) context. A
        // deliberate fix would remove it; today's behavior leaves it behind.
        let leftover = try context.fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(leftover.map(\.title), ["Orphan"])
    }

    // MARK: ToggleFavorite

    func test_toggleFavorite_flipsAndPersists() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let snippet = Snippet(title: "A", code: "a")
        context.insert(snippet)
        try context.save()

        _ = try ToggleFavoriteSnippetIntent.execute(snippetID: snippet.uuid!, in: context)
        XCTAssertTrue(snippet.isFavorite)
        _ = try ToggleFavoriteSnippetIntent.execute(snippetID: snippet.uuid!, in: context)
        XCTAssertFalse(snippet.isFavorite)
    }

    func test_toggleFavorite_unknownUUID_throwsSnippetNotFound() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext

        XCTAssertThrowsError(
            try ToggleFavoriteSnippetIntent.execute(snippetID: UUID(), in: context)
        ) { error in
            XCTAssertEqual(error as? SnippetIntentError, .snippetNotFound)
        }
    }

    // MARK: Find

    func test_find_returnsLiveMatches_excludesDeleted_respectsFilters() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let swift = Snippet(title: "Parser", language: "Swift", code: "p")
        let css = Snippet(title: "Theme", language: "CSS", code: "t", isFavorite: true)
        let deleted = Snippet(title: "Parser old", language: "Swift", code: "p", deletedAt: .now)
        context.insert(swift)
        context.insert(css)
        context.insert(deleted)
        try context.save()

        let byText = try FindSnippetsIntent.execute(
            searchText: "Parser", collectionID: nil, favoritesOnly: false, in: context
        )
        XCTAssertEqual(byText.map(\.title), ["Parser"])

        // The query text also matches the language field of the candidate.
        let byLanguage = try FindSnippetsIntent.execute(
            searchText: "CSS", collectionID: nil, favoritesOnly: false, in: context
        )
        XCTAssertEqual(byLanguage.map(\.title), ["Theme"])

        let favorites = try FindSnippetsIntent.execute(
            searchText: nil, collectionID: nil, favoritesOnly: true, in: context
        )
        XCTAssertEqual(favorites.map(\.title), ["Theme"])
    }

    func test_find_backfillsMissingSnippetUUIDs() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let legacy = Snippet(uuid: nil, title: "Legacy", code: "l")
        context.insert(legacy)
        try context.save()

        _ = try FindSnippetsIntent.execute(
            searchText: nil, collectionID: nil, favoritesOnly: false, in: context
        )

        XCTAssertNotNil(legacy.uuid)
    }

    // MARK: Copy

    func test_copy_returnsSnippetAndBumpsCopyCount_unknownThrows() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let snippet = Snippet(title: "A", code: "let a = 1")
        context.insert(snippet)
        try context.save()

        // Clipboard write stays in perform(); execute only looks up + bumps.
        let found = try CopySnippetIntent.execute(snippetID: snippet.uuid!, in: context)
        XCTAssertEqual(found.code, "let a = 1")
        XCTAssertEqual(found.copyCount, 1)

        XCTAssertThrowsError(
            try CopySnippetIntent.execute(snippetID: UUID(), in: context)
        ) { error in
            XCTAssertEqual(error as? SnippetIntentError, .snippetNotFound)
        }
    }
}

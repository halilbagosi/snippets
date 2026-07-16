import SwiftData
import XCTest
@testable import Snippets

/// Tests for the pure gallery filter core extracted in plan 010. The cache
/// signature itself lives in the view; equivalence of cached vs. from-scratch
/// results is covered by deriving search results from the pool here exactly
/// as the cache refresh does.
@MainActor
final class SnippetFilterCacheTests: XCTestCase {
    // Returns the container: the context alone does not keep it alive, and
    // inserting into a context whose container was deallocated traps.
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func searchPool(
        _ snippets: [Snippet],
        favoritesOnly: Bool = false,
        uncategorizedOnly: Bool = false,
        languages: Set<SupportedLanguage> = []
    ) -> [Snippet] {
        GallerySnippetFilter.searchPool(
            snippets: snippets,
            selectedLanguages: languages,
            showUncategorizedOnly: uncategorizedOnly,
            selectedSearchCollections: [],
            showFavoritesOnly: favoritesOnly,
            lookup: [:],
            descendantIDs: [:]
        )
    }

    func test_base_filtersByLanguageFavoritesAndUncategorized() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let collection = SnippetCollection(name: "Utils")
        let swift = Snippet(title: "A", language: "Swift", code: "a")
        let css = Snippet(title: "B", language: "CSS", code: "b", isFavorite: true)
        context.insert(collection)
        context.insert(swift)
        context.insert(css)
        css.collections = [collection]
        try context.save()

        let byLanguage = GallerySnippetFilter.base(
            snippets: [swift, css], selectedLanguages: [.swift],
            selectedCollectionID: nil, showUncategorizedOnly: false,
            selectedSearchCollections: [], showFavoritesOnly: false,
            lookup: [:], descendantIDs: [:]
        )
        XCTAssertEqual(byLanguage.map(\.title), ["A"])

        let favorites = GallerySnippetFilter.base(
            snippets: [swift, css], selectedLanguages: [],
            selectedCollectionID: nil, showUncategorizedOnly: false,
            selectedSearchCollections: [], showFavoritesOnly: true,
            lookup: [:], descendantIDs: [:]
        )
        XCTAssertEqual(favorites.map(\.title), ["B"])

        let uncategorized = GallerySnippetFilter.base(
            snippets: [swift, css], selectedLanguages: [],
            selectedCollectionID: nil, showUncategorizedOnly: true,
            selectedSearchCollections: [], showFavoritesOnly: false,
            lookup: [:], descendantIDs: [:]
        )
        XCTAssertEqual(uncategorized.map(\.title), ["A"])
    }

    func test_base_selectedCollection_requiresDirectMembership() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let parent = SnippetCollection(name: "Parent")
        let child = SnippetCollection(name: "Child", parent: parent)
        let inChild = Snippet(title: "In child", code: "c")
        let loose = Snippet(title: "Loose", code: "l")
        context.insert(parent)
        context.insert(child)
        context.insert(inChild)
        context.insert(loose)
        inChild.collections = [child]
        try context.save()

        let result = GallerySnippetFilter.base(
            snippets: [inChild, loose], selectedLanguages: [],
            selectedCollectionID: parent.persistentModelID, showUncategorizedOnly: false,
            selectedSearchCollections: [], showFavoritesOnly: false,
            lookup: [parent.persistentModelID: parent],
            descendantIDs: [parent.persistentModelID: [parent.persistentModelID, child.persistentModelID]]
        )
        // Direct membership only: the child's snippet is not directly in Parent.
        XCTAssertTrue(result.isEmpty)
    }

    func test_searchResults_matchTitleAndCode_respectNeedle() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let byTitle = Snippet(title: "Parser", code: "x")
        let byCode = Snippet(title: "Other", code: "let parser = 1")
        let neither = Snippet(title: "Nope", code: "y")
        [byTitle, byCode, neither].forEach(context.insert)
        try context.save()

        let hits = GallerySnippetFilter.searchResults(in: [byTitle, byCode, neither], needle: "parser")
        XCTAssertEqual(Set(hits.map(\.title)), ["Parser", "Other"])
        XCTAssertTrue(GallerySnippetFilter.searchResults(in: [byTitle], needle: "").isEmpty)
    }

    func test_searchCollections_excludesDeleted_respectsFavorites() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let live = SnippetCollection(name: "Utilities", isFavorite: true)
        let deleted = SnippetCollection(name: "Util old", deletedAt: .now)
        let other = SnippetCollection(name: "Views")
        [live, deleted, other].forEach(context.insert)
        try context.save()

        let hits = GallerySnippetFilter.searchCollections([live, deleted, other], needle: "util", showFavoritesOnly: false)
        XCTAssertEqual(hits.map(\.name), ["Utilities"])

        let favoriteHits = GallerySnippetFilter.searchCollections([live, other], needle: "i", showFavoritesOnly: true)
        XCTAssertEqual(favoriteHits.map(\.name), ["Utilities"])
    }

    func test_searchResultsFromPool_equalFromScratchComputation() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let fav = Snippet(title: "Parser fav", code: "p", isFavorite: true)
        let plain = Snippet(title: "Parser plain", code: "p")
        [fav, plain].forEach(context.insert)
        try context.save()

        // Regression for the old double-derivation: results computed from the
        // shared pool must equal filtering everything in one pass.
        let pool = searchPool([fav, plain], favoritesOnly: true)
        let derived = GallerySnippetFilter.searchResults(in: pool, needle: "parser")
        let scratch = GallerySnippetFilter.searchResults(
            in: searchPool([fav, plain], favoritesOnly: true), needle: "parser"
        )
        XCTAssertEqual(derived.map(\.title), scratch.map(\.title))
        XCTAssertEqual(derived.map(\.title), ["Parser fav"])
    }
}

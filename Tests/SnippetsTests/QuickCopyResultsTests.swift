import XCTest
@testable import Snippets

/// The ranking engine is pure — these tests build plain value candidates and
/// never touch SwiftData or a ModelContainer.
final class QuickCopyResultsTests: XCTestCase {

    private func candidate(
        _ title: String,
        favorite: Bool = false,
        copies: Int = 0,
        updated: TimeInterval = 0,
        collections: [String] = [],
        language: String = "Swift",
        description: String = ""
    ) -> QuickCopyResults.Candidate {
        QuickCopyResults.Candidate(
            title: title,
            description: description,
            language: language,
            isFavorite: favorite,
            copyCount: copies,
            updatedAt: Date(timeIntervalSince1970: updated),
            collectionNames: collections
        )
    }

    /// Items are their own projection, so ordering assertions read as titles.
    private func sections(
        _ items: [QuickCopyResults.Candidate],
        scope: QuickCopyScope,
        query: String = ""
    ) -> [QuickCopyResults.Section<QuickCopyResults.Candidate>] {
        QuickCopyResults.sections(items, scope: scope, query: query) { $0 }
    }

    private func titles(
        _ sections: [QuickCopyResults.Section<QuickCopyResults.Candidate>]
    ) -> [String] {
        QuickCopyResults.flattened(sections).map(\.title)
    }

    // MARK: Favorites

    func test_favorites_keepsOnlyFavorites_newestFirst() {
        let items = [
            candidate("A", favorite: true, updated: 100),
            candidate("B", favorite: false, updated: 300),
            candidate("C", favorite: true, updated: 200),
        ]
        XCTAssertEqual(titles(sections(items, scope: .favorites)), ["C", "A"])
    }

    func test_favorites_isASingleUnsectionedGroup() {
        let result = sections([candidate("A", favorite: true)], scope: .favorites)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].title)
    }

    // MARK: Frequent

    func test_frequent_excludesNeverCopied() {
        let items = [candidate("A", copies: 0), candidate("B", copies: 1)]
        XCTAssertEqual(titles(sections(items, scope: .frequent)), ["B"])
    }

    func test_frequent_ordersByCopyCountThenRecencyThenTitle() {
        let items = [
            candidate("A", copies: 2, updated: 100),
            candidate("B", copies: 5, updated: 100),
            candidate("C", copies: 2, updated: 900),
            candidate("Z", copies: 2, updated: 100),
        ]
        // B leads on count; C beats the 100-tie on recency; A before Z on title.
        XCTAssertEqual(titles(sections(items, scope: .frequent)), ["B", "C", "A", "Z"])
    }

    // MARK: Recent

    func test_recent_includesEverything_newestFirst() {
        let items = [
            candidate("A", updated: 100),
            candidate("B", updated: 300),
            candidate("C", updated: 200),
        ]
        XCTAssertEqual(titles(sections(items, scope: .recent)), ["B", "C", "A"])
    }

    // MARK: All

    func test_all_sectionsByCollectionNameAlphabetically() {
        let items = [
            candidate("A", collections: ["Utils"]),
            candidate("B", collections: ["Algorithms"]),
        ]
        let result = sections(items, scope: .all)
        XCTAssertEqual(result.map(\.title), ["Algorithms", "Utils"])
    }

    func test_all_sortsWithinSectionByTitle() {
        let items = [
            candidate("Zebra", collections: ["Utils"]),
            candidate("Apple", collections: ["Utils"]),
        ]
        XCTAssertEqual(titles(sections(items, scope: .all)), ["Apple", "Zebra"])
    }

    func test_all_filesMultiCollectionSnippetUnderFirstNameAlphabetically() {
        let items = [candidate("A", collections: ["Utils", "Algorithms"])]
        let result = sections(items, scope: .all)
        XCTAssertEqual(result.map(\.title), ["Algorithms"])
        XCTAssertEqual(titles(result), ["A"])  // appears exactly once
    }

    func test_all_putsUncollectedSnippetsInUngroupedSectionLast() {
        let items = [
            candidate("Loose", collections: []),
            candidate("Filed", collections: ["Utils"]),
        ]
        let result = sections(items, scope: .all)
        XCTAssertEqual(result.map(\.title), ["Utils", QuickCopyResults.ungroupedTitle])
    }

    // MARK: Query

    func test_query_filtersWithinScope() {
        let items = [
            candidate("Parser", favorite: true),
            candidate("Renderer", favorite: true),
        ]
        XCTAssertEqual(titles(sections(items, scope: .favorites, query: "pars")), ["Parser"])
    }

    func test_query_matchesDescriptionAndLanguage() {
        let items = [
            candidate("A", language: "Swift", description: "throttles input"),
            candidate("B", language: "Python", description: "nothing"),
        ]
        XCTAssertEqual(titles(sections(items, scope: .recent, query: "throttle")), ["A"])
        XCTAssertEqual(titles(sections(items, scope: .recent, query: "python")), ["B"])
    }

    func test_emptyQueryMatchesEverything() {
        let items = [candidate("A"), candidate("B")]
        XCTAssertEqual(titles(sections(items, scope: .recent, query: "   ")).count, 2)
    }

    // MARK: Empty

    func test_noMatches_yieldsNoSections() {
        XCTAssertTrue(sections([candidate("A")], scope: .recent, query: "zzz").isEmpty)
    }

    func test_noItems_yieldsNoSections() {
        XCTAssertTrue(sections([], scope: .all).isEmpty)
    }

    // MARK: Scope shortcuts

    func test_shortcutIndexRoundTrips() {
        for scope in QuickCopyScope.allCases {
            XCTAssertEqual(QuickCopyScope.scope(forShortcutIndex: scope.shortcutIndex), scope)
        }
    }

    func test_shortcutIndexOutOfRangeIsNil() {
        XCTAssertNil(QuickCopyScope.scope(forShortcutIndex: 0))
        XCTAssertNil(QuickCopyScope.scope(forShortcutIndex: 5))
    }
}

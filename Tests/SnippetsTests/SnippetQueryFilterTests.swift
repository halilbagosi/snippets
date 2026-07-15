import XCTest
@testable import Snippets

final class SnippetQueryFilterTests: XCTestCase {
    private func candidate(
        title: String = "",
        description: String = "",
        language: String = "Swift",
        isFavorite: Bool = false,
        collectionUUIDs: Set<UUID> = []
    ) -> SnippetQueryFilter.Candidate {
        .init(title: title, description: description, language: language,
              isFavorite: isFavorite, collectionUUIDs: collectionUUIDs)
    }

    private func filter(
        _ items: [SnippetQueryFilter.Candidate],
        query: String? = nil,
        collectionUUID: UUID? = nil,
        favoritesOnly: Bool = false
    ) -> [SnippetQueryFilter.Candidate] {
        SnippetQueryFilter.filter(items, query: query, collectionUUID: collectionUUID,
                                  favoritesOnly: favoritesOnly, projection: { $0 })
    }

    func test_matches_isCaseInsensitiveAcrossFields() {
        XCTAssertTrue(SnippetQueryFilter.matches(title: "Debounce", description: "", language: "Swift", query: "debo"))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "", description: "A JSON helper", language: "Swift", query: "json"))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "", description: "", language: "Python", query: "PYTH"))
        XCTAssertFalse(SnippetQueryFilter.matches(title: "abc", description: "def", language: "Swift", query: "zzz"))
    }

    func test_matches_emptyOrWhitespaceQuery_returnsTrue() {
        XCTAssertTrue(SnippetQueryFilter.matches(title: "a", description: "b", language: "c", query: ""))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "a", description: "b", language: "c", query: "   "))
    }

    func test_filter_nilQuery_returnsAll() {
        let items = [candidate(title: "a"), candidate(title: "b")]
        XCTAssertEqual(filter(items).count, 2)
    }

    func test_filter_query_matchesTitle() {
        let items = [candidate(title: "Debounce"), candidate(title: "Throttle")]
        XCTAssertEqual(filter(items, query: "debo").map(\.title), ["Debounce"])
    }

    func test_filter_favoritesOnly() {
        let items = [candidate(title: "a", isFavorite: true), candidate(title: "b", isFavorite: false)]
        XCTAssertEqual(filter(items, favoritesOnly: true).map(\.title), ["a"])
    }

    func test_filter_byCollectionUUID() {
        let target = UUID()
        let items = [
            candidate(title: "in", collectionUUIDs: [target]),
            candidate(title: "out", collectionUUIDs: [UUID()])
        ]
        XCTAssertEqual(filter(items, collectionUUID: target).map(\.title), ["in"])
    }

    func test_filter_combinesCriteria() {
        let target = UUID()
        let items = [
            candidate(title: "keep", isFavorite: true, collectionUUIDs: [target]),
            candidate(title: "keepNotFav", isFavorite: false, collectionUUIDs: [target]),
            candidate(title: "other", isFavorite: true, collectionUUIDs: [target])
        ]
        let result = filter(items, query: "keep", collectionUUID: target, favoritesOnly: true)
        XCTAssertEqual(result.map(\.title), ["keep"])
    }
}

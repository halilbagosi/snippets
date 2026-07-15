import XCTest
@testable import Snippets

@MainActor
final class CollectionMoveTreeTests: XCTestCase {
    func test_rows_whenCollectionsAreFlat_returnsThemAtDepthZeroInInputOrder() {
        let work = SnippetCollection(name: "Work")
        let personal = SnippetCollection(name: "Personal")

        let rows = MoveCollectionTree.rows(from: [work, personal])

        XCTAssertEqual(rows.map { $0.collection.name }, ["Work", "Personal"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func test_rows_whenCollectionHasChildPresentInList_nestsChildDirectlyAfterParent() {
        let work = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: work)
        let personal = SnippetCollection(name: "Personal")

        let rows = MoveCollectionTree.rows(from: [work, archived, personal])

        XCTAssertEqual(rows.map { $0.collection.name }, ["Work", "Archived", "Personal"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
    }

    func test_rows_whenChildsParentIsNotInList_treatsChildAsTopLevel() {
        let outsideParent = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: outsideParent)

        let rows = MoveCollectionTree.rows(from: [archived])

        XCTAssertEqual(rows.map { $0.collection.name }, ["Archived"])
        XCTAssertEqual(rows.map(\.depth), [0])
    }

    func test_searchRows_whenQueryMatchesSubstring_returnsFlatMatchesCaseInsensitively() {
        let work = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: work)
        let personal = SnippetCollection(name: "Personal")

        let rows = MoveCollectionTree.searchRows(from: [work, archived, personal], matching: "ARCH")

        XCTAssertEqual(rows.map { $0.collection.name }, ["Archived"])
        XCTAssertEqual(rows.map(\.depth), [0])
    }

    func test_searchRows_whenQueryIsBlank_returnsFullHierarchy() {
        let work = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: work)

        let rows = MoveCollectionTree.searchRows(from: [work, archived], matching: "   ")

        XCTAssertEqual(rows.map { $0.collection.name }, ["Work", "Archived"])
        XCTAssertEqual(rows.map(\.depth), [0, 1])
    }
}

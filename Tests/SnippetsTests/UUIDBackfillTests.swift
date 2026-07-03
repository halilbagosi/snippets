import XCTest
@testable import Snippets

@MainActor
final class UUIDBackfillTests: XCTestCase {
    func test_newSnippet_hasUUIDByDefault() {
        XCTAssertNotNil(Snippet(title: "x").uuid)
    }

    func test_newCollection_hasUUIDByDefault() {
        XCTAssertNotNil(SnippetCollection(name: "x").uuid)
    }

    func test_assign_fillsOnlyNilUUIDs_andReturnsCount() {
        let keep = Snippet(title: "keep")
        let keptUUID = keep.uuid
        let missing = Snippet(title: "missing")
        missing.uuid = nil
        let collection = SnippetCollection(name: "c")
        collection.uuid = nil

        let assigned = UUIDBackfill.assign(snippets: [keep, missing], collections: [collection])

        XCTAssertEqual(assigned, 2)
        XCTAssertEqual(keep.uuid, keptUUID)
        XCTAssertNotNil(missing.uuid)
        XCTAssertNotNil(collection.uuid)
    }

    func test_assign_whenNothingMissing_returnsZero() {
        let assigned = UUIDBackfill.assign(snippets: [Snippet(title: "a")], collections: [])
        XCTAssertEqual(assigned, 0)
    }
}

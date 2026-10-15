import XCTest
@testable import Snippets

@MainActor
final class SnippetGalleryViewModelTests: XCTestCase {
    func test_ordered_whenOldestToNewestIsEnabled_reversesInputOrder() {
        let newest = Snippet(title: "Newest")
        let oldest = Snippet(title: "Oldest")
        let sut = SnippetGalleryViewModel()
        sut.isOldestToNewest = true

        let ordered = sut.ordered([newest, oldest])

        XCTAssertEqual(ordered.map(\.title), ["Oldest", "Newest"])
    }

    func test_toggleSelectAll_whenItemsAreUnselected_selectsEveryVisibleSnippet() {
        let first = Snippet(title: "First")
        let second = Snippet(title: "Second")
        let sut = SnippetGalleryViewModel()

        sut.toggleSelectAll(for: [first, second])

        XCTAssertEqual(sut.selectedForAction, Set([first.persistentModelID, second.persistentModelID]))
    }

    func test_clearSelectionAndExitSelectMode_whenSelectionExists_clearsState() {
        let snippet = Snippet(title: "Selected")
        let sut = SnippetGalleryViewModel()
        sut.isSelectMode = true
        sut.toggleSelection(for: snippet)

        sut.clearSelectionAndExitSelectMode()

        XCTAssertFalse(sut.isSelectMode)
        XCTAssertTrue(sut.selectedForAction.isEmpty)
    }

    // MARK: - BulkDeleteConfirmation.decide

    func test_decide_collectionsWithAskBehavior_asksForCollectionBehaviorOnce() {
        let result = BulkDeleteConfirmation.decide(
            snippetCount: 3,
            collectionCount: 2,
            confirmSnippetDeletion: true,
            collectionDeletionBehavior: "ask"
        )

        XCTAssertEqual(result, .askCollectionBehavior)
    }

    func test_decide_collectionsWithAskBehavior_asksEvenWhenSnippetConfirmationIsOff() {
        let result = BulkDeleteConfirmation.decide(
            snippetCount: 0,
            collectionCount: 2,
            confirmSnippetDeletion: false,
            collectionDeletionBehavior: "ask"
        )

        XCTAssertEqual(result, .askCollectionBehavior)
    }

    func test_decide_snippetsOnlyWithConfirmationOn_confirmsOnce() {
        let result = BulkDeleteConfirmation.decide(
            snippetCount: 5,
            collectionCount: 0,
            confirmSnippetDeletion: true,
            collectionDeletionBehavior: "ask"
        )

        XCTAssertEqual(result, .confirmOnce(deleteCollectionContents: false))
    }

    func test_decide_snippetsAndCollectionsWithFixedBehavior_confirmsOnceUsingThatBehavior() {
        let result = BulkDeleteConfirmation.decide(
            snippetCount: 2,
            collectionCount: 1,
            confirmSnippetDeletion: true,
            collectionDeletionBehavior: "collectionAndContents"
        )

        XCTAssertEqual(result, .confirmOnce(deleteCollectionContents: true))
    }

    func test_decide_snippetsOnlyWithConfirmationOff_deletesImmediately() {
        let result = BulkDeleteConfirmation.decide(
            snippetCount: 4,
            collectionCount: 0,
            confirmSnippetDeletion: false,
            collectionDeletionBehavior: "ask"
        )

        XCTAssertEqual(result, .deleteImmediately(deleteCollectionContents: false))
    }

    func test_decide_collectionsOnlyWithFixedBehaviorAndConfirmationOff_deletesImmediately() {
        let result = BulkDeleteConfirmation.decide(
            snippetCount: 0,
            collectionCount: 3,
            confirmSnippetDeletion: false,
            collectionDeletionBehavior: "collectionOnly"
        )

        XCTAssertEqual(result, .deleteImmediately(deleteCollectionContents: false))
    }
}

@MainActor
final class SnippetCardPreviewTextTests: XCTestCase {
    func test_previewText_whenCodeIsShort_returnsItUnchanged() {
        let code = "let a = 1\nlet b = 2"

        XCTAssertEqual(SnippetCard.previewText(of: code), code)
    }

    func test_previewText_whenCodeHasManyLines_keepsElevenSoTheCardStillTruncates() {
        let code = (1...40).map { "line \($0)" }.joined(separator: "\n")

        let preview = SnippetCard.previewText(of: code)

        XCTAssertEqual(preview, (1...11).map { "line \($0)" }.joined(separator: "\n"))
    }

    func test_previewText_countsCRLFLineEndings() {
        let code = (1...20).map { "line \($0)" }.joined(separator: "\r\n")

        let preview = SnippetCard.previewText(of: code)

        XCTAssertEqual(preview.components(separatedBy: "\r\n").count, 11)
    }

    func test_previewText_whenCodeIsOneLongLine_capsTheCharacterCount() {
        let code = String(repeating: "x", count: 50_000)

        XCTAssertEqual(SnippetCard.previewText(of: code).count, 2_400)
    }
}

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
}

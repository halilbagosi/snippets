import XCTest
@testable import Snippets

final class QuickCopySelectionTests: XCTestCase {

    // MARK: Arrow keys

    func test_moveDown_advancesByOne() {
        XCTAssertEqual(QuickCopySelection.moved(from: 0, by: 1, count: 3), 1)
    }

    func test_moveUp_retreatsByOne() {
        XCTAssertEqual(QuickCopySelection.moved(from: 2, by: -1, count: 3), 1)
    }

    /// Clamped, not wrapping: holding ↓ should rest on the last row rather
    /// than cycling back to the top forever.
    func test_moveDown_clampsAtLastRow() {
        XCTAssertEqual(QuickCopySelection.moved(from: 2, by: 1, count: 3), 2)
    }

    func test_moveUp_clampsAtFirstRow() {
        XCTAssertEqual(QuickCopySelection.moved(from: 0, by: -1, count: 3), 0)
    }

    func test_move_withNoResults_staysAtZero() {
        XCTAssertEqual(QuickCopySelection.moved(from: 0, by: 1, count: 0), 0)
    }

    // MARK: Result changes

    func test_clamped_pullsIndexInsideShrunkList() {
        XCTAssertEqual(QuickCopySelection.clamped(7, count: 3), 2)
    }

    func test_clamped_leavesValidIndexAlone() {
        XCTAssertEqual(QuickCopySelection.clamped(1, count: 3), 1)
    }

    func test_clamped_withNoResults_isZero() {
        XCTAssertEqual(QuickCopySelection.clamped(5, count: 0), 0)
    }

    func test_clamped_negativeIndexIsZero() {
        XCTAssertEqual(QuickCopySelection.clamped(-2, count: 3), 0)
    }

    // MARK: Escape

    func test_escape_withTypedQuery_clearsIt() {
        XCTAssertEqual(QuickCopySelection.escape(query: "pars"), .clearQuery)
    }

    /// A query of only spaces is nothing the user needs cleared — escaping
    /// should get them out rather than making them press it twice.
    func test_escape_withWhitespaceOnlyQuery_dismisses() {
        XCTAssertEqual(QuickCopySelection.escape(query: "   "), .dismiss)
    }

    func test_escape_withEmptyQuery_dismisses() {
        XCTAssertEqual(QuickCopySelection.escape(query: ""), .dismiss)
    }
}

import XCTest
@testable import Snippets

/// Tests for SnippetLinker.stacks — grouping a gallery list into entry cards
/// with their connected snippets tucked behind.
final class SnippetStackerTests: XCTestCase {
    private struct Node: LinkableSnippet {
        let linkID: String
        var linkTitle: String { linkID }
        var linkLanguage: SupportedLanguage = .react
        var linkCode: String = ""
        var linkDependencies: [Node] = []
    }

    func test_dependencyInList_isHiddenBehindItsEntry() {
        let helper = Node(linkID: "GradientText")
        let entry = Node(linkID: "CursorGrid", linkDependencies: [helper])

        let stacks = SnippetLinker.stacks(in: [entry, helper])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["CursorGrid"])
        XCTAssertEqual(stacks[0].connected.map(\.linkID), ["GradientText"])
    }

    func test_transitiveDependencies_joinTheSameStack() {
        let leaf = Node(linkID: "Palette")
        let mid = Node(linkID: "GradientText", linkDependencies: [leaf])
        let entry = Node(linkID: "CursorGrid", linkDependencies: [mid])

        let stacks = SnippetLinker.stacks(in: [entry, mid, leaf])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["CursorGrid"])
        XCTAssertEqual(stacks[0].connected.map(\.linkID), ["GradientText", "Palette"])
    }

    func test_independentSnippets_stayFlatInOrder() {
        let a = Node(linkID: "A")
        let b = Node(linkID: "B")

        let stacks = SnippetLinker.stacks(in: [a, b])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["A", "B"])
        XCTAssertTrue(stacks.allSatisfy { $0.connected.isEmpty })
    }

    func test_dependencyNotInList_doesNotJoinStack() {
        let absent = Node(linkID: "Absent")
        let entry = Node(linkID: "CursorGrid", linkDependencies: [absent])

        let stacks = SnippetLinker.stacks(in: [entry])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["CursorGrid"])
        XCTAssertTrue(stacks[0].connected.isEmpty)
    }

    func test_sharedDependency_appearsInBothStacks() {
        let shared = Node(linkID: "Palette")
        let one = Node(linkID: "One", linkDependencies: [shared])
        let two = Node(linkID: "Two", linkDependencies: [shared])

        let stacks = SnippetLinker.stacks(in: [one, two, shared])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["One", "Two"])
        XCTAssertEqual(stacks[0].connected.map(\.linkID), ["Palette"])
        XCTAssertEqual(stacks[1].connected.map(\.linkID), ["Palette"])
    }

    func test_cycle_collapsesIntoOneStack_preferringEntryLikeLanguage() {
        // Mirrors the real CursorGrid data: Code/CSS/Usage all connected to
        // each other. The javascript member should front the stack; the css
        // and html members go behind it.
        var code = Node(linkID: "CursorGrid Code", linkLanguage: .javascript)
        var css = Node(linkID: "CursorGrid CSS", linkLanguage: .css)
        var usage = Node(linkID: "CursorGrid Usage", linkLanguage: .html)
        code.linkDependencies = [css, usage]
        css.linkDependencies = [code, usage]
        usage.linkDependencies = [css, code]

        let stacks = SnippetLinker.stacks(in: [css, code, usage])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["CursorGrid Code"])
        XCTAssertEqual(Set(stacks[0].connected.map(\.linkID)), ["CursorGrid CSS", "CursorGrid Usage"])
    }

    func test_cycle_sameLanguage_neverMakesSnippetsDisappear() {
        var a = Node(linkID: "A")
        var b = Node(linkID: "B")
        a.linkDependencies = [b]
        b.linkDependencies = [a]

        let stacks = SnippetLinker.stacks(in: [a, b])

        XCTAssertEqual(stacks.map(\.entry.linkID), ["A"])
        XCTAssertEqual(stacks[0].connected.map(\.linkID), ["B"])
    }
}

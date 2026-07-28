import XCTest
@testable import Snippets

private struct Node: LinkableSnippet {
    let linkID: Int
    let linkTitle: String
    let linkLanguage: SupportedLanguage
    let linkCode: String
    var linkDependencies: [Node] = []
}

final class SnippetLinkerTests: XCTestCase {
    func test_orderIsHelpersFirstEntryLast_transitively() {
        let util = Node(linkID: 1, linkTitle: "Util", linkLanguage: .javascript, linkCode: "u")
        let card = Node(linkID: 2, linkTitle: "Card", linkLanguage: .react, linkCode: "c", linkDependencies: [util])
        let entry = Node(linkID: 3, linkTitle: "App", linkLanguage: .react, linkCode: "a", linkDependencies: [card])
        let r = SnippetLinker.resolve(entry: entry)
        XCTAssertEqual(r.sources.map(\.code), ["u", "c", "a"])
        XCTAssertTrue(r.excluded.isEmpty)
    }

    func test_duplicateDependency_includedOnce() {
        let theme = Node(linkID: 1, linkTitle: "Theme", linkLanguage: .css, linkCode: "t")
        let a = Node(linkID: 2, linkTitle: "A", linkLanguage: .javascript, linkCode: "a", linkDependencies: [theme])
        let entry = Node(linkID: 3, linkTitle: "E", linkLanguage: .html, linkCode: "e", linkDependencies: [a, theme])
        XCTAssertEqual(SnippetLinker.resolve(entry: entry).sources.map(\.code), ["t", "a", "e"])
    }

    func test_cycle_isTolerated() {
        var a = Node(linkID: 1, linkTitle: "A", linkLanguage: .javascript, linkCode: "a")
        let b = Node(linkID: 2, linkTitle: "B", linkLanguage: .javascript, linkCode: "b", linkDependencies: [a])
        a.linkDependencies = [b]
        let r = SnippetLinker.resolve(entry: a)
        XCTAssertEqual(r.sources.map(\.code), ["b", "a"])
    }

    func test_incompatibleLanguages_areExcludedAndReported() {
        let py = Node(linkID: 1, linkTitle: "Script", linkLanguage: .python, linkCode: "p")
        let swiftDep = Node(linkID: 2, linkTitle: "Model", linkLanguage: .swift, linkCode: "s")
        let entry = Node(linkID: 3, linkTitle: "E", linkLanguage: .react, linkCode: "e", linkDependencies: [py, swiftDep])
        let r = SnippetLinker.resolve(entry: entry)
        XCTAssertEqual(r.sources.map(\.code), ["e"])
        XCTAssertEqual(Set(r.excluded), ["Script", "Model"])
    }

    func test_contributionMatrix() {
        for dep: SupportedLanguage in [.css, .javascript, .typescript, .react, .html] {
            XCTAssertTrue(SnippetLinker.canContribute(dep, toEntry: .react))
            XCTAssertTrue(SnippetLinker.canContribute(dep, toEntry: .html))
        }
        XCTAssertTrue(SnippetLinker.canContribute(.swift, toEntry: .swift))
        XCTAssertTrue(SnippetLinker.canContribute(.metal, toEntry: .metal))
        XCTAssertTrue(SnippetLinker.canContribute(.glsl, toEntry: .glsl))
        XCTAssertFalse(SnippetLinker.canContribute(.css, toEntry: .glsl))
        XCTAssertFalse(SnippetLinker.canContribute(.metal, toEntry: .swift))
        XCTAssertFalse(SnippetLinker.canContribute(.python, toEntry: .html))
        // CSS entries preview against connected markup and extra styles.
        XCTAssertTrue(SnippetLinker.canContribute(.html, toEntry: .css))
        XCTAssertTrue(SnippetLinker.canContribute(.css, toEntry: .css))
        XCTAssertFalse(SnippetLinker.canContribute(.javascript, toEntry: .css))
    }

    func test_strongerEntry_flagsReactConnectionOfCSSSnippet() {
        let component = Node(linkID: 1, linkTitle: "Button", linkLanguage: .react, linkCode: "c")
        let stronger = SnippetLinker.strongerEntry(thanEntryOf: .css, among: [component])
        XCTAssertEqual(stronger?.linkTitle, "Button")
    }

    func test_strongerEntry_prefersMostEntryLikeCandidate() {
        let markup = Node(linkID: 1, linkTitle: "Markup", linkLanguage: .html, linkCode: "h")
        let component = Node(linkID: 2, linkTitle: "Button", linkLanguage: .react, linkCode: "c")
        let stronger = SnippetLinker.strongerEntry(thanEntryOf: .css, among: [markup, component])
        XCTAssertEqual(stronger?.linkTitle, "Button")
    }

    func test_strongerEntry_nilWhenEditedSnippetIsAlreadyTheRoot() {
        let styles = Node(linkID: 1, linkTitle: "Theme", linkLanguage: .css, linkCode: "t")
        let util = Node(linkID: 2, linkTitle: "Util", linkLanguage: .javascript, linkCode: "u")
        XCTAssertNil(SnippetLinker.strongerEntry(thanEntryOf: .react, among: [styles, util]))
    }

    func test_strongerEntry_nilWhenReversedDirectionCannotPreview() {
        // A swift connection can't absorb a css entry, so no hint.
        let view = Node(linkID: 1, linkTitle: "Card", linkLanguage: .swift, linkCode: "s")
        XCTAssertNil(SnippetLinker.strongerEntry(thanEntryOf: .css, among: [view]))
    }

    func test_excludedDependencySubtree_isNotTraversed() {
        let css = Node(linkID: 1, linkTitle: "Theme", linkLanguage: .css, linkCode: "t")
        let py = Node(linkID: 2, linkTitle: "Py", linkLanguage: .python, linkCode: "p", linkDependencies: [css])
        let entry = Node(linkID: 3, linkTitle: "E", linkLanguage: .html, linkCode: "e", linkDependencies: [py])
        let r = SnippetLinker.resolve(entry: entry)
        XCTAssertEqual(r.sources.map(\.code), ["e"])
        XCTAssertEqual(r.excluded, ["Py"])
    }
}

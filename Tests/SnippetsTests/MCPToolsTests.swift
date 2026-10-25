#if !APP_STORE
import SwiftData
import XCTest
@testable import Snippets

@MainActor
final class MCPToolsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var allowEdits = false
    private var forgotten: [UUID] = []
    private var tools: SnippetMCPTools!

    override func setUp() async throws {
        // Keep the container alive for the whole test: inserting into a
        // context whose container was deallocated traps.
        container = try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        allowEdits = false
        forgotten = []
        tools = SnippetMCPTools(
            context: container.mainContext,
            editsAllowed: { [unowned self] in self.allowEdits },
            forgetTrust: { [unowned self] in self.forgotten.append($0) }
        )
    }

    override func tearDown() async throws {
        tools = nil
        container = nil
    }

    @discardableResult
    private func insert(_ title: String, language: String = "Swift", code: String = "code",
                        description: String = "", trashed: Bool = false,
                        updatedAt: Date = .now, collections: [SnippetCollection] = []) throws -> Snippet {
        let s = Snippet(title: title, snippetDescription: description, language: language, code: code,
                        updatedAt: updatedAt, deletedAt: trashed ? .now : nil, collections: collections)
        context.insert(s)
        try context.save()
        return s
    }

    private func id(_ s: Snippet) -> JSONValue { .string(s.uuid!.uuidString) }

    private func titles(_ result: JSONValue) -> [String] {
        (result["snippets"]?.arrayValue ?? []).compactMap { $0["title"]?.stringValue }
    }

    private func assertFails(_ name: String, _ args: [String: JSONValue], _ expected: MCPToolError,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try tools.call(name, arguments: args), file: file, line: line) {
            XCTAssertEqual($0 as? MCPToolError, expected, file: file, line: line)
        }
    }

    // MARK: Listing

    func test_tools_listsTheSixToolsWithObjectSchemas() {
        XCTAssertEqual(tools.tools.map(\.name),
                       ["find_snippets", "get_snippet", "use_snippet", "list_collections", "create_snippet", "update_snippet"])
        for tool in tools.tools { XCTAssertEqual(tool.inputSchema["type"], "object", tool.name) }
    }

    func test_writeSchemas_offerOnlyKnownLanguages() throws {
        for name in ["create_snippet", "update_snippet"] {
            let tool = try XCTUnwrap(tools.tools.first { $0.name == name })
            let accepted = try XCTUnwrap(tool.inputSchema["properties"]?["language"]?["enum"]?.arrayValue, name)
            XCTAssertTrue(accepted.contains("Swift"), name)
            XCTAssertTrue(accepted.contains("C/C++"), name)
            XCTAssertFalse(accepted.contains("Unknown"), name)
        }
        // Filtering stays free-form: an unknown name just matches nothing.
        let find = try XCTUnwrap(tools.tools.first { $0.name == "find_snippets" })
        XCTAssertNil(find.inputSchema["properties"]?["language"]?["enum"])
    }

    func test_readDescriptions_labelSnippetsAsData() throws {
        for name in ["get_snippet", "use_snippet"] {
            let tool = try XCTUnwrap(tools.tools.first { $0.name == name })
            XCTAssertTrue(tool.description.contains("not instructions"), name)
        }
    }

    func test_editsOffMessage_namesTheSettingsLabelAndWhatToDo() {
        XCTAssertEqual(SnippetMCPTools.editsOffMessage,
                       "Editing is off — enable \"Allow Agents to Edit\" in Snippets ▸ Settings ▸ Agents."
                       + " Nothing was saved: ask the user to turn it on, then call this tool again.")
    }

    /// Not every client passes the server instructions to its model, so the
    /// tool an agent reaches for when asked to save code must carry the rules.
    func test_createDescription_carriesTheSaveWorkflow() throws {
        let tool = try XCTUnwrap(tools.tools.first { $0.name == "create_snippet" })
        for phrase in ["verbatim", "update_snippet", "tell the user the title", "Settings ▸ Agents"] {
            XCTAssertTrue(tool.description.contains(phrase), phrase)
        }
        let code = try XCTUnwrap(tool.inputSchema["properties"]?["code"]?["description"]?.stringValue)
        XCTAssertTrue(code.contains("No Markdown fences"), code)
    }

    // MARK: list_collections

    func test_listCollections_namesLiveCollectionsWithCountsAndParents() throws {
        let web = SnippetCollection(name: "Web")
        let css = SnippetCollection(name: "CSS bits")
        css.parent = web
        let gone = SnippetCollection(name: "Gone")
        gone.deletedAt = .now
        for c in [web, css, gone] { context.insert(c) }
        try insert("A", collections: [web])
        try insert("B", collections: [web])
        try insert("Trashed", trashed: true, collections: [web])

        let result = try tools.call("list_collections", arguments: [:])
        let rows = try XCTUnwrap(result["collections"]?.arrayValue)
        XCTAssertEqual(rows.map { $0["name"] }, ["CSS bits", "Web"])
        XCTAssertEqual(rows[0]["parent"], "Web")
        XCTAssertEqual(rows[1]["parent"], .null)
        XCTAssertEqual(rows[1]["snippetCount"], 2)
        XCTAssertEqual(rows[1]["id"], .string(web.uuid!.uuidString))
    }

    // MARK: find_snippets

    func test_find_matchesQueryAndNeverReturnsCode() throws {
        try insert("Debounce", code: "SECRET")
        try insert("Throttle")
        let result = try tools.call("find_snippets", arguments: ["query": "debounce"])
        XCTAssertEqual(titles(result), ["Debounce"])
        XCTAssertNil(result["snippets"]?.arrayValue?.first?["code"])
        XCTAssertEqual(result["truncated"], false)
    }

    func test_find_filtersByLanguageCaseInsensitively() throws {
        try insert("A", language: "Swift")
        try insert("B", language: "JavaScript")
        XCTAssertEqual(titles(try tools.call("find_snippets", arguments: ["language": "javascript"])), ["B"])
    }

    func test_find_byCollectionNameOrID() throws {
        let utils = SnippetCollection(name: "Utils")
        context.insert(utils)
        try insert("In", collections: [utils])
        try insert("Out")
        XCTAssertEqual(titles(try tools.call("find_snippets", arguments: ["collection": "utils"])), ["In"])
        XCTAssertEqual(titles(try tools.call("find_snippets", arguments: ["collection": .string(utils.uuid!.uuidString)])), ["In"])
    }

    func test_find_unknownCollection_fails() {
        assertFails("find_snippets", ["collection": "Nope"], .failed("No collection named or with id Nope."))
    }

    func test_find_limitTruncates() throws {
        for i in 0..<3 { try insert("S\(i)") }
        let result = try tools.call("find_snippets", arguments: ["limit": 2])
        XCTAssertEqual(titles(result).count, 2)
        XCTAssertEqual(result["truncated"], true)
    }

    func test_find_hidesTrashed() throws {
        try insert("Gone", trashed: true)
        XCTAssertEqual(titles(try tools.call("find_snippets", arguments: [:])), [])
    }

    // MARK: get_snippet

    func test_get_returnsCodeAndDependencies() throws {
        let helper = try insert("Helper", language: "CSS", code: ".a{}")
        let entry = try insert("Page", language: "HTML", code: "<p>", description: "A page")
        entry.dependencies = [helper]
        try context.save()

        let result = try tools.call("get_snippet", arguments: ["id": id(entry)])
        XCTAssertEqual(result["code"], "<p>")
        XCTAssertEqual(result["description"], "A page")
        XCTAssertEqual(result["dependencies"], [["id": id(helper), "title": "Helper"]])
        XCTAssertNotNil(result["updatedAt"]?.stringValue)
    }

    func test_get_malformedID_isInvalidArguments() {
        assertFails("get_snippet", ["id": "xyz"], .invalidArguments("id must be a snippet id from find_snippets"))
    }

    func test_get_missingID_isInvalidArguments() {
        assertFails("get_snippet", [:], .invalidArguments("Missing required argument: id"))
    }

    func test_get_trashed_isNotFound() throws {
        let s = try insert("Gone", trashed: true)
        assertFails("get_snippet", ["id": id(s)], .failed("No snippet with id \(s.uuid!.uuidString)."))
    }

    // MARK: use_snippet

    func test_use_resolvesHelpersFirstAndReportsExcluded() throws {
        let css = try insert("Theme", language: "CSS", code: "css")
        let swift = try insert("Model", language: "Swift", code: "swift")
        let entry = try insert("Page", language: "HTML", code: "html")
        entry.dependencies = [css, swift]
        try context.save()

        let result = try tools.call("use_snippet", arguments: ["id": id(entry)])
        XCTAssertEqual(result["sources"], [["language": "CSS", "code": "css"], ["language": "HTML", "code": "html"]])
        XCTAssertEqual(result["excluded"], ["Model"])
    }

    func test_use_excludesTrashedDependencies() throws {
        let trashed = try insert("Old theme", language: "CSS", code: "trashed-css", trashed: true)
        let live = try insert("Theme", language: "CSS", code: "live-css")
        let entry = try insert("Page", language: "HTML", code: "html")
        entry.dependencies = [trashed, live]
        try context.save()

        let result = try tools.call("use_snippet", arguments: ["id": id(entry)])
        XCTAssertEqual(result["sources"], [["language": "CSS", "code": "live-css"], ["language": "HTML", "code": "html"]])
        XCTAssertEqual(result["excluded"], [])
    }

    func test_use_excludesTrashedTransitiveDependencies() throws {
        let trashed = try insert("Old reset", language: "CSS", code: "trashed-css", trashed: true)
        let live = try insert("Theme", language: "CSS", code: "live-css")
        live.dependencies = [trashed]
        let entry = try insert("Page", language: "HTML", code: "html")
        entry.dependencies = [live]
        try context.save()

        let result = try tools.call("use_snippet", arguments: ["id": id(entry)])
        XCTAssertEqual(result["sources"], [["language": "CSS", "code": "live-css"], ["language": "HTML", "code": "html"]])
        XCTAssertEqual(result["excluded"], [])
    }

    func test_use_countsAsACopyWithoutReorderingTheGallery() throws {
        let past = Date(timeIntervalSince1970: 1_000)
        let s = try insert("S", updatedAt: past)
        _ = try tools.call("use_snippet", arguments: ["id": id(s)])
        XCTAssertEqual(s.copyCount, 1)
        XCTAssertEqual(s.updatedAt, past)
    }

    // MARK: create_snippet

    func test_create_editsOff_failsAndInsertsNothing() throws {
        assertFails("create_snippet", ["title": "T", "code": "c"], .failed(SnippetMCPTools.editsOffMessage))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).count, 0)
    }

    func test_create_detectsLanguageAndSetsDescriptionAndCollection() throws {
        allowEdits = true
        let utils = SnippetCollection(name: "Utils")
        context.insert(utils)
        try context.save()

        let code = "import SwiftUI\n\nstruct ContentView: View {\n    var body: some View { Text(\"Hi\") }\n}"
        let result = try tools.call("create_snippet", arguments: [
            "title": "Hello", "code": .string(code), "description": "Greets", "collection": "utils",
        ])

        XCTAssertEqual(result["language"], "Swift")
        XCTAssertEqual(result["description"], "Greets")
        XCTAssertEqual(result["collections"], ["Utils"])
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(stored.title, "Hello")
        XCTAssertEqual(stored.snippetDescription, "Greets")
    }

    func test_create_canonicalizesAKnownLanguageName() throws {
        allowEdits = true
        let result = try tools.call("create_snippet", arguments: ["title": "T", "code": "x", "language": "javascript"])
        XCTAssertEqual(result["language"], "JavaScript")
    }

    func test_create_withDescription_persistsItInOneSave() throws {
        allowEdits = true
        var saves = 0
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: context, queue: nil
        ) { _ in saves += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try tools.call("create_snippet", arguments: ["title": "T", "code": "x", "description": "Greets"])

        XCTAssertEqual(saves, 1)
        let stored = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(stored.snippetDescription, "Greets")
    }

    func test_create_unknownLanguage_isInvalidArgumentsAndInsertsNothing() throws {
        allowEdits = true
        for name in ["Klingon", "Unknown"] {
            XCTAssertThrowsError(try tools.call("create_snippet", arguments: ["title": "T", "code": "c", "language": .string(name)])) {
                guard case .invalidArguments(let message)? = $0 as? MCPToolError else {
                    return XCTFail("expected invalidArguments, got \($0)")
                }
                XCTAssertTrue(message.hasPrefix("Unknown language: \(name). Use one of: HTML, Swift,"), message)
                XCTAssertFalse(message.hasSuffix("Unknown"), message)
            }
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).count, 0)
    }

    func test_create_unwrapsAMarkdownFenceAndTakesItsLanguage() throws {
        allowEdits = true
        let result = try tools.call("create_snippet", arguments: [
            "title": "T", "code": "```ts\nconst a = 1\n  indented()\n```\n",
        ])
        XCTAssertEqual(result["code"], "const a = 1\n  indented()")
        XCTAssertEqual(result["language"], "TypeScript")
    }

    func test_create_explicitLanguageBeatsTheFenceTag() throws {
        allowEdits = true
        let result = try tools.call("create_snippet", arguments: [
            "title": "T", "code": "```js\nx\n```", "language": "React",
        ])
        XCTAssertEqual(result["code"], "x")
        XCTAssertEqual(result["language"], "React")
    }

    func test_unfenced_leavesUnfencedOrMultiFenceCodeExactlyAsSent() {
        XCTAssertEqual(SnippetMCPTools.unfenced("  x\n").code, "  x\n")
        let two = "```\na\n```\ntext\n```\nb\n```"
        XCTAssertEqual(SnippetMCPTools.unfenced(two).code, two)
        XCTAssertNil(SnippetMCPTools.unfenced("```\na\n```").language)
        XCTAssertNil(SnippetMCPTools.unfenced("```klingon\na\n```").language)
        XCTAssertEqual(SnippetMCPTools.unfenced("```Swift title=x\na\n```").language, "Swift")
    }

    func test_create_emptyFence_isBlankCode() {
        allowEdits = true
        assertFails("create_snippet", ["title": "T", "code": "```swift\n  \n```"], .invalidArguments("code can't be blank"))
    }

    func test_create_missingCode_isInvalidArguments() {
        allowEdits = true
        assertFails("create_snippet", ["title": "T"], .invalidArguments("Missing required argument: code"))
    }

    func test_create_blankTitle_isInvalidArgumentsAndInsertsNothing() throws {
        allowEdits = true
        assertFails("create_snippet", ["title": "  \n ", "code": "c"], .invalidArguments("title can't be blank"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).count, 0)
    }

    func test_create_blankCode_isInvalidArgumentsAndInsertsNothing() throws {
        allowEdits = true
        assertFails("create_snippet", ["title": "T", "code": " \n\t"], .invalidArguments("code can't be blank"))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).count, 0)
    }

    func test_create_trimsTitleAndDescriptionButNotCode() throws {
        allowEdits = true
        _ = try tools.call("create_snippet", arguments: [
            "title": "  Hello \n", "code": "  x\n", "description": " Greets  ",
        ])
        let stored = try XCTUnwrap(try context.fetch(FetchDescriptor<Snippet>()).first)
        XCTAssertEqual(stored.title, "Hello")
        XCTAssertEqual(stored.snippetDescription, "Greets")
        XCTAssertEqual(stored.code, "  x\n")
    }

    func test_create_unknownCollection_failsAndInsertsNothing() throws {
        allowEdits = true
        assertFails("create_snippet", ["title": "T", "code": "c", "collection": "Nope"],
                    .failed("No collection named or with id Nope."))
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).count, 0)
    }

    // MARK: update_snippet

    func test_update_editsOff_failsAndChangesNothing() throws {
        let s = try insert("Old")
        assertFails("update_snippet", ["id": id(s), "title": "New"], .failed(SnippetMCPTools.editsOffMessage))
        XCTAssertEqual(s.title, "Old")
    }

    func test_update_changesOnlyGivenFieldsAndBumpsUpdatedAt() throws {
        allowEdits = true
        let past = Date(timeIntervalSince1970: 1_000)
        let s = try insert("Old", code: "keep", description: "keep too", updatedAt: past)

        let result = try tools.call("update_snippet", arguments: ["id": id(s), "title": "New"])

        XCTAssertEqual(result["title"], "New")
        XCTAssertEqual(s.title, "New")
        XCTAssertEqual(s.code, "keep")
        XCTAssertEqual(s.snippetDescription, "keep too")
        XCTAssertGreaterThan(s.updatedAt, past)
    }

    func test_update_blankTitle_isInvalidArgumentsAndChangesNothing() throws {
        allowEdits = true
        let s = try insert("Old", code: "keep")
        assertFails("update_snippet", ["id": id(s), "title": "   ", "code": "new"],
                    .invalidArguments("title can't be blank"))
        XCTAssertEqual(s.title, "Old")
        XCTAssertEqual(s.code, "keep")
    }

    func test_update_blankCode_isInvalidArgumentsAndChangesNothing() throws {
        allowEdits = true
        let s = try insert("Old", code: "keep")
        assertFails("update_snippet", ["id": id(s), "title": "New", "code": "\n "],
                    .invalidArguments("code can't be blank"))
        XCTAssertEqual(s.title, "Old")
        XCTAssertEqual(s.code, "keep")
    }

    func test_update_trimsTitleAndDescription() throws {
        allowEdits = true
        let s = try insert("Old")
        _ = try tools.call("update_snippet", arguments: ["id": id(s), "title": "  New \n", "description": " d "])
        XCTAssertEqual(s.title, "New")
        XCTAssertEqual(s.snippetDescription, "d")
    }

    func test_update_unknownLanguage_isInvalidArgumentsAndChangesNothing() throws {
        allowEdits = true
        let s = try insert("Old", language: "Swift", code: "keep")
        XCTAssertThrowsError(try tools.call("update_snippet", arguments: ["id": id(s), "title": "New", "language": "Klingon"])) {
            guard case .invalidArguments(let message)? = $0 as? MCPToolError else {
                return XCTFail("expected invalidArguments, got \($0)")
            }
            XCTAssertTrue(message.hasPrefix("Unknown language: Klingon. Use one of: "), message)
        }
        XCTAssertEqual(s.title, "Old")
        XCTAssertEqual(s.language, "Swift")
        XCTAssertEqual(forgotten, [])
    }

    func test_update_unwrapsAMarkdownFence() throws {
        allowEdits = true
        let s = try insert("S", language: "Swift", code: "old")
        _ = try tools.call("update_snippet", arguments: ["id": id(s), "code": "```swift\nnew\n```"])
        XCTAssertEqual(s.code, "new")
        XCTAssertEqual(s.language, "Swift")
    }

    func test_update_canonicalizesAKnownLanguageName() throws {
        allowEdits = true
        let s = try insert("S", language: "Swift")
        let result = try tools.call("update_snippet", arguments: ["id": id(s), "language": " javascript "])
        XCTAssertEqual(result["language"], "JavaScript")
        XCTAssertEqual(s.language, "JavaScript")
    }

    // MARK: Preview trust

    func test_update_codeChange_forgetsTrustForSnippetAndLiveDependents() throws {
        allowEdits = true
        let helper = try insert("Helper", code: "old")
        let page = try insert("Page")
        let other = try insert("Other")
        let trashed = try insert("Trashed", trashed: true)
        for dependent in [page, other, trashed] { dependent.dependencies = [helper] }
        try context.save()

        _ = try tools.call("update_snippet", arguments: ["id": id(helper), "code": "new"])

        XCTAssertEqual(forgotten.first, helper.uuid)
        XCTAssertEqual(Set(forgotten), [helper.uuid!, page.uuid!, other.uuid!])
        XCTAssertEqual(forgotten.count, 3)
    }

    func test_update_languageChange_forgetsTrust() throws {
        allowEdits = true
        let s = try insert("S", language: "Swift")
        _ = try tools.call("update_snippet", arguments: ["id": id(s), "language": "HTML"])
        XCTAssertEqual(forgotten, [s.uuid!])
    }

    func test_update_titleOrDescriptionOnly_forgetsNoTrust() throws {
        allowEdits = true
        let s = try insert("S", language: "Swift", code: "same")
        _ = try tools.call("update_snippet", arguments: ["id": id(s), "title": "New", "description": "d"])
        // Passing the current code and language back is not a change either.
        _ = try tools.call("update_snippet", arguments: ["id": id(s), "code": "same", "language": "swift"])
        XCTAssertEqual(forgotten, [])
    }

    func test_update_rejected_forgetsNoTrust() throws {
        let s = try insert("S", code: "keep")
        assertFails("update_snippet", ["id": id(s), "code": "new"], .failed(SnippetMCPTools.editsOffMessage))
        allowEdits = true
        assertFails("update_snippet", ["id": id(s), "title": " ", "code": "new"], .invalidArguments("title can't be blank"))
        XCTAssertEqual(forgotten, [])
    }

    // MARK: save_snippet prompt

    private func savePrompt(_ args: [String: String]) throws -> String {
        try XCTUnwrap(SnippetMCPTools.prompts.first { $0.name == "save_snippet" }).render(args)
    }

    func test_savePrompt_withoutArguments_savesTheCodeJustDiscussed() throws {
        let text = try savePrompt([:])
        XCTAssertTrue(text.hasPrefix("Save the code we were just looking at to my Snippets library."), text)
        XCTAssertTrue(text.contains("create_snippet"), text)
        XCTAssertTrue(text.contains("a short descriptive title"), text)
        XCTAssertFalse(text.contains("collection"), text)
        XCTAssertTrue(text.hasSuffix("instead of saving the code anywhere else."), text)
        XCTAssertTrue(text.contains("\n3. Tell me"), text)
    }

    func test_savePrompt_usesGivenCodeTitleAndCollection() throws {
        let text = try savePrompt(["code": " the debounce in utils.ts ", "title": "Debounce", "collection": "Web"])
        XCTAssertTrue(text.hasPrefix("Save the debounce in utils.ts to my Snippets library."), text)
        XCTAssertTrue(text.contains("the title \"Debounce\""), text)
        XCTAssertTrue(text.contains("\n3. File it in the collection \"Web\""), text)
        XCTAssertTrue(text.contains("\n4. Tell me"), text)
    }

    func test_update_nothingToChange_isInvalidArguments() throws {
        allowEdits = true
        let s = try insert("S")
        assertFails("update_snippet", ["id": id(s)],
                    .invalidArguments("Give at least one of title, code, language or description to change."))
    }
}
#endif

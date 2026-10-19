#if !APP_STORE
import SwiftData
import XCTest
@testable import Snippets

@MainActor
final class MCPToolsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private var allowEdits = false
    private var tools: SnippetMCPTools!

    override func setUp() async throws {
        // Keep the container alive for the whole test: inserting into a
        // context whose container was deallocated traps.
        container = try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        allowEdits = false
        tools = SnippetMCPTools(context: container.mainContext, editsAllowed: { [unowned self] in self.allowEdits })
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

    func test_tools_listsTheFiveToolsWithObjectSchemas() {
        XCTAssertEqual(tools.tools.map(\.name),
                       ["find_snippets", "get_snippet", "use_snippet", "create_snippet", "update_snippet"])
        for tool in tools.tools { XCTAssertEqual(tool.inputSchema["type"], "object", tool.name) }
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

    func test_use_countsAsACopyWithoutReorderingTheGallery() throws {
        let past = Date(timeIntervalSince1970: 1_000)
        let s = try insert("S", updatedAt: past)
        _ = try tools.call("use_snippet", arguments: ["id": id(s)])
        XCTAssertEqual(s.copyCount, 1)
        XCTAssertEqual(s.updatedAt, past)
    }
}
#endif

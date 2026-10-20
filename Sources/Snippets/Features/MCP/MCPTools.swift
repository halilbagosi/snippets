#if !APP_STORE
import Foundation
import SwiftData

/// The tools agents see. Each one adapts logic the App Intents already
/// use, so Shortcuts and agents can't drift apart. Trashed snippets and
/// collections are invisible here, and there is deliberately no delete.
@MainActor
final class SnippetMCPTools: MCPToolProvider {
    static let editsOffMessage = "Editing is off — enable \"Allow agents to edit\" in Snippets ▸ Settings ▸ Agents."
    static let defaultFindLimit = 25
    static let maxFindLimit = 100

    private let context: ModelContext
    private let editsAllowed: @MainActor () -> Bool

    init(context: ModelContext, editsAllowed: @escaping @MainActor () -> Bool) {
        self.context = context
        self.editsAllowed = editsAllowed
    }

    var tools: [MCPTool] { Self.definitions }

    func call(_ name: String, arguments: [String: JSONValue]) throws -> JSONValue {
        switch name {
        case "find_snippets": return try find(arguments)
        case "get_snippet": return try detail(snippet(arguments))
        case "use_snippet": return try use(arguments)
        case "create_snippet": return try create(arguments)
        case "update_snippet": return try update(arguments)
        default: throw MCPToolError.invalidArguments("Unknown tool: \(name)")
        }
    }

    // MARK: - Read tools

    private func find(_ a: [String: JSONValue]) throws -> JSONValue {
        let query = try string(a, "query")
        let language = try string(a, "language")
        let favoritesOnly = try bool(a, "favoritesOnly") ?? false
        let limit = try min(max(int(a, "limit") ?? Self.defaultFindLimit, 1), Self.maxFindLimit)
        let collectionID = try string(a, "collection").map { try collectionUUID($0) }

        let found = try FindSnippetsIntent.execute(
            searchText: query, collectionID: collectionID, favoritesOnly: favoritesOnly,
            in: context, language: language
        )
        return [
            "snippets": .array(found.prefix(limit).map { .object(summaryFields($0)) }),
            "truncated": .bool(found.count > limit),
        ]
    }

    private func use(_ a: [String: JSONValue]) throws -> JSONValue {
        let snippet = try snippet(a)
        // The one definition of copy bookkeeping: feeds the panel's Frequent scope.
        SnippetStore.recordCopy(snippet, in: context)
        let resolution = SnippetLinker.resolve(entry: LiveLinkable(snippet))
        return [
            "id": .string(snippet.uuid?.uuidString ?? ""),
            "title": .string(snippet.title),
            "language": .string(snippet.language),
            "sources": .array(resolution.sources.map {
                ["language": .string($0.language.rawValue), "code": .string($0.code)]
            }),
            "excluded": .array(resolution.excluded.map(JSONValue.string)),
        ]
    }

    /// Trashing is a soft delete that leaves `dependencies` intact, so the
    /// in-app linker still sees trashed helpers. Agents must not: this view
    /// of a snippet drops them, at every depth.
    private struct LiveLinkable: LinkableSnippet {
        let snippet: Snippet
        init(_ snippet: Snippet) { self.snippet = snippet }

        var linkID: PersistentIdentifier { snippet.persistentModelID }
        var linkTitle: String { snippet.title }
        var linkLanguage: SupportedLanguage { SupportedLanguage(rawValue: snippet.language) ?? .unknown }
        var linkCode: String { snippet.code }
        var linkDependencies: [LiveLinkable] {
            snippet.dependencies.filter { !$0.isDeleted }.map(LiveLinkable.init)
        }
    }

    // MARK: - Write tools (Task 3)

    private func create(_ a: [String: JSONValue]) throws -> JSONValue {
        guard editsAllowed() else { throw MCPToolError.failed(Self.editsOffMessage) }
        throw MCPToolError.failed("Not implemented yet.")
    }

    private func update(_ a: [String: JSONValue]) throws -> JSONValue {
        guard editsAllowed() else { throw MCPToolError.failed(Self.editsOffMessage) }
        throw MCPToolError.failed("Not implemented yet.")
    }

    // MARK: - Lookup

    private func snippet(_ a: [String: JSONValue]) throws -> Snippet {
        let raw = try requiredString(a, "id")
        guard let uuid = UUID(uuidString: raw) else {
            throw MCPToolError.invalidArguments("id must be a snippet id from find_snippets")
        }
        guard let snippet = try SnippetStore.snippet(uuid: uuid, in: context) else {
            throw MCPToolError.failed("No snippet with id \(raw).")
        }
        return snippet
    }

    /// A live collection by uuid or, failing that, by case-insensitive name.
    private func collectionUUID(_ ref: String) throws -> UUID {
        let live = try context.fetch(
            FetchDescriptor<SnippetCollection>(predicate: #Predicate { $0.deletedAt == nil })
        )
        let match = live.first { $0.uuid?.uuidString.caseInsensitiveCompare(ref) == .orderedSame }
            ?? live.first { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        guard let uuid = match?.uuid else {
            throw MCPToolError.failed("No collection named or with id \(ref).")
        }
        return uuid
    }

    // MARK: - Shapes

    private func summaryFields(_ s: Snippet) -> [String: JSONValue] {
        [
            "id": .string(s.uuid?.uuidString ?? ""),
            "title": .string(s.title),
            "language": .string(s.language),
            "description": .string(s.snippetDescription),
            "isFavorite": .bool(s.isFavorite),
            "collections": .array(s.collections.filter { !$0.isDeleted }.map { .string($0.name) }),
        ]
    }

    private func detail(_ s: Snippet) -> JSONValue {
        var fields = summaryFields(s)
        fields["code"] = .string(s.code)
        fields["createdAt"] = .string(s.createdAt.formatted(.iso8601))
        fields["updatedAt"] = .string(s.updatedAt.formatted(.iso8601))
        fields["dependencies"] = .array(s.dependencies.filter { !$0.isDeleted }.map {
            ["id": .string($0.uuid?.uuidString ?? ""), "title": .string($0.title)]
        })
        return .object(fields)
    }

    // MARK: - Arguments

    private func string(_ a: [String: JSONValue], _ key: String) throws -> String? {
        guard let value = a[key], value != .null else { return nil }
        guard let s = value.stringValue else { throw MCPToolError.invalidArguments("\(key) must be a string") }
        return s
    }

    private func requiredString(_ a: [String: JSONValue], _ key: String) throws -> String {
        guard let s = try string(a, key) else { throw MCPToolError.invalidArguments("Missing required argument: \(key)") }
        return s
    }

    private func bool(_ a: [String: JSONValue], _ key: String) throws -> Bool? {
        guard let value = a[key], value != .null else { return nil }
        guard let b = value.boolValue else { throw MCPToolError.invalidArguments("\(key) must be true or false") }
        return b
    }

    private func int(_ a: [String: JSONValue], _ key: String) throws -> Int? {
        guard let value = a[key], value != .null else { return nil }
        guard let i = value.intValue else { throw MCPToolError.invalidArguments("\(key) must be an integer") }
        return i
    }

    // MARK: - Schemas

    private static let idProperty: JSONValue = ["type": "string", "description": "A snippet id from find_snippets."]

    static let definitions: [MCPTool] = [
        MCPTool(
            name: "find_snippets",
            description: "Search the user's snippet library. Returns ids, titles, languages and descriptions — never code; call use_snippet or get_snippet for that.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Words to match against title, description and language."],
                    "language": ["type": "string", "description": "Only snippets in this language, e.g. Swift, JavaScript, HTML."],
                    "collection": ["type": "string", "description": "A collection name or id."],
                    "favoritesOnly": ["type": "boolean"],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 100, "description": "Default 25."],
                ],
                "additionalProperties": false,
            ]
        ),
        MCPTool(
            name: "get_snippet",
            description: "Everything about one snippet: its code, description, collections and the snippets it depends on.",
            inputSchema: ["type": "object", "properties": ["id": idProperty], "required": ["id"], "additionalProperties": false]
        ),
        MCPTool(
            name: "use_snippet",
            description: "Get a snippet's code ready to put into a project, with the snippets it depends on resolved in order (helpers first, the snippet itself last). Use when the user asks you to use one of their snippets.",
            inputSchema: ["type": "object", "properties": ["id": idProperty], "required": ["id"], "additionalProperties": false]
        ),
        MCPTool(
            name: "create_snippet",
            description: "Save new code to the user's snippet library. Requires the user to allow agent edits in Snippets' Settings.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "title": ["type": "string"],
                    "code": ["type": "string"],
                    "language": ["type": "string", "description": "Detected from the code when omitted."],
                    "description": ["type": "string"],
                    "collection": ["type": "string", "description": "A collection name or id to file it in."],
                ],
                "required": ["title", "code"],
                "additionalProperties": false,
            ]
        ),
        MCPTool(
            name: "update_snippet",
            description: "Change an existing snippet. Only the fields you pass change. Requires the user to allow agent edits in Snippets' Settings.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": idProperty,
                    "title": ["type": "string"],
                    "code": ["type": "string"],
                    "language": ["type": "string"],
                    "description": ["type": "string"],
                ],
                "required": ["id"],
                "additionalProperties": false,
            ]
        ),
    ]
}
#endif

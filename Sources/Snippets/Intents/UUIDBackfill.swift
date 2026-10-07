import Foundation

/// Assigns stable UUIDs to any models that predate the `uuid` property (existing
/// rows migrate to `nil`). Pure: mutates the passed models but never saves — the
/// caller owns persistence.
enum UUIDBackfill {
    @discardableResult
    static func assign(snippets: [Snippet], collections: [SnippetCollection]) -> Int {
        var assigned = 0
        for snippet in snippets where snippet.uuid == nil {
            snippet.uuid = UUID()
            assigned += 1
        }
        for collection in collections where collection.uuid == nil {
            collection.uuid = UUID()
            assigned += 1
        }
        return assigned
    }
}

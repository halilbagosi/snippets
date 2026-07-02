import SwiftData

/// A single row in the Move-to popup's collection list: the collection to
/// show plus how deeply it's nested under its parent (0 = top level).
struct CollectionMoveRow: Identifiable {
    let collection: SnippetCollection
    let depth: Int

    var id: PersistentIdentifier { collection.persistentModelID }
}

/// Builds the display order for the Move-to popup's collection list out of
/// an already-filtered flat list of valid move targets.
enum MoveCollectionTree {
    /// Orders `collections` depth-first: a collection whose parent is absent
    /// from `collections` (nil, or filtered out as an invalid target) is
    /// treated as top level; each collection is immediately followed by its
    /// children that are present in `collections`. Every input collection
    /// appears exactly once, in `collections`' relative order at each level.
    static func rows(from collections: [SnippetCollection]) -> [CollectionMoveRow] {
        let presentIDs = Set(collections.map(\.persistentModelID))
        var childrenByParentID: [PersistentIdentifier: [SnippetCollection]] = [:]
        var roots: [SnippetCollection] = []
        for collection in collections {
            if let parentID = collection.parent?.persistentModelID, presentIDs.contains(parentID) {
                childrenByParentID[parentID, default: []].append(collection)
            } else {
                roots.append(collection)
            }
        }

        var visited = Set<PersistentIdentifier>()
        var result: [CollectionMoveRow] = []
        result.reserveCapacity(collections.count)
        for root in roots {
            appendSubtree(root, depth: 0, childrenByParentID: childrenByParentID, visited: &visited, into: &result)
        }
        return result
    }

    /// Flat (depth 0), case-insensitive substring match against `query`.
    /// Falls back to the full hierarchy when `query` is blank.
    static func searchRows(from collections: [SnippetCollection], matching query: String) -> [CollectionMoveRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return rows(from: collections) }
        return collections
            .filter { $0.name.range(of: needle, options: .caseInsensitive) != nil }
            .map { CollectionMoveRow(collection: $0, depth: 0) }
    }

    private static func appendSubtree(
        _ collection: SnippetCollection,
        depth: Int,
        childrenByParentID: [PersistentIdentifier: [SnippetCollection]],
        visited: inout Set<PersistentIdentifier>,
        into result: inout [CollectionMoveRow]
    ) {
        let id = collection.persistentModelID
        guard !visited.contains(id) else { return }
        visited.insert(id)
        result.append(CollectionMoveRow(collection: collection, depth: depth))

        for child in childrenByParentID[id] ?? [] {
            appendSubtree(child, depth: depth + 1, childrenByParentID: childrenByParentID, visited: &visited, into: &result)
        }
    }
}

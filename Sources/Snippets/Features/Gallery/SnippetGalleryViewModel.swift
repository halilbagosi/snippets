import Foundation
import Observation
import SwiftData

/// What a bulk delete of the current selection needs from the user before
/// proceeding — at most one dialog, regardless of how many items are selected.
enum BulkDeleteConfirmation: Equatable {
    /// No dialog needed; delete the whole selection right away.
    case deleteImmediately(deleteCollectionContents: Bool)
    /// One confirmation covering the whole selection.
    case confirmOnce(deleteCollectionContents: Bool)
    /// Ask once whether selected collections' contents go to the trash too.
    case askCollectionBehavior

    static func decide(
        snippetCount: Int,
        collectionCount: Int,
        confirmSnippetDeletion: Bool,
        collectionDeletionBehavior: String
    ) -> BulkDeleteConfirmation {
        let deleteContents = collectionDeletionBehavior == "collectionAndContents"
        let behaviorIsFixed = deleteContents || collectionDeletionBehavior == "collectionOnly"

        if collectionCount > 0 && !behaviorIsFixed {
            return .askCollectionBehavior
        }
        if snippetCount > 0 && confirmSnippetDeletion {
            return .confirmOnce(deleteCollectionContents: deleteContents)
        }
        return .deleteImmediately(deleteCollectionContents: deleteContents)
    }
}

@MainActor
@Observable
final class SnippetGalleryViewModel {
    var isOldestToNewest = false
    var isShowingCollectionFilter = false
    var isSelectMode = false
    var selectedForAction = Set<PersistentIdentifier>()

    func hasAnyResults(
        snippets: [Snippet],
        searchResultCollections: [SnippetCollection],
        searchResultSnippets: [Snippet],
        searchQuery: String
    ) -> Bool {
        if searchQuery.isEmpty {
            return !snippets.isEmpty
        }

        return !searchResultCollections.isEmpty || !searchResultSnippets.isEmpty
    }

    func visibleSnippetIDs(
        snippets: [Snippet],
        searchResultSnippets: [Snippet],
        searchQuery: String
    ) -> Set<PersistentIdentifier> {
        Set((searchQuery.isEmpty ? snippets : searchResultSnippets).map(\.persistentModelID))
    }

    func displaySnippets(
        snippets: [Snippet],
        searchResultSnippets: [Snippet],
        searchQuery: String
    ) -> [Snippet] {
        if searchQuery.isEmpty {
            return snippets
        }

        return searchResultSnippets
    }

    func ordered(_ snippets: [Snippet]) -> [Snippet] {
        isOldestToNewest ? Array(snippets.reversed()) : snippets
    }

    func ordered(_ collections: [SnippetCollection]) -> [SnippetCollection] {
        isOldestToNewest ? Array(collections.reversed()) : collections
    }

    func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode {
            selectedForAction.removeAll()
        }
    }

    func toggleSelection(for snippet: Snippet) {
        let id = snippet.persistentModelID
        if selectedForAction.contains(id) {
            selectedForAction.remove(id)
        } else {
            selectedForAction.insert(id)
        }
    }

    func toggleSelection(for collection: SnippetCollection) {
        let id = collection.persistentModelID
        if selectedForAction.contains(id) {
            selectedForAction.remove(id)
        } else {
            selectedForAction.insert(id)
        }
    }

    func toggleSelectAll(for snippets: [Snippet]) {
        let ids = Set(snippets.map(\.persistentModelID))
        if selectedForAction == ids, !ids.isEmpty {
            selectedForAction.removeAll()
        } else {
            selectedForAction = ids
        }
    }

    func selectedSnippets(from snippets: [Snippet]) -> [Snippet] {
        snippets.filter { selectedForAction.contains($0.persistentModelID) }
    }

    func selectedCollections(from collections: [SnippetCollection]) -> [SnippetCollection] {
        collections.filter { selectedForAction.contains($0.persistentModelID) }
    }

    func clearSelectionAndExitSelectMode() {
        selectedForAction.removeAll()
        isSelectMode = false
    }
}

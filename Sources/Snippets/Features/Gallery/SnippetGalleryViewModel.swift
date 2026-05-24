import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SnippetGalleryViewModel {
    var isOldestToNewest = false
    var isShowingCollectionFilter = false
    var isSelectMode = false
    var selectedForAction = Set<PersistentIdentifier>()

    func hasAnyResults(
        snippets: [Snippet],
        collectionMatchSnippets: [Snippet],
        contentMatchSnippets: [Snippet]
    ) -> Bool {
        !snippets.isEmpty || !collectionMatchSnippets.isEmpty || !contentMatchSnippets.isEmpty
    }

    func visibleSnippetIDs(
        snippets: [Snippet],
        collectionMatchSnippets: [Snippet],
        contentMatchSnippets: [Snippet]
    ) -> Set<PersistentIdentifier> {
        Set((snippets + collectionMatchSnippets + contentMatchSnippets).map(\.persistentModelID))
    }

    func displaySnippets(
        snippets: [Snippet],
        collectionMatchSnippets: [Snippet],
        contentMatchSnippets: [Snippet],
        searchQuery: String
    ) -> [Snippet] {
        if searchQuery.isEmpty {
            return snippets
        }

        return collectionMatchSnippets + contentMatchSnippets
    }

    func ordered(_ snippets: [Snippet]) -> [Snippet] {
        isOldestToNewest ? Array(snippets.reversed()) : snippets
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

    func clearSelectionAndExitSelectMode() {
        selectedForAction.removeAll()
        isSelectMode = false
    }
}

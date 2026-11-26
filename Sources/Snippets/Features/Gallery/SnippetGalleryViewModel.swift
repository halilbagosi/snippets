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

    /// Splits `snippets` into one group per language, keeping each group's
    /// snippets in the order given.
    ///
    /// With a language filter the groups follow `preferredOrder` (the order the
    /// user tapped them in) and a selected language with nothing to show gets no
    /// group. Without one, every language present gets a group, alphabetically,
    /// so the strips don't reshuffle as the data changes.
    func languageGroups(
        _ snippets: [Snippet],
        preferredOrder: [SupportedLanguage]
    ) -> [(language: SupportedLanguage, snippets: [Snippet])] {
        let grouped = Dictionary(grouping: snippets) { SupportedLanguage(stored: $0.language) }
        let languages = preferredOrder.isEmpty
            ? grouped.keys.sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
            : preferredOrder
        return languages.compactMap { language in
            guard let members = grouped[language], !members.isEmpty else { return nil }
            return (language, members)
        }
    }

    func toggleSelectMode() {
        isSelectMode.toggle()
        if !isSelectMode {
            selectedForAction.removeAll()
            selectionAnchor = nil
        }
    }

    /// The item a Shift-click extends from: the last one toggled on its own.
    var selectionAnchor: PersistentIdentifier?

    func toggleSelection(for snippet: Snippet) {
        toggleSelection(id: snippet.persistentModelID)
    }

    func toggleSelection(for collection: SnippetCollection) {
        toggleSelection(id: collection.persistentModelID)
    }

    func toggleSelection(id: PersistentIdentifier) {
        if selectedForAction.contains(id) {
            selectedForAction.remove(id)
        } else {
            selectedForAction.insert(id)
        }
        selectionAnchor = id
    }

    /// One click on a card while selecting (or ⌘-clicking to start).
    /// Shift extends from the anchor to `id` through `order` — the cards as
    /// they appear on screen — the way Finder does; without an anchor in
    /// `order` it behaves like a plain toggle.
    func handleSelectionClick(id: PersistentIdentifier, extending: Bool, order: [PersistentIdentifier]) {
        isSelectMode = true
        guard extending, let anchor = selectionAnchor,
              let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
            toggleSelection(id: id)
            return
        }
        selectedForAction.formUnion(order[min(from, to)...max(from, to)])
    }

    func toggleSelectAll(for snippets: [Snippet]) {
        let ids = Set(snippets.map(\.persistentModelID))
        if selectedForAction == ids, !ids.isEmpty {
            selectedForAction.removeAll()
        } else {
            selectedForAction = ids
        }
    }

    /// Select-all that stays in select mode either way.
    func setAllSelected(_ selectAll: Bool, ids: [PersistentIdentifier]) {
        selectedForAction = selectAll ? Set(ids) : []
        selectionAnchor = nil
    }

    /// Drops selected items that are no longer on screen (a filter or search
    /// changed), so the counts on the action chips always match what is shown
    /// and an action never touches something the user can't see.
    func pruneSelection(toVisible visible: Set<PersistentIdentifier>) {
        let pruned = selectedForAction.intersection(visible)
        if pruned != selectedForAction { selectedForAction = pruned }
        if let anchor = selectionAnchor, !visible.contains(anchor) { selectionAnchor = nil }
    }

    func selectedSnippets(from snippets: [Snippet]) -> [Snippet] {
        snippets.filter { selectedForAction.contains($0.persistentModelID) }
    }

    func selectedCollections(from collections: [SnippetCollection]) -> [SnippetCollection] {
        collections.filter { selectedForAction.contains($0.persistentModelID) }
    }

    func clearSelectionAndExitSelectMode() {
        selectedForAction.removeAll()
        selectionAnchor = nil
        isSelectMode = false
    }
}

import SwiftData
import SwiftUI

struct TrashView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(filter: #Predicate<Snippet> { $0.deletedAt != nil }, sort: [SortDescriptor(\Snippet.deletedAt, order: .reverse)])
    private var trashedSnippets: [Snippet]

    @Query(filter: #Predicate<SnippetCollection> { $0.deletedAt != nil }, sort: [SortDescriptor(\SnippetCollection.deletedAt, order: .reverse)])
    private var trashedCollections: [SnippetCollection]

    @State private var searchText = ""
    @State private var selectedLanguages = Set<SupportedLanguage>()
    @State private var selectedSearchCollections = Set<PersistentIdentifier>()

    private var theme: Theme {
        Theme.current(colorScheme)
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case-insensitive substring match without allocating a lowercased copy
    /// of `haystack` (runs over every trashed snippet's full code per pass).
    private func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    private var matchingTrashedSnippets: [Snippet] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return [] }

        return trashedSnippets.filter { snippet in
            matches(snippet.title, needle) ||
            matches(snippet.snippetDescription, needle) ||
            matches(snippet.code, needle) ||
            matches(snippet.language, needle)
        }
    }

    var body: some View {
        ZStack {
            DotGridBackground(
                gradientPalette: [
                    Color(hex: "#FF453A") ?? .red,
                    Color(hex: "#D70015") ?? .red,
                    Color(hex: "#8E0011") ?? .red,
                    Color(hex: "#5C0008") ?? .red
                ],
                lightModeStrength: 0.55
            )
                .ignoresSafeArea()

            VStack(spacing: 0) {
                SnippetGalleryView(
                    snippets: trimmedSearchText.isEmpty ? trashedSnippets : [],
                    searchResultCollections: [],
                    searchResultSnippets: trimmedSearchText.isEmpty ? [] : matchingTrashedSnippets,
                    searchQuery: trimmedSearchText,
                    searchText: $searchText,
                    showFavoritesOnly: .constant(false),
                    selectedLanguages: $selectedLanguages,
                    selectedSearchCollections: $selectedSearchCollections,
                    showUncategorizedOnly: .constant(false),
                    availableLanguages: [],
                    availableCollections: [],
                    subcollections: trashedCollections,
                    onSelect: { _ in },
                    onNew: nil,
                    onDelete: nil,
                    onUndoDelete: nil,
                    isTrashMode: true,
                    onRestore: restore,
                    onPermanentDelete: { snippet, onConfirmed in
                        permanentlyDelete(snippet)
                        onConfirmed()
                    },
                    onRestoreCollection: restoreCollection,
                    onPermanentDeleteCollection: permanentlyDeleteCollection
                )
            }
        }
    }

    private func restore(_ snippet: Snippet) {
        snippet.deletedAt = nil
        snippet.updatedAt = .now
        try? modelContext.save()
    }

    private func permanentlyDelete(_ snippet: Snippet) {
        for mediaItem in snippet.mediaItems {
            appEnvironment.mediaManager.deleteFile(for: mediaItem)
        }

        modelContext.delete(snippet)
        try? modelContext.save()
    }

    private func restoreCollection(_ collection: SnippetCollection) {
        collection.deletedAt = nil
        collection.updatedAt = .now
        try? modelContext.save()
    }

    private func permanentlyDeleteCollection(_ collection: SnippetCollection) {
        modelContext.delete(collection)
        try? modelContext.save()
    }
}

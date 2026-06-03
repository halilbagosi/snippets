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

    private var matchingTrashedSnippets: [Snippet] {
        guard !trimmedSearchText.isEmpty else { return [] }
        let needle = trimmedSearchText.lowercased()

        return trashedSnippets.filter { snippet in
            snippet.title.lowercased().contains(needle) ||
            snippet.snippetDescription.lowercased().contains(needle) ||
            snippet.code.lowercased().contains(needle) ||
            snippet.language.lowercased().contains(needle)
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
                    selectedLanguages: $selectedLanguages,
                    selectedSearchCollections: $selectedSearchCollections,
                    availableLanguages: [],
                    availableCollections: [],
                    subcollections: trashedCollections,
                    onSelect: { _ in },
                    onNew: nil,
                    onDelete: nil,
                    onUndoDelete: nil,
                    isTrashMode: true,
                    onRestore: restore,
                    onPermanentDelete: permanentlyDelete,
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

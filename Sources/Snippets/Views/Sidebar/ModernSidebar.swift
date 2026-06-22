import SwiftUI
import SwiftData

struct ModernSidebar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @FocusState private var isListFocused: Bool

    enum Selection: Hashable {
        case all
        case language(String)
        case collection(PersistentIdentifier)
        case favoriteCollection(PersistentIdentifier)
        case snippet(PersistentIdentifier, ContentView.SidebarSelectionContext)
        case trash
    }

    let snippets: [Snippet]
    let uncategorizedSnippets: [Snippet]
    let collections: [SnippetCollection]
    let frequentlyUsedSnippets: [Snippet]
    let favoriteSnippets: [Snippet]
    let favoriteCollections: [SnippetCollection]
    let availableLanguages: [SupportedLanguage]
    let sidebarFilteredLanguages: [SupportedLanguage]
    let trashedItemCount: Int

    @Binding var sidebarSearch: String
    @Binding var selectedLanguages: Set<SupportedLanguage>
    @Binding var selectedSearchCollections: Set<PersistentIdentifier>
    @Binding var selectedSnippetID: PersistentIdentifier?
    @Binding var sidebarSelectionContext: ContentView.SidebarSelectionContext?
    @Binding var selectedCollectionID: PersistentIdentifier?
    @Binding var isLibrarySectionExpanded: Bool
    @Binding var isFavoritesSectionExpanded: Bool
    @Binding var isFrequentlyUsedSectionExpanded: Bool
    @Binding var isLanguagesSectionExpanded: Bool
    @Binding var isAllSnippetsExpanded: Bool
    @Binding var isCollectionsSectionExpanded: Bool
    @Binding var expandedCollections: Set<PersistentIdentifier>

    let onNew: () -> Void
    let onEditCollection: (SnippetCollection) -> Void
    let onDeleteCollection: (SnippetCollection) -> Void
    let onEditSnippet: (Snippet) -> Void
    let onDeleteSnippet: (Snippet) -> Void
    let onMoveSnippetToLibrary: (Snippet) -> Void
    let onMoveSnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onCopySnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onHandleDrop: ([String], SnippetCollection?) -> Bool

    private var topLevelCollections: [SnippetCollection] {
        collections.filter { !$0.isDeleted && ($0.parent == nil || $0.parent?.isDeleted == true) }
    }

    private var languageCounts: [String: Int] {
        snippets.reduce(into: [:]) { counts, snippet in
            counts[snippet.language, default: 0] += 1
        }
    }

    private var theme: Theme { Theme.current(colorScheme) }
    private var shouldUseActiveSelectionIconColor: Bool {
        controlActiveState != .inactive
    }

    private var selection: Binding<Selection?> {
        Binding(
            get: {
                if sidebarSelectionContext == .trash {
                    return .trash
                }
                if let id = selectedSnippetID, let context = sidebarSelectionContext {
                    return .snippet(id, context)
                }
                if let id = selectedCollectionID {
                    if sidebarSelectionContext == .favoriteCollection(id) {
                        return .favoriteCollection(id)
                    }
                    if sidebarSelectionContext == .collection(id) {
                        return .collection(id)
                    }
                }
                if let lang = selectedLanguages.first, selectedLanguages.count == 1 { return .language(lang.rawValue) }
                return .all
            },
            set: { newValue in
                switch newValue {
                case .all, .none:
                    selectedLanguages.removeAll()
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                case .language(let raw):
                    if let lang = SupportedLanguage(rawValue: raw) {
                        selectedLanguages = [lang]
                    }
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                case .collection(let id):
                    selectedCollectionID = id
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    sidebarSelectionContext = .collection(id)
                case .favoriteCollection(let id):
                    selectedCollectionID = id
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    sidebarSelectionContext = .favoriteCollection(id)
                case .snippet(let id, let context):
                    selectedSnippetID = id
                    sidebarSelectionContext = context
                    selectedSearchCollections.removeAll()
                    if case .collection(let collectionID) = context {
                        selectedCollectionID = collectionID
                    } else {
                        selectedCollectionID = nil
                    }
                case .trash:
                    selectedLanguages.removeAll()
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                    sidebarSelectionContext = .trash
                }
            }
        )
    }

    var body: some View {
        List(selection: selection) {
            snippetsSection

            if !topLevelCollections.isEmpty {
                collectionsSection
            }

            if !favoriteSnippets.isEmpty || !favoriteCollections.isEmpty {
                favoritesSection
            }

            if !frequentlyUsedSnippets.isEmpty {
                frequentlyUsedSection
            }

            if !availableLanguages.isEmpty {
                languagesSection
            }

            recentlyDeletedSection
        }
        .focused($isListFocused)
        .listStyle(.sidebar)
        .scrollContentBackground(.automatic)
        .safeAreaInset(edge: .top, spacing: 0) {
            Button(action: onNew) {
                Label("New Collection", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.text)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 10, style: .continuous),
                tint: theme.accent,
                interactive: true,
                borderOpacity: colorScheme == .dark ? 0.22 : 0.40,
                shadowRadius: 0,
                shadowY: 0
            )
            .overlay {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.accent.opacity(0.15))
                        .allowsHitTesting(false)
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .padding(DSToken.Spacing.sm)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var snippetsSection: some View {
        Section("SNIPPETS", isExpanded: $isLibrarySectionExpanded) {
            DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
                if sidebarFilteredLanguages.count == availableLanguages.count {
                    ForEach(snippets) { snippet in
                        snippetRow(snippet, context: .allSnippets)
                    }
                }
            } label: {
                countRow(title: "All Snippets", icon: "square.grid.2x2", iconColor: Color.accentColor, count: snippets.count, isSelected: selection.wrappedValue == .all)
            }
            .tag(Selection.all)
            .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, nil) }

            if !uncategorizedSnippets.isEmpty {
                DisclosureGroup(isExpanded: .constant(true)) {
                    if sidebarFilteredLanguages.count == availableLanguages.count {
                        ForEach(uncategorizedSnippets) { snippet in
                            snippetRow(snippet, context: .allSnippets)
                        }
                    }
                } label: {
                    countRow(title: "Uncategorized", icon: "tray", iconColor: theme.textMuted, count: uncategorizedSnippets.count, isSelected: false)
                }
            }
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        Section("COLLECTIONS", isExpanded: $isCollectionsSectionExpanded) {
            ForEach(topLevelCollections) { collection in
                CollectionTreeRow(
                    collection: collection,
                    collections: collections,
                    expandedCollections: $expandedCollections,
                    selectionValue: selection.wrappedValue,
                    selectedSnippetID: selectedSnippetID,
                    sidebarSelectionContext: sidebarSelectionContext,
                    shouldUseActiveSelectionIconColor: shouldUseActiveSelectionIconColor,
                    onEditCollection: onEditCollection,
                    onDeleteCollection: onDeleteCollection,
                    onEditSnippet: onEditSnippet,
                    onDeleteSnippet: onDeleteSnippet,
                    onMoveSnippetToLibrary: onMoveSnippetToLibrary,
                    onMoveSnippetToCollection: onMoveSnippetToCollection,
                    onCopySnippetToCollection: onCopySnippetToCollection,
                    onHandleDrop: onHandleDrop
                )
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        Section("FAVORITES", isExpanded: $isFavoritesSectionExpanded) {
            ForEach(favoriteCollections) { collection in
                let isSelected = selection.wrappedValue == .favoriteCollection(collection.persistentModelID)
                Label {
                    Text(collection.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: SnippetCollection.isValidSFSymbolName(collection.iconName) ? collection.iconName : SnippetCollection.defaultIconName)
                        .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : Color(red: 1.0, green: 0.80, blue: 0.20))
                }
                .tag(Selection.favoriteCollection(collection.persistentModelID))
                .contextMenu {
                    Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                }
            }
            ForEach(favoriteSnippets) { snippet in
                let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .favorites
                Label {
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(isSelected && shouldUseActiveSelectionIconColor ? Color.white : Color(red: 1.0, green: 0.80, blue: 0.20))
                }
                .tag(Selection.snippet(snippet.persistentModelID, .favorites))
                .contextMenu {
                    Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                }
            }
        }
    }

    @ViewBuilder
    private var frequentlyUsedSection: some View {
        Section("FREQUENTLY USED", isExpanded: $isFrequentlyUsedSectionExpanded) {
            ForEach(frequentlyUsedSnippets) { snippet in
                snippetRow(snippet, context: .frequentlyUsed)
                    .contextMenu {
                        Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                        moveToMenu(snippet)
                        Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                    }
            }
        }
    }

    @ViewBuilder
    private var languagesSection: some View {
        Section("LANGUAGES", isExpanded: $isLanguagesSectionExpanded) {
            let counts = languageCounts
            ForEach(sidebarFilteredLanguages) { language in
                let count = counts[language.rawValue, default: 0]
                let accent = Color(hex: language.accentHex) ?? Color.accentColor
                let isSelected = selection.wrappedValue == .language(language.rawValue)
                countRow(title: language.rawValue, icon: language.symbolName, iconColor: accent, count: count, isSelected: isSelected)
                    .tag(Selection.language(language.rawValue))
            }

            if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
                Text("No matches")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var recentlyDeletedSection: some View {
        Section {
            countRow(title: "Recently Deleted", icon: "trash", iconColor: .red, count: trashedItemCount, isSelected: selection.wrappedValue == .trash)
                .tag(Selection.trash)
        }
    }

    // MARK: - Reusable Row Builders

    @ViewBuilder
    private func snippetRow(_ snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent
        Label {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(activeAccent)
                .frame(width: 8, height: 8)
        }
        .tag(Selection.snippet(snippet.persistentModelID, context))
    }

    @ViewBuilder
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool = false) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(activeIconColor)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Context Menu Helpers

    @ViewBuilder
    private func moveToMenu(_ snippet: Snippet) -> some View {
        Menu("Move to") {
            Button { onMoveSnippetToLibrary(snippet) } label: {
                Label("All Snippets", systemImage: "square.grid.2x2")
            }
            ForEach(collections) { collection in
                Button { onMoveSnippetToCollection(snippet, collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
    }

    @ViewBuilder
    private func copyToMenu(_ snippet: Snippet) -> some View {
        Menu("Copy to") {
            ForEach(collections) { collection in
                Button { onCopySnippetToCollection(snippet, collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
    }

}

private struct CollectionTreeRow: View {
    let collection: SnippetCollection
    let collections: [SnippetCollection]
    @Binding var expandedCollections: Set<PersistentIdentifier>
    let selectionValue: ModernSidebar.Selection?
    let selectedSnippetID: PersistentIdentifier?
    let sidebarSelectionContext: ContentView.SidebarSelectionContext?
    let shouldUseActiveSelectionIconColor: Bool
    let onEditCollection: (SnippetCollection) -> Void
    let onDeleteCollection: (SnippetCollection) -> Void
    let onEditSnippet: (Snippet) -> Void
    let onDeleteSnippet: (Snippet) -> Void
    let onMoveSnippetToLibrary: (Snippet) -> Void
    let onMoveSnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onCopySnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onHandleDrop: ([String], SnippetCollection?) -> Bool

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: {
                if $0 {
                    expandedCollections.insert(collection.persistentModelID)
                } else {
                    expandedCollections.remove(collection.persistentModelID)
                }
            }
        )
    }

    private var activeSnippets: [Snippet] {
        collection.snippets.filter { $0.deletedAt == nil }
    }

    var body: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(collection.children) { child in
                CollectionTreeRow(
                    collection: child,
                    collections: collections,
                    expandedCollections: $expandedCollections,
                    selectionValue: selectionValue,
                    selectedSnippetID: selectedSnippetID,
                    sidebarSelectionContext: sidebarSelectionContext,
                    shouldUseActiveSelectionIconColor: shouldUseActiveSelectionIconColor,
                    onEditCollection: onEditCollection,
                    onDeleteCollection: onDeleteCollection,
                    onEditSnippet: onEditSnippet,
                    onDeleteSnippet: onDeleteSnippet,
                    onMoveSnippetToLibrary: onMoveSnippetToLibrary,
                    onMoveSnippetToCollection: onMoveSnippetToCollection,
                    onCopySnippetToCollection: onCopySnippetToCollection,
                    onHandleDrop: onHandleDrop
                )
            }

            ForEach(activeSnippets) { snippet in
                snippetRow(snippet)
            }
        } label: {
            countRow(
                title: collection.name,
                icon: collection.displayIconName,
                iconColor: collection.displayColor,
                count: activeSnippets.count,
                isSelected: selectionValue == .collection(collection.persistentModelID)
            )
            .contextMenu {
                Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
            }
        }
        .tag(ModernSidebar.Selection.collection(collection.persistentModelID))
        .dropDestination(for: String.self) { items, _ in onHandleDrop(items, collection) }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID)
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        let activeAccent = isSelected && shouldUseActiveSelectionIconColor ? Color.white : accent

        return Label {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(activeAccent)
                .frame(width: 8, height: 8)
        }
        .tag(ModernSidebar.Selection.snippet(snippet.persistentModelID, .collection(collection.persistentModelID)))
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
            Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
            Menu("Move to") {
                Button { onMoveSnippetToLibrary(snippet) } label: { Label("All Snippets", systemImage: "square.grid.2x2") }
                ForEach(collections) { target in
                    Button { onMoveSnippetToCollection(snippet, target) } label: { Label(target.name, systemImage: target.displayIconName) }
                }
            }
            Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
            Menu("Copy to") {
                ForEach(collections) { target in
                    Button { onCopySnippetToCollection(snippet, target) } label: { Label(target.name, systemImage: target.displayIconName) }
                }
            }
        }
    }

    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool) -> some View {
        let activeIconColor = isSelected && shouldUseActiveSelectionIconColor ? Color.white : iconColor

        return HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(activeIconColor)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

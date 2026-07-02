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
    private var isSelectionActive: Bool {
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
                Button {
                    selectedLanguages.removeAll()
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                } label: {
                    countRow(title: "All Snippets", icon: "square.grid.2x2", iconColor: theme.accent, count: snippets.count, isSelected: selection.wrappedValue == .all, includesChevron: true)
                }
                .buttonStyle(.plain)
                .sidebarMatchedSelection(
                    accent: theme.accent,
                    isSelected: selection.wrappedValue == .all,
                    colorScheme: colorScheme,
                    isActive: isSelectionActive
                )
            }
            // Match the disclosure chevron to the row's accent color.
            .tint(theme.accent)
            .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, nil) }


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
                    selectedSnippetID: $selectedSnippetID,
                    selectedCollectionID: $selectedCollectionID,
                    sidebarSelectionContext: $sidebarSelectionContext,
                    selectedLanguages: $selectedLanguages,
                    selectedSearchCollections: $selectedSearchCollections,
                    isSelectionActive: isSelectionActive,
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
                let accent = collection.displayColor
                Button {
                    selectedCollectionID = collection.persistentModelID
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    sidebarSelectionContext = .favoriteCollection(collection.persistentModelID)
                } label: {
                    Label {
                        Text(collection.name.lowercased())
                            .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: collection.displayIconName)
                            .foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .sidebarMatchedSelection(
                    accent: accent,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    isActive: isSelectionActive
                )
                .contextMenu {
                    Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                }
            }
            ForEach(favoriteSnippets) { snippet in
                let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .favorites
                let accent = Color(red: 1.0, green: 0.80, blue: 0.20)
                Button {
                    selectedSnippetID = snippet.persistentModelID
                    selectedCollectionID = nil
                    sidebarSelectionContext = .favorites
                    selectedLanguages.removeAll()
                    selectedSearchCollections.removeAll()
                } label: {
                    Label {
                        Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                            .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        Image(systemName: "star.fill")
                            .foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .sidebarMatchedSelection(
                    accent: accent,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    isActive: isSelectionActive
                )
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
                Button {
                    selectedLanguages = [language]
                    selectedSearchCollections.removeAll()
                    selectedSnippetID = nil
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                } label: {
                    countRow(title: language.rawValue, icon: language.symbolName, iconColor: accent, count: count, isSelected: isSelected)
                }
                .buttonStyle(.plain)
                .sidebarMatchedSelection(
                    accent: accent,
                    isSelected: isSelected,
                    colorScheme: colorScheme,
                    isActive: isSelectionActive
                )
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
            Button {
                selectedLanguages.removeAll()
                selectedSearchCollections.removeAll()
                selectedSnippetID = nil
                selectedCollectionID = nil
                sidebarSelectionContext = .trash
            } label: {
                countRow(title: "Recently Deleted", icon: "trash", iconColor: .red, count: trashedItemCount, isSelected: selection.wrappedValue == .trash)
            }
            .buttonStyle(.plain)
            .sidebarMatchedSelection(
                accent: .red,
                isSelected: selection.wrappedValue == .trash,
                colorScheme: colorScheme,
                isActive: isSelectionActive
            )
        }
    }

    // MARK: - Reusable Row Builders

    @ViewBuilder
    private func snippetRow(_ snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        Button {
            selectedSnippetID = snippet.persistentModelID
            selectedCollectionID = nil
            sidebarSelectionContext = context
            selectedLanguages.removeAll()
            selectedSearchCollections.removeAll()
        } label: {
            Label {
                Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                    .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sidebarMatchedSelection(
            accent: accent,
            isSelected: isSelected,
            colorScheme: colorScheme,
            isActive: isSelectionActive
        )
    }

    @ViewBuilder
    private func countRow(title: String, icon: String, iconColor: Color, count: Int, isSelected: Bool = false, includesChevron: Bool = false) -> some View {
        HStack {
            Label {
                Text(title.lowercased())
                    .font(Mono.font(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
            } icon: {
                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.text.opacity(0.74) : theme.textFaint)
            }
        }
        // Pull the row content toward the disclosure chevron so the chevron
        // sits close to the icon instead of leaving a gap.
        .padding(.leading, includesChevron ? -12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Context Menu Helpers

    @ViewBuilder
    private func moveToMenu(_ snippet: Snippet) -> some View {
        Menu("Move to") {
            if !snippet.collections.isEmpty {
                Button { onMoveSnippetToLibrary(snippet) } label: {
                    Label("All Snippets", systemImage: "square.grid.2x2")
                }
            }
            let targetCollections = collections.filter { target in
                !snippet.collections.contains(where: { $0.persistentModelID == target.persistentModelID })
            }
            ForEach(targetCollections) { collection in
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
    @Environment(\.colorScheme) var colorScheme
    let collection: SnippetCollection
    let collections: [SnippetCollection]
    @Binding var expandedCollections: Set<PersistentIdentifier>
    let selectionValue: ModernSidebar.Selection?
    @Binding var selectedSnippetID: PersistentIdentifier?
    @Binding var selectedCollectionID: PersistentIdentifier?
    @Binding var sidebarSelectionContext: ContentView.SidebarSelectionContext?
    @Binding var selectedLanguages: Set<SupportedLanguage>
    @Binding var selectedSearchCollections: Set<PersistentIdentifier>
    let isSelectionActive: Bool
    let onEditCollection: (SnippetCollection) -> Void
    let onDeleteCollection: (SnippetCollection) -> Void
    let onEditSnippet: (Snippet) -> Void
    let onDeleteSnippet: (Snippet) -> Void
    let onMoveSnippetToLibrary: (Snippet) -> Void
    let onMoveSnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onCopySnippetToCollection: (Snippet, SnippetCollection) -> Void
    let onHandleDrop: ([String], SnippetCollection?) -> Bool

    private var theme: Theme { Theme.current(colorScheme) }

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
                    selectedSnippetID: $selectedSnippetID,
                    selectedCollectionID: $selectedCollectionID,
                    sidebarSelectionContext: $sidebarSelectionContext,
                    selectedLanguages: $selectedLanguages,
                    selectedSearchCollections: $selectedSearchCollections,
                    isSelectionActive: isSelectionActive,
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
            Button {
                selectedCollectionID = collection.persistentModelID
                selectedSearchCollections.removeAll()
                selectedSnippetID = nil
                sidebarSelectionContext = .collection(collection.persistentModelID)
                selectedLanguages.removeAll()
            } label: {
                countRow(
                    title: collection.name,
                    icon: collection.displayIconName,
                    iconColor: collection.displayColor,
                    count: activeSnippets.count,
                    isSelected: selectionValue == .collection(collection.persistentModelID)
                )
            }
            .buttonStyle(.plain)
            .sidebarMatchedSelection(
                accent: collection.displayColor,
                isSelected: selectionValue == .collection(collection.persistentModelID),
                colorScheme: colorScheme,
                isActive: isSelectionActive
            )
            .contextMenu {
                Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
            }
        }
        // Match the disclosure chevron to the collection's color.
        .tint(collection.displayColor)
        .dropDestination(for: String.self) { items, _ in onHandleDrop(items, collection) }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        let isSelected = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID)
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor

        return Button {
            selectedSnippetID = snippet.persistentModelID
            selectedCollectionID = nil
            sidebarSelectionContext = .collection(collection.persistentModelID)
            selectedLanguages.removeAll()
            selectedSearchCollections.removeAll()
        } label: {
            Label {
                Text(snippet.title.isEmpty ? "untitled" : snippet.title.lowercased())
                    .font(Mono.font(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .sidebarMatchedSelection(
            accent: accent,
            isSelected: isSelected,
            colorScheme: colorScheme,
            isActive: isSelectionActive
        )
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
            Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
            Menu("Move to") {
                if !snippet.collections.isEmpty {
                    Button { onMoveSnippetToLibrary(snippet) } label: { Label("All Snippets", systemImage: "square.grid.2x2") }
                }
                let targetCollections = collections.filter { target in
                    !snippet.collections.contains(where: { $0.persistentModelID == target.persistentModelID })
                }
                ForEach(targetCollections) { target in
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
        return HStack {
            Label {
                Text(title.lowercased())
                    .font(Mono.font(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
            } icon: {
                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.text.opacity(0.74) : theme.textFaint)
            }
        }
        // Pull the row content toward the disclosure chevron so the chevron
        // sits close to the icon instead of leaving a gap.
        .padding(.leading, -12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Sidebar selection frame, tinted with the row's accent colour.
///
/// Drawn via `listRowBackground`, so the List hands it the entire row
/// rectangle — disclosure chevron included — and the frame keeps even,
/// fixed margins to both sidebar edges instead of being derived from the
/// label's position.
private struct SidebarMatchedSelectionModifier: ViewModifier {
    let accent: Color
    let isSelected: Bool
    let colorScheme: ColorScheme
    let isActive: Bool

    /// Distance between the selection frame and the row's edges.
    private let horizontalInset: CGFloat = 4
    private let verticalInset: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .listRowBackground(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(accent.opacity(isSelected ? fillOpacity : 0))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(accent.opacity(isSelected ? strokeOpacity : 0), lineWidth: 1)
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, verticalInset)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isActive)
    }

    private var fillOpacity: Double {
        isActive
            ? (colorScheme == .dark ? 0.32 : 0.20)
            : (colorScheme == .dark ? 0.18 : 0.12)
    }

    private var strokeOpacity: Double {
        isActive ? 0.42 : 0.24
    }
}

private extension View {
    func sidebarMatchedSelection(
        accent: Color,
        isSelected: Bool,
        colorScheme: ColorScheme,
        isActive: Bool
    ) -> some View {
        modifier(
            SidebarMatchedSelectionModifier(
                accent: accent,
                isSelected: isSelected,
                colorScheme: colorScheme,
                isActive: isActive
            )
        )
    }
}

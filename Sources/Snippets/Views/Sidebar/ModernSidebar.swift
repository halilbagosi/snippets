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
        case snippet(PersistentIdentifier, ContentView.SidebarSelectionContext)
        case trash
    }

    let snippets: [Snippet]
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

    private var theme: Theme { Theme.current(colorScheme) }

    private var selection: Binding<Selection?> {
        Binding(
            get: {
                if sidebarSelectionContext == .trash {
                    return .trash
                }
                if let id = selectedSnippetID, let context = sidebarSelectionContext {
                    return .snippet(id, context)
                }
                if let id = selectedCollectionID, sidebarSelectionContext == .collection(id) { return .collection(id) }
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
            .padding(12)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var snippetsSection: some View {
        Section("Snippets", isExpanded: $isLibrarySectionExpanded) {
            DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
                ForEach(snippets) { snippet in
                    snippetRow(snippet, context: .allSnippets)
                        .draggable(String(snippet.persistentModelID.hashValue))
                        .contextMenu {
                            Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                            Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                            moveToMenu(snippet)
                            copyToMenu(snippet)
                        }
                }
            } label: {
                countRow(title: "All Snippets", icon: "square.grid.2x2", iconColor: Color.accentColor, count: snippets.count)
            }
            .tag(Selection.all)
            .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, nil) }

            ForEach(topLevelCollections) { collection in
                modernCollectionTree(for: collection)
            }
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        Section("Favorites", isExpanded: $isFavoritesSectionExpanded) {
            ForEach(favoriteCollections) { collection in
                Label {
                    Text(collection.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: SnippetCollection.isValidSFSymbolName(collection.iconName) ? collection.iconName : SnippetCollection.defaultIconName)
                        .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.20))
                }
                .tag(Selection.collection(collection.persistentModelID))
                .contextMenu {
                    Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                }
            }
            ForEach(favoriteSnippets) { snippet in
                Label {
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Image(systemName: "star.fill")
                        .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.20))
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
        Section("Frequently Used", isExpanded: $isFrequentlyUsedSectionExpanded) {
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
        Section("Languages", isExpanded: $isLanguagesSectionExpanded) {
            ForEach(sidebarFilteredLanguages) { language in
                let count = snippets.filter { $0.language == language.rawValue }.count
                let accent = Color(hex: language.accentHex) ?? Color.accentColor
                countRow(title: language.rawValue, icon: language.symbolName, iconColor: accent, count: count)
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
            countRow(title: "Recently Deleted", icon: "trash", iconColor: .red, count: trashedItemCount)
                .tag(Selection.trash)
        }
    }

    // MARK: - Reusable Row Builders

    /// A standard snippet row with a colored language dot icon.
    @ViewBuilder
    private func snippetRow(_ snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? Color.accentColor
        Label {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .lineLimit(1)
                .truncationMode(.tail)
        } icon: {
            Circle()
                .fill(accent)
                .frame(width: 8, height: 8)
        }
        .tag(Selection.snippet(snippet.persistentModelID, context))
    }

    /// A row with a trailing count badge.
    @ViewBuilder
    private func countRow(title: String, icon: String, iconColor: Color, count: Int) -> some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .font(.system(size: 12))
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
        }
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

    // MARK: - Collection Tree

    @ViewBuilder
    private func modernCollectionTree(for collection: SnippetCollection) -> some View {
        let isExpanded = Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
        )
        let activeCount = collection.snippets.filter { $0.deletedAt == nil }.count
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(collection.children) { child in
                AnyView(modernCollectionTree(for: child))
            }
            ForEach(collection.snippets.filter { $0.deletedAt == nil }) { snippet in
                let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                let accent = Color(hex: language.accentHex) ?? Color.accentColor
                Label {
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Circle()
                        .fill(accent)
                        .frame(width: 8, height: 8)
                }
                .tag(Selection.snippet(snippet.persistentModelID, .collection(collection.persistentModelID)))
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
        } label: {
            countRow(title: collection.name, icon: collection.displayIconName, iconColor: collection.displayColor, count: activeCount)
                .contextMenu {
                    Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
                }
        }
        .tag(Selection.collection(collection.persistentModelID))
        .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, collection) }
    }
}

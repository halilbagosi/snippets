import SwiftUI
import SwiftData

@available(macOS 26.0, *)
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
            Section("Snippets", isExpanded: $isLibrarySectionExpanded) {
                DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
                    ForEach(snippets) { snippet in
                        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        let isSnippetSelected = selection.wrappedValue == .snippet(snippet.persistentModelID, .allSnippets)
                        let isActiveSelection = isSnippetSelected && isListFocused && controlActiveState != .inactive
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(isActiveSelection ? .white : accent)
                                .frame(width: 8, height: 8)
                        }
                        .foregroundStyle(isActiveSelection ? .white : .primary)
                        .tag(Selection.snippet(snippet.persistentModelID, .allSnippets))
                        .draggable(String(snippet.persistentModelID.hashValue))
                        .contextMenu {
                            Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                            Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                            Menu("Move to") {
                                Button { onMoveSnippetToLibrary(snippet) } label: { Label("All Snippets", systemImage: "square.grid.2x2") }
                                ForEach(collections) { collection in
                                    Button { onMoveSnippetToCollection(snippet, collection) } label: { Label(collection.name, systemImage: collection.displayIconName) }
                                }
                            }
                            Menu("Copy to") {
                                ForEach(collections) { collection in
                                    Button { onCopySnippetToCollection(snippet, collection) } label: { Label(collection.name, systemImage: collection.displayIconName) }
                                }
                            }
                        }
                    }
                } label: {
                    let isAllSelected = selection.wrappedValue == .all
                    let isActiveSelection = isAllSelected && isListFocused && controlActiveState != .inactive
                    Label {
                        HStack {
                            Text("All Snippets")
                            Spacer()
                            Text("\(snippets.count)")
                                .foregroundStyle(isActiveSelection ? .white.opacity(0.7) : .secondary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(isActiveSelection ? .white : .accentColor)
                    }
                    .foregroundStyle(isActiveSelection ? .white : .primary)
                }
                .tag(Selection.all)
                .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, nil) }

                ForEach(topLevelCollections) { collection in
                    modernCollectionTree(for: collection)
                }
            }

            if !frequentlyUsedSnippets.isEmpty {
                Section("Frequently Used", isExpanded: $isFrequentlyUsedSectionExpanded) {
                    ForEach(frequentlyUsedSnippets) { snippet in
                        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        let isFreqSelected = selection.wrappedValue == .snippet(snippet.persistentModelID, .frequentlyUsed)
                        let isActiveSelection = isFreqSelected && isListFocused && controlActiveState != .inactive
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(isActiveSelection ? .white : accent)
                                .frame(width: 8, height: 8)
                        }
                        .foregroundStyle(isActiveSelection ? .white : .primary)
                        .tag(Selection.snippet(snippet.persistentModelID, .frequentlyUsed))
                        .contextMenu {
                            Button { onEditSnippet(snippet) } label: {
                                Label("Edit snippet", systemImage: "pencil")
                            }
                            Button(role: .destructive) { onDeleteSnippet(snippet) } label: {
                                Label("Delete snippet", systemImage: "trash")
                            }
                            Menu("Move to") {
                                Button { onMoveSnippetToLibrary(snippet) } label: {
                                    Label("Snippets", systemImage: "square.grid.2x2")
                                }
                                ForEach(collections) { collection in
                                    Button { onMoveSnippetToCollection(snippet, collection) } label: {
                                        Label(collection.name, systemImage: collection.displayIconName)
                                    }
                                }
                            }
                        }
                    }
                }
            }


            if !availableLanguages.isEmpty {
                Section("Languages", isExpanded: $isLanguagesSectionExpanded) {
                    ForEach(sidebarFilteredLanguages) { language in
                        let count = snippets.filter { $0.language == language.rawValue }.count
                        let accent = Color(hex: language.accentHex) ?? .accentColor
                        let isLangSelected = selection.wrappedValue == .language(language.rawValue)
                        let isActiveSelection = isLangSelected && isListFocused && controlActiveState != .inactive
                        Label {
                            HStack {
                                Text(language.rawValue)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(isActiveSelection ? .white.opacity(0.7) : .secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: language.symbolName)
                                .foregroundStyle(isActiveSelection ? .white : accent)
                        }
                        .foregroundStyle(isActiveSelection ? .white : .primary)
                        .tag(Selection.language(language.rawValue))
                    }

                    if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    }
                }
            }

            Section {
                let isTrashSelected = selection.wrappedValue == .trash
                let isActiveSelection = isTrashSelected && isListFocused && controlActiveState != .inactive
                Label {
                    HStack {
                        Text("Recently Deleted")
                        Spacer()
                        Text("\(trashedItemCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(isActiveSelection ? .white : .red)
                }
                .tag(Selection.trash)
                .foregroundStyle(isActiveSelection ? .white : .red)
            }
        }
        .focused($isListFocused)
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
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
                shadowRadius: 6,
                shadowY: 3
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

    @ViewBuilder
    private func modernCollectionTree(for collection: SnippetCollection) -> some View {
        let isExpanded = Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
        )
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(collection.children) { child in
                AnyView(modernCollectionTree(for: child))
            }
            ForEach(collection.snippets.filter { $0.deletedAt == nil }) { snippet in
                let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
                let accent = Color(hex: language.accentHex) ?? .accentColor
                let isCollSnippetSelected = selection.wrappedValue == .snippet(snippet.persistentModelID, .collection(collection.persistentModelID))
                let isActiveSelection = isCollSnippetSelected && isListFocused && controlActiveState != .inactive
                Label {
                    Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } icon: {
                    Circle()
                        .fill(isActiveSelection ? .white : accent)
                        .frame(width: 8, height: 8)
                }
                .foregroundStyle(isActiveSelection ? .white : .primary)
                .tag(Selection.snippet(snippet.persistentModelID, .collection(collection.persistentModelID)))
                .draggable(String(snippet.persistentModelID.hashValue))
                .contextMenu {
                    Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                    Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                    Menu("Move to") {
                        Button { onMoveSnippetToLibrary(snippet) } label: { Label("All Snippets", systemImage: "square.grid.2x2") }
                        ForEach(collections) { target in
                            Button { onMoveSnippetToCollection(snippet, target) } label: { Label(target.name, systemImage: target.displayIconName) }
                        }
                    }
                    Menu("Copy to") {
                        ForEach(collections) { target in
                            Button { onCopySnippetToCollection(snippet, target) } label: { Label(target.name, systemImage: target.displayIconName) }
                        }
                    }
                }
            }
        } label: {
            let isCollSelected = selection.wrappedValue == .collection(collection.persistentModelID)
            let isActiveSelection = isCollSelected && isListFocused && controlActiveState != .inactive
            Label {
                HStack {
                    Text(collection.name)
                    Spacer()
                    Text("\(collection.snippets.filter { $0.deletedAt == nil }.count)")
                        .foregroundStyle(isActiveSelection ? .white.opacity(0.7) : .secondary)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: collection.displayIconName)
                    .foregroundStyle(isActiveSelection ? .white : collection.displayColor)
            }
            .foregroundStyle(isActiveSelection ? .white : .primary)
            .contextMenu {
                Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
                Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
            }
        }
        .tag(Selection.collection(collection.persistentModelID))
        .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, collection) }
    }
}

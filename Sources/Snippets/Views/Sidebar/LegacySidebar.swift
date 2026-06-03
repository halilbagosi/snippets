import SwiftUI
import SwiftData

struct LegacySidebar: View {
    @Environment(\.colorScheme) private var colorScheme

    let snippets: [Snippet]
    let collections: [SnippetCollection]
    let frequentlyUsedSnippets: [Snippet]
    let availableLanguages: [SupportedLanguage]
    let sidebarFilteredLanguages: [SupportedLanguage]
    let trashedItemCount: Int
    let backgroundPalette: [Color]

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

    private var theme: Theme { Theme.current(colorScheme) }

    private var topLevelCollections: [SnippetCollection] {
        collections.filter { !$0.isDeleted && ($0.parent == nil || $0.parent?.isDeleted == true) }
            .sorted(by: collectionSort)
    }

    private func collectionSort(_ lhs: SnippetCollection, _ rhs: SnippetCollection) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    var body: some View {
        ZStack {
            theme.canvasDeep.ignoresSafeArea()
            DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.72)
                .opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                sidebarSearchBar
                    .padding(.top, 14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        newSnippetButton

                        librarySection

                        if !frequentlyUsedSnippets.isEmpty {
                            frequentlyUsedSection
                        }
                        if !availableLanguages.isEmpty {
                            languagesSection
                        }

                        sidebarRow(
                            icon: "trash",
                            title: "Recently Deleted",
                            count: trashedItemCount,
                            isActive: sidebarSelectionContext == .trash,
                            accent: .red
                        ) {
                            sidebarSelectionContext = .trash
                            selectedSnippetID = nil
                            selectedCollectionID = nil
                            selectedLanguages.removeAll()
                            selectedSearchCollections.removeAll()
                        }

                        Spacer(minLength: 12)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
                .scrollIndicators(.hidden)

                sidebarFooter
            }
        }
    }

    private var sidebarSearchBar: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(Mono.font(size: 11, weight: .bold))
                .foregroundStyle(theme.textFaint)
            TextField("filter languages…", text: $sidebarSearch)
                .textFieldStyle(.plain)
                .font(Mono.font(size: 11))
                .foregroundStyle(theme.text)
            if !sidebarSearch.isEmpty {
                Button {
                    sidebarSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(theme.surface.opacity(0.6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(theme.border, lineWidth: 1)
                }
        }
        .padding(.horizontal, 14)
    }

    private var newSnippetButton: some View {
        Button {
            onNew()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(Mono.font(size: 12, weight: .bold))
                Text("new collection")
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    Text("⌘")
                    Text("⇧N")
                }
                .font(Mono.font(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background {
                    Capsule(style: .continuous)
                        .fill(.white.opacity(0.14))
                }
            }
            .font(Mono.font(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Capsule(style: .continuous)
                    .fill(theme.accent)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command, .shift])
    }

    private var librarySection: some View {
        DisclosureGroup(isExpanded: $isLibrarySectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                DisclosureGroup(isExpanded: $isAllSnippetsExpanded) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snippets) { snippet in
                            sidebarSnippetRow(for: snippet, context: .allSnippets)
                        }
                    }
                    .padding(.leading, 12)
                } label: {
                    sidebarRow(
                        icon: "square.grid.2x2",
                        title: "All Snippets",
                        count: snippets.count,
                        isActive: selectedLanguages.isEmpty && selectedSnippetID == nil && selectedCollectionID == nil && sidebarSelectionContext != .trash,
                        accent: theme.accent
                    ) {
                        selectedLanguages.removeAll()
                        selectedSearchCollections.removeAll()
                        selectedSnippetID = nil
                        selectedCollectionID = nil
                        sidebarSelectionContext = .allSnippets
                    }
                    .dropDestination(for: String.self) { items, _ in
                        return onHandleDrop(items, nil)
                    }
                }

                ForEach(topLevelCollections) { collection in
                    legacyCollectionTree(for: collection)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("snippets")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }


    private var frequentlyUsedSection: some View {
        DisclosureGroup(isExpanded: $isFrequentlyUsedSectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(frequentlyUsedSnippets) { snippet in
                    frequentlyUsedRow(for: snippet)
                }
            }
            .padding(.top, 4)
        } label: {
            Text("frequently used")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }

    private var languagesSection: some View {
        DisclosureGroup(isExpanded: $isLanguagesSectionExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("languages")
                        .font(Mono.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                    Text("\(sidebarFilteredLanguages.count)")
                        .font(Mono.font(size: 10, weight: .medium))
                        .foregroundStyle(theme.textFaint)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 2)

                ForEach(sidebarFilteredLanguages) { language in
                    sidebarRow(
                        icon: language.symbolName,
                        title: language.rawValue.lowercased(),
                        count: snippets.filter { $0.language == language.rawValue }.count,
                        isActive: selectedLanguages.contains(language) && selectedSnippetID == nil,
                        accent: Color(hex: language.accentHex) ?? theme.accent
                    ) {
                        if selectedLanguages.contains(language) {
                            selectedLanguages.remove(language)
                        } else {
                            selectedLanguages.insert(language)
                        }
                        selectedSnippetID = nil
                        selectedCollectionID = nil
                        sidebarSelectionContext = .allSnippets
                    }
                }
                if sidebarFilteredLanguages.isEmpty && !sidebarSearch.isEmpty {
                    Text("no matches")
                        .font(Mono.font(size: 11))
                        .foregroundStyle(theme.textFaint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
            }
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text("languages")
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                Text("\(sidebarFilteredLanguages.count)")
                    .font(Mono.font(size: 10, weight: .medium))
                    .foregroundStyle(theme.textFaint)
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(
        icon: String,
        title: String,
        count: Int,
        isActive: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(isActive ? .white : accent)
                Text(title)
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : theme.textMuted)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? .white.opacity(0.8) : theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func frequentlyUsedRow(for snippet: Snippet) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == .frequentlyUsed
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = .frequentlyUsed
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? .white : accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            snippetContextMenu(for: snippet)
        }
    }

    @ViewBuilder
    private func collectionRow(for collection: SnippetCollection) -> some View {
        let accent = collection.displayColor
        let isActive = selectedCollectionID == collection.persistentModelID && selectedSnippetID == nil && sidebarSelectionContext == .collection(collection.persistentModelID)
        Button {
            if selectedCollectionID == collection.persistentModelID && sidebarSelectionContext == .collection(collection.persistentModelID) {
                selectedCollectionID = nil
                sidebarSelectionContext = .allSnippets
                selectedSearchCollections.removeAll()
            } else {
                selectedCollectionID = collection.persistentModelID
                sidebarSelectionContext = .collection(collection.persistentModelID)
                selectedSearchCollections.removeAll()
            }
            selectedSnippetID = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collection.displayIconName)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(isActive ? .white : accent)

                Text(collection.name.lowercased())
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : theme.textMuted)
                Spacer(minLength: 4)
                Text("\(collection.snippets.filter { $0.deletedAt == nil }.count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? .white.opacity(0.8) : theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { onEditCollection(collection) } label: {
                Label("Edit collection", systemImage: "pencil")
            }
            Button(role: .destructive) { onDeleteCollection(collection) } label: {
                Label("Delete collection", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func legacyCollectionTree(for collection: SnippetCollection) -> some View {
        let isExpanded = Binding(
            get: { expandedCollections.contains(collection.persistentModelID) },
            set: { if $0 { expandedCollections.insert(collection.persistentModelID) } else { expandedCollections.remove(collection.persistentModelID) } }
        )
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(collection.children) { child in
                    AnyView(legacyCollectionTree(for: child))
                }
                ForEach(collection.snippets.filter { $0.deletedAt == nil }) { snippet in
                    sidebarSnippetRow(for: snippet, context: .collection(collection.persistentModelID))
                }
            }
            .padding(.leading, 12)
        } label: {
            collectionRow(for: collection)
                .dropDestination(for: String.self) { items, _ in
                    return onHandleDrop(items, collection)
                }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: 10) {
            footerStat(icon: "doc.text", value: "\(snippets.count)", label: "snips")
            footerStat(icon: "chevron.left.forwardslash.chevron.right", value: "\(availableLanguages.count)", label: "langs")
            Spacer()
            if let last = snippets.first {
                Text(last.updatedAt, format: .relative(presentation: .numeric))
                    .font(Mono.font(size: 10))
                    .foregroundStyle(theme.textFaint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(theme.surfaceElevated.opacity(0.5))
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }
        }
    }

    private func footerStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(Mono.font(size: 9, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Text(value)
                .font(Mono.font(size: 11, weight: .bold))
                .foregroundStyle(theme.text)
            Text(label)
                .font(Mono.font(size: 10))
                .foregroundStyle(theme.textFaint)
        }
    }

    @ViewBuilder
    private func snippetContextMenu(for snippet: Snippet) -> some View {
        Button { onEditSnippet(snippet) } label: {
            Label("Edit snippet", systemImage: "pencil")
        }
        Button(role: .destructive) { onDeleteSnippet(snippet) } label: {
            Label("Delete snippet", systemImage: "trash")
        }
        Menu("Move to") {
            Button { onMoveSnippetToLibrary(snippet) } label: {
                Label("All snippets", systemImage: "square.grid.2x2")
            }
            ForEach(collections) { collection in
                Button { onMoveSnippetToCollection(snippet, collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
        Menu("Copy to") {
            ForEach(collections) { collection in
                Button { onCopySnippetToCollection(snippet, collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarSnippetRow(for snippet: Snippet, context: ContentView.SidebarSelectionContext) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = context
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isActive ? .white : accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? .white : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
            snippetContextMenu(for: snippet)
        }
    }
}

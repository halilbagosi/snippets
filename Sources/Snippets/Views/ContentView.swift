import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(filter: #Predicate<Snippet> { $0.deletedAt == nil }, sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var snippets: [Snippet]
    @Query(sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var allSnippets: [Snippet]
    @Query(sort: [SortDescriptor(\SnippetCollection.updatedAt, order: .reverse)])
    private var collections: [SnippetCollection]

    @State private var selectedLanguages: Set<SupportedLanguage> = []
    @State private var selectedSearchCollections: Set<PersistentIdentifier> = []
    @State private var searchText: String = ""
    @State private var editingSnippet: Snippet? = nil
    @State private var isPresentingNew: Bool = false
    @State private var isPresentingCollectionEditor: Bool = false
    @State private var editingCollection: SnippetCollection? = nil
    @State private var collectionDraftName: String = ""
    @State private var collectionDraftColor: Color = Color(hex: SnippetCollection.defaultColorHex) ?? .accentColor
    @State private var collectionDraftIconName: String = SnippetCollection.defaultIconName
    @State private var collectionDraftSnippetIDs: Set<PersistentIdentifier> = []
    @State private var collectionDraftParentID: PersistentIdentifier? = nil
    @State private var isSubcollectionDraft: Bool = false
    @State private var selectedSnippetID: PersistentIdentifier? = nil
    enum SidebarSelectionContext: Hashable {
        case frequentlyUsed
        case allSnippets
        case trash
        case collection(PersistentIdentifier)
    }
    @State private var sidebarSelectionContext: SidebarSelectionContext? = nil
    @State private var selectedCollectionID: PersistentIdentifier? = nil
    @State private var sidebarSearch: String = ""
    @State private var isLibrarySectionExpanded: Bool = true
    @State private var isFrequentlyUsedSectionExpanded: Bool = true
    @State private var isLanguagesSectionExpanded: Bool = true
    @State private var isAllSnippetsExpanded: Bool = false
    @State private var expandedCollections: Set<PersistentIdentifier> = []
    @State private var lastDeletedSnippet: DeletedSnippetSnapshot? = nil
    

    private struct DeletedMediaSnapshot {
        let fileName: String
        let kind: MediaKind
        let addedAt: Date
    }

    private struct DeletedSnippetSnapshot {
        let id: PersistentIdentifier
        let title: String
        let snippetDescription: String
        let language: String
        let code: String
        let createdAt: Date
        let updatedAt: Date
        let copyCount: Int
        let mediaItems: [DeletedMediaSnapshot]
        let collectionIDs: [PersistentIdentifier]
    }

    private var topLevelCollections: [SnippetCollection] {
        collections.filter { $0.parent == nil }
    }

    private var collectionNameMatches: [SnippetCollection] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return collections.filter { $0.name.lowercased().contains(needle) }
    }

    private var baseFilteredSnippets: [Snippet] {
        snippets.filter { snippet in
            if !selectedLanguages.isEmpty, let lang = SupportedLanguage(rawValue: snippet.language), !selectedLanguages.contains(lang) { return false }
            
            let belongsToCollection = { (colID: PersistentIdentifier) -> Bool in
                if let collection = collections.first(where: { $0.persistentModelID == colID }) {
                    let allowedIDs = collection.allDescendantIDs
                    return snippet.collections.contains(where: { allowedIDs.contains($0.persistentModelID) })
                }
                return false
            }

            if let selectedCollectionID {
                if !belongsToCollection(selectedCollectionID) { return false }
            }
            
            if !selectedSearchCollections.isEmpty {
                if !selectedSearchCollections.contains(where: { belongsToCollection($0) }) { return false }
            }
            
            return true
        }
    }

    private var snippetsInCollectionSearchSection: [Snippet] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var matchedIDs = Set<PersistentIdentifier>()
        for col in collectionNameMatches {
            matchedIDs.formUnion(col.allDescendantIDs)
        }
        return baseFilteredSnippets.filter { snippet in
            snippet.collections.contains(where: { matchedIDs.contains($0.persistentModelID) })
        }
    }

    private var snippetsInContentSearchSection: [Snippet] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let needle = searchText.lowercased()
        let alreadyIncluded = Set(snippetsInCollectionSearchSection.map(\.persistentModelID))
        return baseFilteredSnippets.filter { snippet in
            let containsText =
                snippet.title.lowercased().contains(needle) ||
                snippet.snippetDescription.lowercased().contains(needle) ||
                snippet.code.lowercased().contains(needle)
            return containsText && !alreadyIncluded.contains(snippet.persistentModelID)
        }
    }

    private var gallerySnippets: [Snippet] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? baseFilteredSnippets : []
    }

    private var availableLanguages: [SupportedLanguage] {
        let used = Set(snippets.compactMap { SupportedLanguage(rawValue: $0.language) })
        return SupportedLanguage.allCases.filter { used.contains($0) }
    }

    private var sidebarFilteredLanguages: [SupportedLanguage] {
        guard !sidebarSearch.isEmpty else { return availableLanguages }
        let needle = sidebarSearch.lowercased()
        return availableLanguages.filter { $0.rawValue.lowercased().contains(needle) }
    }

    private var frequentlyUsedSnippets: [Snippet] {
        Array(
            snippets.sorted {
                if $0.copyCount != $1.copyCount {
                    return $0.copyCount > $1.copyCount
                }
                return $0.updatedAt > $1.updatedAt
            }
            .prefix(5)
        )
    }

    private var trashedSnippetCount: Int {
        allSnippets.filter { $0.deletedAt != nil }.count
    }

    private var selectedSnippet: Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return snippets.first(where: { $0.persistentModelID == id })
    }

    private var selectedCollection: SnippetCollection? {
        guard let id = selectedCollectionID else { return nil }
        return collections.first(where: { $0.persistentModelID == id })
    }

    private var backgroundPalette: [Color] {
        var colors: [Color] = []
        var seenHex = Set<String>()

        for snippet in snippets {
            guard
                let language = SupportedLanguage(rawValue: snippet.language),
                !seenHex.contains(language.accentHex.lowercased())
            else { continue }

            seenHex.insert(language.accentHex.lowercased())
            colors.append(theme.accentColor(for: language))
        }
        return colors
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if sidebarSelectionContext == .trash {
                TrashView()
            } else {
                ZStack {
                    Group {
                        DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.78)
                            .ignoresSafeArea()
                    }

                    VStack(spacing: 0) {
                        SnippetGalleryView(
                            snippets: gallerySnippets,
                            collectionMatchSnippets: snippetsInCollectionSearchSection,
                            contentMatchSnippets: snippetsInContentSearchSection,
                            searchQuery: searchText.trimmingCharacters(in: .whitespacesAndNewlines),
                            searchText: $searchText,
                            selectedLanguages: $selectedLanguages,
                            selectedSearchCollections: $selectedSearchCollections,
                            availableLanguages: availableLanguages,
                            availableCollections: collections,
                            onSelect: { snippet in
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    selectedSnippetID = snippet.persistentModelID
                                    if let colID = selectedCollectionID {
                                        sidebarSelectionContext = .collection(colID)
                                    } else {
                                        sidebarSelectionContext = .allSnippets
                                    }
                                }
                            },
                            onNew: { isPresentingNew = true },
                            onDelete: { snippet in delete(snippet) },
                            onUndoDelete: { restoreLastDeletedSnippet() }
                        )
                        .blur(radius: selectedSnippet == nil ? 0 : 2)
                        .saturation(selectedSnippet == nil ? 1.0 : 0.95)
                        .allowsHitTesting(selectedSnippet == nil)

                        StatusBar(segments: detailStatusSegments())
                    }

                    if let snippet = selectedSnippet {
                        Color.black
                            .opacity(colorScheme == .dark ? 0.34 : 0.22)
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                    selectedSnippetID = nil
                                }
                            }
                            .transition(.opacity)
                            .zIndex(1)

                        GeometryReader { proxy in
                            let cardWidth = min(max(proxy.size.width * 0.86, 700), 1080)
                            let cardHeight = min(max(proxy.size.height * 0.84, 500), 860)

                            SnippetDetailView(snippet: snippet) {
                                editingSnippet = snippet
                            } onDelete: {
                                delete(snippet)
                            } onClose: {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                    selectedSnippetID = nil
                                }
                            }
                            .frame(width: cardWidth, height: cardHeight)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(theme.surface)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(theme.borderStrong, lineWidth: 1)
                                    }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.52 : 0.24), radius: 30, x: 0, y: 18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
                                    removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                                )
                            )
                        }
                        .zIndex(2)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: selectedSnippetID)
            }
        } // Closing missing brace for `detail: {`
        .task {
            performTrashCleanup()
        }
        .sheet(isPresented: $isPresentingNew) {
            SnippetEditorView(mode: .create, availableCollections: collections) { newSnippet in
                modelContext.insert(newSnippet)
                try? modelContext.save()
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    selectedSnippetID = newSnippet.persistentModelID
                    sidebarSelectionContext = .allSnippets
                }
            }
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(mode: .edit(snippet), availableCollections: collections) { _ in
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $isPresentingCollectionEditor) {
            CollectionEditorSheet(
                title: editingCollection == nil ? "New collection" : "Edit collection",
                collectionName: $collectionDraftName,
                collectionColor: $collectionDraftColor,
                collectionIconName: $collectionDraftIconName,
                selectedSnippetIDs: $collectionDraftSnippetIDs,
                parentCollectionID: $collectionDraftParentID,
                isSubcollection: $isSubcollectionDraft,
                editingCollectionID: editingCollection?.persistentModelID,
                snippets: snippets,
                collections: collections,
                onCancel: { isPresentingCollectionEditor = false },
                onSave: { commitCollectionEditor() }
            )
        }
    }

    private var theme: Theme { Theme.current(colorScheme) }

    private func detailStatusSegments() -> [StatusBar.Segment] {
        var segs: [StatusBar.Segment] = []
        segs.append(.init(icon: "terminal", label: "snippets"))
        if let snippet = selectedSnippet {
            let lang = SupportedLanguage(rawValue: snippet.language) ?? .unknown
            let lines = snippet.code.split(separator: "\n").count
            segs.append(.init(label: "ln \(max(lines, 1))"))
            segs.append(.init(label: lang.rawValue.lowercased(), tint: Color(hex: lang.accentHex)))
            if !snippet.mediaItems.isEmpty {
                segs.append(.init(icon: "paperclip", label: "\(snippet.mediaItems.count)"))
            }
        } else {
            segs.append(.init(label: "\(baseFilteredSnippets.count) / \(snippets.count) snippets"))
            if !selectedLanguages.isEmpty {
                let langsStr = selectedLanguages.map { $0.rawValue.lowercased() }.joined(separator: ", ")
                segs.append(.init(label: "filter: \(langsStr)", tint: theme.accent))
            }
            if let selectedCollection {
                segs.append(.init(label: "collection: \(selectedCollection.name.lowercased())", tint: selectedCollection.displayColor))
            }
        }
        segs.append(.init(label: "utf-8"))
        return segs
    }

    @ViewBuilder
    private var sidebar: some View {
        if #available(macOS 26.0, *) {
            modernSidebar
        } else {
            legacySidebar
        }
    }

    // MARK: - Modern (Tahoe / macOS 26+) sidebar

    @available(macOS 26.0, *)
    private var modernSidebar: some View {
        ModernSidebar(
            snippets: snippets,
            collections: collections,
            frequentlyUsedSnippets: frequentlyUsedSnippets,
            availableLanguages: availableLanguages,
            sidebarFilteredLanguages: sidebarFilteredLanguages,
            trashedSnippetCount: trashedSnippetCount,
            sidebarSearch: $sidebarSearch,
            selectedLanguages: $selectedLanguages,
            selectedSearchCollections: $selectedSearchCollections,
            selectedSnippetID: $selectedSnippetID,
            sidebarSelectionContext: $sidebarSelectionContext,
            selectedCollectionID: $selectedCollectionID,
            isLibrarySectionExpanded: $isLibrarySectionExpanded,
            isFrequentlyUsedSectionExpanded: $isFrequentlyUsedSectionExpanded,
            isLanguagesSectionExpanded: $isLanguagesSectionExpanded,
            isAllSnippetsExpanded: $isAllSnippetsExpanded,
            expandedCollections: $expandedCollections,
            onNew: { beginCreateCollection() },
            onEditCollection: { collection in beginEditCollection(collection) },
            onDeleteCollection: { collection in delete(collection) },
            onEditSnippet: { snippet in editingSnippet = snippet },
            onDeleteSnippet: { snippet in delete(snippet) },
            onMoveSnippetToLibrary: { snippet in moveSnippetToLibrary(snippet) },
            onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },
            onCopySnippetToCollection: { snippet, collection in copySnippet(snippet, to: collection) },
            onHandleDrop: { items, collection in handleDrop(items: items, to: collection) }
        )
    }

    // MARK: - Legacy (pre-Tahoe) sidebar

    private var legacySidebar: some View {
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
                            title: "trash",
                            count: trashedSnippetCount,
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
            beginCreateCollection()
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
                        title: "all snippets",
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
                        return handleDrop(items: items, to: nil)
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
                    .foregroundStyle(accent)
                Text(title)
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
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
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
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
            } else {
                selectedCollectionID = collection.persistentModelID
                sidebarSelectionContext = .collection(collection.persistentModelID)
            }
            selectedSearchCollections.removeAll()
            selectedLanguages.removeAll()
            selectedSnippetID = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: collection.displayIconName)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .foregroundStyle(accent)
                
                Text(collection.name.lowercased())
                    .font(Mono.font(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(collection.snippets.filter { $0.deletedAt == nil }.count)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { beginEditCollection(collection) } label: {
                Label("Edit collection", systemImage: "pencil")
            }
            Button(role: .destructive) { delete(collection) } label: {
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
                    return handleDrop(items: items, to: collection)
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

    private func delete(_ snippet: Snippet) {
        lastDeletedSnippet = DeletedSnippetSnapshot(
            id: snippet.persistentModelID,
            title: snippet.title,
            snippetDescription: snippet.snippetDescription,
            language: snippet.language,
            code: snippet.code,
            createdAt: snippet.createdAt,
            updatedAt: snippet.updatedAt,
            copyCount: snippet.copyCount,
            mediaItems: snippet.mediaItems.map { item in
                DeletedMediaSnapshot(fileName: item.fileName, kind: item.kind, addedAt: item.addedAt)
            },
            collectionIDs: snippet.collections.map(\.persistentModelID)
        )

        if selectedSnippetID == snippet.persistentModelID {
            selectedSnippetID = nil
        }
        // Soft-delete: set deletedAt so the snippet is retained in Trash for 30 days
        snippet.deletedAt = Date.now
        snippet.updatedAt = .now
        try? modelContext.save()
    }

    private func restoreLastDeletedSnippet() -> PersistentIdentifier? {
        guard let snapshot = lastDeletedSnippet else { return nil }

        // Try to find the existing (soft-deleted) snippet and clear its deletedAt
        if let existing = allSnippets.first(where: { $0.persistentModelID == snapshot.id }) {
            existing.deletedAt = nil
            existing.updatedAt = .now
            try? modelContext.save()
            lastDeletedSnippet = nil
            return existing.persistentModelID
        }

        // Fallback: recreate from snapshot if the original object isn't available
        let restoredMedia = snapshot.mediaItems.map { media in
            MediaItem(fileName: media.fileName, kind: media.kind, addedAt: media.addedAt)
        }
        let restoredSnippet = Snippet(
            title: snapshot.title,
            snippetDescription: snapshot.snippetDescription,
            language: snapshot.language,
            code: snapshot.code,
            createdAt: snapshot.createdAt,
            updatedAt: snapshot.updatedAt,
            copyCount: snapshot.copyCount,
            mediaItems: restoredMedia,
            collections: collections.filter { snapshot.collectionIDs.contains($0.persistentModelID) }
        )

        modelContext.insert(restoredSnippet)
        try? modelContext.save()
        lastDeletedSnippet = nil
        return restoredSnippet.persistentModelID
    }

    private func performTrashCleanup() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.distantPast
        for snippet in allSnippets {
            if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
                for media in snippet.mediaItems {
                    MediaManager.deleteFile(for: media)
                }
                modelContext.delete(snippet)
            }
        }
        try? modelContext.save()
    }

    private func beginCreateCollection() {
        editingCollection = nil
        collectionDraftName = ""
        collectionDraftColor = Color(hex: SnippetCollection.defaultColorHex) ?? theme.accent
        collectionDraftIconName = SnippetCollection.defaultIconName
        collectionDraftSnippetIDs = []
        collectionDraftParentID = nil
        isSubcollectionDraft = false
        isPresentingCollectionEditor = true
    }

    private func beginEditCollection(_ collection: SnippetCollection) {
        editingCollection = collection
        collectionDraftName = collection.name
        collectionDraftColor = collection.displayColor
        collectionDraftIconName = collection.displayIconName
        collectionDraftSnippetIDs = Set(collection.snippets.map(\.persistentModelID))
        collectionDraftParentID = collection.parent?.persistentModelID
        isSubcollectionDraft = collection.parent != nil
        isPresentingCollectionEditor = true
    }

    private func resetCollectionDraft() {
        collectionDraftName = ""
        collectionDraftColor = Color(hex: SnippetCollection.defaultColorHex) ?? theme.accent
        collectionDraftIconName = SnippetCollection.defaultIconName
        collectionDraftSnippetIDs = []
        collectionDraftParentID = nil
        isSubcollectionDraft = false
    }

    private func commitCollectionEditor() {
        let trimmed = collectionDraftName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer {
            resetCollectionDraft()
            isPresentingCollectionEditor = false
        }
        guard !trimmed.isEmpty else { return }
        let colorHex = collectionDraftColor.hexString(fallback: SnippetCollection.defaultColorHex)
        let iconName = SnippetCollection.validSFSymbolName(collectionDraftIconName)
        let collection: SnippetCollection
        if let editingCollection {
            collection = editingCollection
            collection.name = trimmed
        } else if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.parent?.persistentModelID == collectionDraftParentID }) {
            collection = existing
        } else {
            collection = SnippetCollection(name: trimmed, colorHex: colorHex, iconName: iconName)
            modelContext.insert(collection)
        }

        if isSubcollectionDraft, let parentID = collectionDraftParentID, let newParent = collections.first(where: { $0.persistentModelID == parentID }) {
            collection.parent = newParent
        } else {
            collection.parent = nil
        }
        collection.colorHex = colorHex
        collection.iconName = iconName

        let selectedIDs = collectionDraftSnippetIDs
        for snippet in snippets {
            let shouldBeInCollection = selectedIDs.contains(snippet.persistentModelID)
            let isAlreadyInCollection = snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID })
            if shouldBeInCollection && !isAlreadyInCollection {
                snippet.collections.append(collection)
            } else if !shouldBeInCollection && isAlreadyInCollection {
                snippet.collections.removeAll(where: { $0.persistentModelID == collection.persistentModelID })
            }
            if snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID }) {
                snippet.updatedAt = .now
            }
        }
        collection.snippets = snippets.filter { selectedIDs.contains($0.persistentModelID) }
        collection.updatedAt = .now
        try? modelContext.save()
        selectedCollectionID = collection.persistentModelID
        sidebarSelectionContext = .collection(collection.persistentModelID)
        isLibrarySectionExpanded = true
        expandedCollections.insert(collection.persistentModelID)
    }

    @ViewBuilder
    private func snippetContextMenu(for snippet: Snippet) -> some View {
        Button { editingSnippet = snippet } label: {
            Label("Edit snippet", systemImage: "pencil")
        }
        Button(role: .destructive) { delete(snippet) } label: {
            Label("Delete snippet", systemImage: "trash")
        }
        Menu("Move to") {
            Button { moveSnippetToLibrary(snippet) } label: {
                Label("All snippets", systemImage: "square.grid.2x2")
            }
            ForEach(collections) { collection in
                Button { moveSnippet(snippet, to: collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
        Menu("Copy to") {
            ForEach(collections) { collection in
                Button { copySnippet(snippet, to: collection) } label: {
                    Label(collection.name, systemImage: collection.displayIconName)
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarSnippetRow(for snippet: Snippet, context: SidebarSelectionContext) -> some View {
        let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
        let accent = Color(hex: language.accentHex) ?? theme.accent
        let isActive = selectedSnippetID == snippet.persistentModelID && sidebarSelectionContext == context
        Button {
            selectedSnippetID = snippet.persistentModelID
            sidebarSelectionContext = context
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .font(Mono.font(size: 11, weight: isActive ? .semibold : .medium))
                    .foregroundStyle(isActive ? theme.text : theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? accent.opacity(colorScheme == .dark ? 0.15 : 0.10) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(String(snippet.persistentModelID.hashValue))
        .contextMenu {
            snippetContextMenu(for: snippet)
        }
    }

    private func copySnippet(_ snippet: Snippet, to collection: SnippetCollection) {
        if !snippet.collections.contains(where: { $0.persistentModelID == collection.persistentModelID }) {
            snippet.collections.append(collection)
            collection.updatedAt = .now
            snippet.updatedAt = .now
            try? modelContext.save()
        }
    }

    private func handleDrop(items: [String], to collection: SnippetCollection?) -> Bool {
        guard let first = items.first, let hash = Int(first) else { return false }
        guard let snippet = snippets.first(where: { $0.persistentModelID.hashValue == hash }) else { return false }
        
        if let collection {
            moveSnippet(snippet, to: collection)
        } else {
            moveSnippetToLibrary(snippet)
        }
        return true
    }

    private func delete(_ collection: SnippetCollection) {
        for snippet in snippets {
            snippet.collections.removeAll(where: { $0.persistentModelID == collection.persistentModelID })
        }
        if selectedCollectionID == collection.persistentModelID {
            selectedCollectionID = nil
        }
        if sidebarSelectionContext == .collection(collection.persistentModelID) {
            sidebarSelectionContext = .allSnippets
        }
        modelContext.delete(collection)
        try? modelContext.save()
    }

    private func moveSnippetToLibrary(_ snippet: Snippet) {
        for collection in collections {
            collection.snippets.removeAll(where: { $0.persistentModelID == snippet.persistentModelID })
            collection.updatedAt = .now
        }
        snippet.collections = []
        snippet.updatedAt = .now
        try? modelContext.save()
    }

    private func moveSnippet(_ snippet: Snippet, to collection: SnippetCollection) {
        for other in collections {
            other.snippets.removeAll(where: { $0.persistentModelID == snippet.persistentModelID })
        }
        snippet.collections = [collection]
        if !collection.snippets.contains(where: { $0.persistentModelID == snippet.persistentModelID }) {
            collection.snippets.append(snippet)
        }
        collection.updatedAt = .now
        snippet.updatedAt = .now
        try? modelContext.save()
    }
}


// MARK: - Modern sidebar (native SwiftUI + Liquid Glass on macOS 26+)

@available(macOS 26.0, *)
private struct ModernSidebar: View {
    @Environment(\.colorScheme) private var colorScheme

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
    let trashedSnippetCount: Int

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
        collections.filter { $0.parent == nil }
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
                    selectedLanguages.removeAll()
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
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                        }
                        .tag(Selection.snippet(snippet.persistentModelID, .allSnippets))
                        .draggable(String(snippet.persistentModelID.hashValue))
                        .contextMenu {
                            Button { onEditSnippet(snippet) } label: { Label("Edit snippet", systemImage: "pencil") }
                            Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                            Menu("Move to") {
                                Button { onMoveSnippetToLibrary(snippet) } label: { Label("All snippets", systemImage: "square.grid.2x2") }
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
                    Label {
                        HStack {
                            Text("All snippets")
                            Spacer()
                            Text("\(snippets.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    } icon: {
                        Image(systemName: "square.grid.2x2")
                    }
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
                        Label {
                            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } icon: {
                            Circle()
                                .fill(accent)
                                .frame(width: 8, height: 8)
                        }
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
                        Label {
                            HStack {
                                Text(language.rawValue)
                                Spacer()
                                Text("\(count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: language.symbolName)
                                .foregroundStyle(accent)
                        }
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
                Label {
                    HStack {
                        Text("Trash")
                        Spacer()
                        Text("\(trashedSnippetCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                } icon: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .tag(Selection.trash)
                .foregroundStyle(.red)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .searchable(
            text: $sidebarSearch,
            placement: .sidebar,
            prompt: Text("Filter languages")
        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: onNew) {
                Label("New Collection", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent)
            .controlSize(.large)
            .clipShape(Capsule(style: .continuous))
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
                    Button(role: .destructive) { onDeleteSnippet(snippet) } label: { Label("Delete snippet", systemImage: "trash") }
                    Menu("Move to") {
                        Button { onMoveSnippetToLibrary(snippet) } label: { Label("All snippets", systemImage: "square.grid.2x2") }
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
            Label {
                HStack {
                    Text(collection.name)
                    Spacer()
                    Text("\(collection.snippets.filter { $0.deletedAt == nil }.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: collection.displayIconName)
                    .foregroundStyle(collection.displayColor)
            }
        }
        .tag(Selection.collection(collection.persistentModelID))
        .contextMenu {
            Button { onEditCollection(collection) } label: { Label("Edit collection", systemImage: "pencil") }
            Button(role: .destructive) { onDeleteCollection(collection) } label: { Label("Delete collection", systemImage: "trash") }
        }
        .dropDestination(for: String.self) { items, _ in return onHandleDrop(items, collection) }
    }
}

private struct CollectionEditorSheet: View {
    @Environment(\.colorScheme) private var colorScheme

    private struct SymbolSection: Identifiable {
        let title: String
        let symbols: [String]

        var id: String { title }
    }

    private struct ColorChoice: Identifiable {
        let name: String
        let hex: String

        var id: String { hex }
    }

    let title: String
    @Binding var collectionName: String
    @Binding var collectionColor: Color
    @Binding var collectionIconName: String
    @Binding var selectedSnippetIDs: Set<PersistentIdentifier>
    @Binding var parentCollectionID: PersistentIdentifier?
    @Binding var isSubcollection: Bool
    let editingCollectionID: PersistentIdentifier?
    let snippets: [Snippet]
    let collections: [SnippetCollection]
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var symbolSearch: String = ""
    @State private var isSnippetPickerExpanded: Bool = false

    private let symbolColumns = Array(repeating: GridItem(.flexible(minimum: 42, maximum: 56), spacing: 18), count: 7)
    private let palette: [ColorChoice] = [
        .init(name: "Red", hex: "#FF453A"),
        .init(name: "Orange", hex: "#FF9F0A"),
        .init(name: "Yellow", hex: "#FFD60A"),
        .init(name: "Green", hex: "#30D158"),
        .init(name: "Blue", hex: "#0A84FF"),
        .init(name: "Purple", hex: "#BF5AF2"),
        .init(name: "Pink", hex: "#FF375F"),
        .init(name: "Gray", hex: "#8E8E93")
    ]
    private let symbolSections: [SymbolSection] = [
        .init(title: "Code", symbols: [
            "curlybraces", "terminal", "chevron.left.forwardslash.chevron.right", "command",
            "apple.terminal", "doc.plaintext", "doc.text", "doc.on.doc",
            "text.alignleft", "number", "function", "sum",
            "at", "cpu", "memorychip", "server.rack",
            "externaldrive", "internaldrive", "network", "point.3.connected.trianglepath.dotted"
        ]),
        .init(title: "Objects", symbols: [
            "tag", "bookmark", "paperclip", "link",
            "pin", "archivebox", "tray.full", "shippingbox",
            "lock", "key", "hammer", "wrench.and.screwdriver",
            "paintpalette", "wand.and.stars", "camera", "photo",
            "video", "play.rectangle", "music.note", "waveform"
        ]),
        .init(title: "People", symbols: [
            "person", "person.fill", "person.2", "person.2.fill",
            "person.crop.circle", "person.crop.circle.fill", "figure.stand", "figure.walk",
            "figure.wave", "figure.2.and.child.holdinghands", "person.3", "person.3.fill",
            "brain.head.profile", "eye", "eyes", "ear",
            "hand.raised", "hand.thumbsup", "hand.thumbsdown", "hand.tap",
            "hand.point.up.left", "hand.point.right", "hand.wave", "face.smiling"
        ]),
        .init(title: "Animals & Nature", symbols: [
            "hare", "tortoise", "dog", "cat",
            "bird", "fish", "pawprint", "ladybug",
            "leaf", "tree", "globe.americas", "globe.europe.africa",
            "sun.max", "sunrise", "sunset", "moon",
            "sparkles", "cloud", "flame", "drop"
        ])
    ]

    private var theme: Theme { Theme.current(colorScheme) }

    private var trimmedName: String {
        collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedIconName: String {
        collectionIconName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSymbolValid: Bool {
        SnippetCollection.isValidSFSymbolName(trimmedIconName)
    }

    private var previewIconName: String {
        isSymbolValid ? trimmedIconName : SnippetCollection.defaultIconName
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && isSymbolValid
    }

    private var selectedColorHex: String {
        collectionColor.hexString(fallback: SnippetCollection.defaultColorHex).lowercased()
    }

    private var displayedSymbolSections: [SymbolSection] {
        let needle = symbolSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return symbolSections.compactMap { section in
            let symbols = section.symbols.filter { symbol in
                SnippetCollection.isValidSFSymbolName(symbol) &&
                (needle.isEmpty || symbol.lowercased().contains(needle))
            }
            guard !symbols.isEmpty else { return nil }
            return SymbolSection(title: section.title, symbols: symbols)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        previewHeader
                        colorStrip
                        Divider()
                        subcollectionToggleSection
                        Divider()
                        symbolBrowser
                        Divider()
                        snippetMembershipSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: onSave)
                        .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 740)
    }

    private var previewHeader: some View {
        VStack(spacing: 14) {
            CollectionIconView(
                iconName: previewIconName,
                color: collectionColor,
                size: 68,
                isSelected: true
            )
            .frame(height: 82)

            TextField("Collection name", text: $collectionName)
                .textFieldStyle(.plain)
                .font(.system(size: 24, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var colorStrip: some View {
        HStack(spacing: 16) {
            Image(systemName: "tag")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(theme.textFaint)
                .frame(width: 30)

            ForEach(palette) { choice in
                Button {
                    collectionColor = Color(hex: choice.hex) ?? collectionColor
                } label: {
                    let isSelected = selectedColorHex == choice.hex.lowercased()
                    Circle()
                        .fill(Color(hex: choice.hex) ?? theme.accent)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Circle()
                                .strokeBorder(isSelected ? .white.opacity(0.92) : .black.opacity(0.14), lineWidth: isSelected ? 3 : 1)
                        }
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.14), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .help(choice.name)
            }

            ZStack {
                Circle()
                    .fill(collectionColor.opacity(0.34))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Circle()
                            .strokeBorder(theme.borderStrong, lineWidth: 1)
                    }
                Image(systemName: "plus")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(collectionColor)
                    .allowsHitTesting(false)
                ColorPicker("", selection: $collectionColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 40, height: 40)
                    .opacity(0.02)
            }
            .help("Custom color")
        }
        .frame(maxWidth: .infinity)
    }

    private var symbolBrowser: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.textFaint)
                TextField("Search SF Symbols", text: $symbolSearch)
                    .textFieldStyle(.plain)
                if !symbolSearch.isEmpty {
                    Button {
                        symbolSearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(theme.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    }
            }

            ForEach(displayedSymbolSections) { section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(theme.text)

                    LazyVGrid(columns: symbolColumns, spacing: 16) {
                        ForEach(section.symbols, id: \.self) { symbolName in
                            symbolButton(symbolName)
                        }
                    }
                }
            }

            if displayedSymbolSections.isEmpty {
                Text("No matching symbols")
                    .font(.callout)
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
    }

    private func symbolButton(_ symbolName: String) -> some View {
        Button {
            collectionIconName = symbolName
        } label: {
            let isSelected = previewIconName == symbolName
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? .white : theme.textMuted)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(isSelected ? collectionColor : Color.clear)
                }
                .overlay {
                    Circle()
                        .strokeBorder(isSelected ? collectionColor.opacity(0.55) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .help(symbolName)
    }

    private var subcollectionToggleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Sub-Collection", isOn: $isSubcollection)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.text)
                .tint(theme.accent)
            
            if isSubcollection {
                Picker("Parent", selection: $parentCollectionID) {
                    Text("Select parent...").tag(nil as PersistentIdentifier?)
                    ForEach(availableParentCollections) { collection in
                        Text(collection.name).tag(collection.persistentModelID as PersistentIdentifier?)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(theme.accent)
            }
        }
    }
    
    private var availableParentCollections: [SnippetCollection] {
        guard let editingID = editingCollectionID else {
            return collections
        }
        // Exclude the collection itself and its descendants to prevent cycles
        var excludedIDs = Set([editingID])
        var queue = [editingID]
        
        while !queue.isEmpty {
            let currentID = queue.removeFirst()
            if let current = collections.first(where: { $0.persistentModelID == currentID }) {
                let childIDs = current.children.map(\.persistentModelID)
                excludedIDs.formUnion(childIDs)
                queue.append(contentsOf: childIDs)
            }
        }
        
        return collections.filter { !excludedIDs.contains($0.persistentModelID) }
    }

    private var snippetMembershipSection: some View {
        DisclosureGroup(isExpanded: $isSnippetPickerExpanded) {
            if snippets.isEmpty {
                Text("No snippets yet")
                    .font(.callout)
                    .foregroundStyle(theme.textMuted)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(snippets) { snippet in
                        snippetToggleRow(snippet)
                        Divider()
                    }
                }
                .padding(.top, 8)
            }
        } label: {
            HStack {
                Text("Snippets")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(selectedSnippetIDs.count)")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.textMuted)
            }
        }
    }

    private func snippetToggleRow(_ snippet: Snippet) -> some View {
        Button {
            if selectedSnippetIDs.contains(snippet.persistentModelID) {
                selectedSnippetIDs.remove(snippet.persistentModelID)
            } else {
                selectedSnippetIDs.insert(snippet.persistentModelID)
            }
        } label: {
            HStack {
                Image(systemName: selectedSnippetIDs.contains(snippet.persistentModelID) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedSnippetIDs.contains(snippet.persistentModelID) ? collectionColor : theme.textFaint)
                Text(snippet.title.isEmpty ? "untitled" : snippet.title)
                    .lineLimit(1)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}

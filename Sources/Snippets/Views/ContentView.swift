import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppearanceSettings.self) private var appearanceSettings

    @Query(filter: #Predicate<Snippet> { $0.deletedAt == nil }, sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var snippets: [Snippet]
    @Query(sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var allSnippets: [Snippet]
    @Query(sort: [SortDescriptor(\SnippetCollection.updatedAt, order: .reverse)])
    private var collections: [SnippetCollection]

    @State private var selectedLanguages: Set<SupportedLanguage> = []
    @State private var selectedSearchCollections: Set<PersistentIdentifier> = []
    @State private var searchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>? = nil
    @State private var cachedAvailableLanguages: [SupportedLanguage] = []
    @State private var cachedBackgroundPalette: [Color] = []
    @State private var hasBuiltDerivedCaches = false
    @State private var editingSnippet: Snippet? = nil
    @State private var isPresentingNew: Bool = false
    @State private var newSnippetPreselectedCollectionID: PersistentIdentifier? = nil
    @State private var isPresentingCollectionEditor: Bool = false
    @State private var editingCollection: SnippetCollection? = nil
    @State private var collectionDraftName: String = ""
    @State private var collectionDraftColor: Color = Color(hex: SnippetCollection.defaultColorHex) ?? .accentColor
    @State private var collectionDraftColorDark: Color? = nil
    @State private var collectionDraftIconName: String = SnippetCollection.defaultIconName
    @State private var collectionDraftSnippetIDs: Set<PersistentIdentifier> = []
    @State private var collectionDraftParentID: PersistentIdentifier? = nil
    @State private var isSubcollectionDraft: Bool = false
    @State private var selectedSnippetID: PersistentIdentifier? = nil
    enum SidebarSelectionContext: Hashable {
        case frequentlyUsed
        case favorites
        case allSnippets
        case trash
        case collection(PersistentIdentifier)
        case favoriteCollection(PersistentIdentifier)
    }
    @State private var sidebarSelectionContext: SidebarSelectionContext? = .allSnippets
    @State private var selectedCollectionID: PersistentIdentifier? = nil
    @State private var sidebarSearch: String = ""
    @State private var showFavoritesOnly: Bool = false
    @State private var showUncategorizedOnly: Bool = false
    @State private var isLibrarySectionExpanded: Bool = true
    @State private var isFavoritesSectionExpanded: Bool = true
    @State private var isFrequentlyUsedSectionExpanded: Bool = true
    @State private var isLanguagesSectionExpanded: Bool = true
    @State private var isAllSnippetsExpanded: Bool = false
    @State private var isCollectionsSectionExpanded: Bool = true
    @State private var expandedCollections: Set<PersistentIdentifier> = []
    enum DeletedItem {
        case snippet(PersistentIdentifier)
        case collection(PersistentIdentifier)
    }
    @State private var lastDeletedItem: DeletedItem? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("suppressCollectionDeleteWarning") private var suppressCollectionDeleteWarning = false
    @AppStorage("suppressSnippetDeleteWarning") private var suppressSnippetDeleteWarning = false

    @State private var snippetToDelete: Snippet?
    @State private var pendingSnippetDeleteConfirm: (() -> Void)?
    @State private var collectionToDelete: SnippetCollection?
    @State private var collectionToDeletePermanent: Bool = false
    @State private var showUndoToast: Bool = false
    @State private var undoToastMessage: String = ""
    @State private var toastHideTask: Task<Void, Never>? = nil

    private var uncategorizedSnippets: [Snippet] {
        snippets.filter { snippet in
            !snippet.collections.contains(where: { !$0.isDeleted })
        }
    }


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
        collections
            .filter { !$0.isDeleted && ($0.parent == nil || $0.parent?.isDeleted == true) }
            .sorted(by: collectionSort)
    }

    private var trimmedSearchText: String {
        debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var collectionLookup: [PersistentIdentifier: SnippetCollection] {
        Dictionary(uniqueKeysWithValues: collections.map { ($0.persistentModelID, $0) })
    }

    private var descendantIDsByCollectionID: [PersistentIdentifier: Set<PersistentIdentifier>] {
        let lookup = collectionLookup
        var cache: [PersistentIdentifier: Set<PersistentIdentifier>] = [:]

        func descendants(for collection: SnippetCollection) -> Set<PersistentIdentifier> {
            let id = collection.persistentModelID
            if let cached = cache[id] { return cached }

            var ids = Set([id])
            for child in collection.children {
                ids.formUnion(descendants(for: child))
            }
            cache[id] = ids
            return ids
        }

        for collection in lookup.values {
            _ = descendants(for: collection)
        }
        return cache
    }

    private var baseFilteredSnippets: [Snippet] {
        let lookup = collectionLookup
        let descendantIDs = descendantIDsByCollectionID

        return snippets.filter { snippet in
            if !selectedLanguages.isEmpty, let lang = SupportedLanguage(rawValue: snippet.language), !selectedLanguages.contains(lang) { return false }

            let belongsDirectlyToCollection = { (colID: PersistentIdentifier) -> Bool in
                snippet.collections.contains(where: { $0.persistentModelID == colID })
            }

            let belongsToCollection = { (colID: PersistentIdentifier) -> Bool in
                guard lookup[colID] != nil, let allowedIDs = descendantIDs[colID] else { return false }
                return snippet.collections.contains(where: { allowedIDs.contains($0.persistentModelID) })
            }

            if let selectedCollectionID {
                if !belongsDirectlyToCollection(selectedCollectionID) { return false }
            }

            if showUncategorizedOnly && snippet.collections.contains(where: { !$0.isDeleted }) {
                return false
            }

            if !selectedSearchCollections.isEmpty {
                if !selectedSearchCollections.contains(where: { belongsToCollection($0) }) { return false }
            }

            if showFavoritesOnly && !snippet.isFavorite { return false }

            return true
        }
    }

    private var searchFilteredSnippets: [Snippet] {
        let lookup = collectionLookup
        let descendantIDs = descendantIDsByCollectionID

        return snippets.filter { snippet in
            if !selectedLanguages.isEmpty, let lang = SupportedLanguage(rawValue: snippet.language), !selectedLanguages.contains(lang) { return false }

            if showFavoritesOnly && !snippet.isFavorite { return false }

            if showUncategorizedOnly && snippet.collections.contains(where: { !$0.isDeleted }) {
                return false
            }

            guard !selectedSearchCollections.isEmpty else { return true }
            return selectedSearchCollections.contains { collectionID in
                guard lookup[collectionID] != nil, let allowedIDs = descendantIDs[collectionID] else { return false }
                return snippet.collections.contains { allowedIDs.contains($0.persistentModelID) }
            }
        }
    }

    private var searchResultCollections: [SnippetCollection] {
        let needle = trimmedSearchText.lowercased()
        guard !needle.isEmpty else { return [] }

        return collections.filter { collection in
            !collection.isDeleted && 
            (!showFavoritesOnly || collection.isFavorite) &&
            collection.name.lowercased().contains(needle)
        }
    }

    private var searchResultSnippets: [Snippet] {
        let needle = trimmedSearchText.lowercased()
        guard !needle.isEmpty else { return [] }

        return searchFilteredSnippets.filter { snippet in
            snippet.title.lowercased().contains(needle) ||
            snippet.snippetDescription.lowercased().contains(needle) ||
            snippet.code.lowercased().contains(needle) ||
            snippet.language.lowercased().contains(needle) ||
            snippet.collections.contains { !$0.isDeleted && $0.name.lowercased().contains(needle) }
        }
    }

    private var gallerySnippets: [Snippet] {
        trimmedSearchText.isEmpty ? baseFilteredSnippets : []
    }

    private var gallerySubcollections: [SnippetCollection] {
        guard trimmedSearchText.isEmpty else { return [] }

        if
            let selectedCollection,
            sidebarSelectionContext == .collection(selectedCollection.persistentModelID)
        {
            let children = selectedCollection.children.sorted(by: collectionSort)
            return showFavoritesOnly ? children.filter(\.isFavorite) : children
        }
        if
            let selectedCollection,
            sidebarSelectionContext == .favoriteCollection(selectedCollection.persistentModelID)
        {
            let children = selectedCollection.children.sorted(by: collectionSort)
            return showFavoritesOnly ? children.filter(\.isFavorite) : children
        }

        if sidebarSelectionContext == .allSnippets {
            let allValidCollections = collections.filter { !$0.isDeleted }.sorted(by: collectionSort)
            return showFavoritesOnly ? allValidCollections.filter(\.isFavorite) : allValidCollections
        }

        let showsTopLevelCollections = sidebarSelectionContext == .frequentlyUsed
            || sidebarSelectionContext == .favorites
        guard selectedCollectionID == nil, showsTopLevelCollections else { return [] }
        return showFavoritesOnly ? topLevelCollections.filter(\.isFavorite) : topLevelCollections
    }

    private var availableLanguages: [SupportedLanguage] {
        hasBuiltDerivedCaches ? cachedAvailableLanguages : buildAvailableLanguages()
    }

    private var sidebarFilteredLanguages: [SupportedLanguage] {
        guard !sidebarSearch.isEmpty else { return availableLanguages }
        let needle = sidebarSearch.lowercased()
        return availableLanguages.filter { $0.rawValue.lowercased().contains(needle) }
    }

    private var frequentlyUsedSnippets: [Snippet] {
        var top: [Snippet] = []

        for snippet in snippets {
            if top.count < 5 {
                insertFrequentlyUsed(snippet, into: &top)
            } else if let last = top.last, frequentlyUsedPrecedes(snippet, last) {
                top.removeLast()
                insertFrequentlyUsed(snippet, into: &top)
            }
        }

        return top
    }

    private var favoriteSnippets: [Snippet] {
        snippets.filter(\.isFavorite).sorted(by: { $0.updatedAt > $1.updatedAt })
    }

    private var favoriteCollections: [SnippetCollection] {
        collections.filter(\.isFavorite).sorted(by: collectionSort)
    }

    private var trashedItemCount: Int {
        allSnippets.filter { $0.deletedAt != nil }.count + collections.filter { $0.deletedAt != nil }.count
    }

    private var selectedSnippet: Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return snippets.first(where: { $0.persistentModelID == id })
    }

    private var selectedCollection: SnippetCollection? {
        guard let id = selectedCollectionID else { return nil }
        return collectionLookup[id]
    }

    private func frequentlyUsedPrecedes(_ lhs: Snippet, _ rhs: Snippet) -> Bool {
        if lhs.copyCount != rhs.copyCount {
            return lhs.copyCount > rhs.copyCount
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private func insertFrequentlyUsed(_ snippet: Snippet, into top: inout [Snippet]) {
        let index = top.firstIndex { frequentlyUsedPrecedes(snippet, $0) } ?? top.endIndex
        top.insert(snippet, at: index)
    }

    private func collectionSort(_ lhs: SnippetCollection, _ rhs: SnippetCollection) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private var backgroundPalette: [Color] {
        hasBuiltDerivedCaches ? cachedBackgroundPalette : buildBackgroundPalette()
    }

    private var snippetLanguageSignature: Int {
        var hasher = Hasher()
        hasher.combine(snippets.count)
        for snippet in snippets {
            hasher.combine(snippet.persistentModelID)
            hasher.combine(snippet.language)
        }
        return hasher.finalize()
    }

    private func rebuildDerivedCaches() {
        cachedAvailableLanguages = buildAvailableLanguages()
        cachedBackgroundPalette = buildBackgroundPalette()
        hasBuiltDerivedCaches = true
    }

    private func buildAvailableLanguages() -> [SupportedLanguage] {
        let used = Set(snippets.compactMap { SupportedLanguage(rawValue: $0.language) })
        return SupportedLanguage.allCases.filter { used.contains($0) }
    }

    private func buildBackgroundPalette() -> [Color] {
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

    private func debounceSearch(_ newValue: String) {
        searchDebounceTask?.cancel()

        if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            debouncedSearchText = newValue
            return
        }

        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debouncedSearchText = newValue
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if sidebarSelectionContext == .trash {
                TrashView()
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        StatusBar(
                            segments: currentStatusSegments,
                            contentLeadingInset: 0
                        )
                    }
            } else {
                ZStack {
                    Group {
                        DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.78, focusedMode: appearanceSettings.focusedMode)
                            .ignoresSafeArea()
                    }

                    VStack(spacing: 0) {
                        SnippetGalleryView(
                            snippets: gallerySnippets,
                            searchResultCollections: searchResultCollections,
                            searchResultSnippets: searchResultSnippets,
                            searchQuery: trimmedSearchText,
                            searchText: $searchText,
                            showFavoritesOnly: $showFavoritesOnly,
                            selectedLanguages: $selectedLanguages,
                            selectedSearchCollections: $selectedSearchCollections,
                            showUncategorizedOnly: $showUncategorizedOnly,
                            availableLanguages: availableLanguages,
                            availableCollections: collections,
                            subcollections: gallerySubcollections,
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
                            onSelectCollection: { collection in
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    selectedSearchCollections.removeAll()
                                    selectedSnippetID = nil
                                    selectedCollectionID = collection.persistentModelID
                                    sidebarSelectionContext = .collection(collection.persistentModelID)
                                }
                            },
                            onCreateCollection: {
                                beginCreateCollection()
                            },
                            onNew: {
                                newSnippetPreselectedCollectionID = selectedCollectionID
                                isPresentingNew = true
                            },
                            onBack: selectedCollectionID != nil ? {
                                navigateBackFromCollection()
                            } : nil,
                            onClearSelection: {
                                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                    selectedSearchCollections.removeAll()
                                    if selectedCollectionID == nil {
                                        sidebarSelectionContext = .allSnippets
                                    }
                                }
                            },
                            onEditCollection: { collection in beginEditCollection(collection) },
                            onDeleteCollection: { collection in delete(collection) },
                            onEditSnippet: { snippet in editingSnippet = snippet },
                            onDelete: { snippet, onConfirmed in delete(snippet, onConfirmed: onConfirmed) },
                            onUndoDelete: { undoLastDeletion() },
                            onMoveSnippetToLibrary: { snippet in moveSnippetToLibrary(snippet) },
                            onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },
                            onCopySnippetToCollection: { snippet, collection in copySnippet(snippet, to: collection) }
                        )
                        .blur(radius: selectedSnippet == nil ? 0 : 2)
                        .saturation(selectedSnippet == nil ? 1.0 : 0.95)
                        .allowsHitTesting(selectedSnippet == nil)
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

                    if isPresentingNew {
                        Color.black
                            .opacity(colorScheme == .dark ? 0.34 : 0.22)
                            .ignoresSafeArea()
                            .onTapGesture {
                                NotificationCenter.default.post(name: .init("AttemptDismissEditor"), object: nil)
                            }
                            .transition(.opacity)
                            .zIndex(3)

                        GeometryReader { proxy in
                            let w = min(max(proxy.size.width * 0.90, 820), 1200)
                            let h = min(max(proxy.size.height * 0.92, 660), 960)
                            SnippetEditorView(
                                mode: .create(preselectedCollectionID: newSnippetPreselectedCollectionID),
                                availableCollections: collections,
                                onRequestDismiss: {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                        isPresentingNew = false
                                    }
                                },
                                onSave: { newSnippet in
                                    modelContext.insert(newSnippet)
                                    try? modelContext.save()
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                        selectedSnippetID = newSnippet.persistentModelID
                                        sidebarSelectionContext = .allSnippets
                                        isPresentingNew = false
                                    }
                                }
                            )
                            .frame(width: w, height: h)
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
                                    removal:   .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                                )
                            )
                        }
                        .zIndex(4)
                    }

                    if showUndoToast {
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Text(undoToastMessage)
                                    .foregroundStyle(theme.text)
                                Button("Undo") {
                                    withAnimation {
                                        _ = undoLastDeletion()
                                        showUndoToast = false
                                    }
                                }
                                .bold()
                                .foregroundStyle(theme.accent)
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.surfaceElevated)
                                    .shadow(radius: 10, y: 5)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(theme.borderStrong, lineWidth: 1)
                                    }
                            }
                            .padding(.bottom, 60)
                        }
                        .zIndex(100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: selectedSnippetID)
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: isPresentingNew)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBar(
                        segments: currentStatusSegments,
                        contentLeadingInset: 0
                    )
                }
            }
        }
        .task {
            performTrashCleanup()
            debouncedSearchText = searchText
            rebuildDerivedCaches()
        }
        .onChange(of: searchText) { _, newValue in
            debounceSearch(newValue)
        }
        .onChange(of: snippets.count) { _, _ in
            rebuildDerivedCaches()
        }
        .onChange(of: snippetLanguageSignature) { _, _ in
            rebuildDerivedCaches()
        }
        .onChange(of: colorScheme) { _, _ in
            rebuildDerivedCaches()
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(mode: .edit(snippet), availableCollections: collections) { _ in
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $isPresentingCollectionEditor) {
            CollectionEditorSheet(
                collectionName: $collectionDraftName,
                collectionColor: $collectionDraftColor,
                collectionColorDark: $collectionDraftColorDark,
                collectionIconName: $collectionDraftIconName,
                selectedSnippetIDs: $collectionDraftSnippetIDs,
                parentCollectionID: $collectionDraftParentID,
                isSubcollection: $isSubcollectionDraft,
                editingCollection: $editingCollection,
                snippets: snippets,
                collections: collections,
                onCancel: { isPresentingCollectionEditor = false },
                onSave: { commitCollectionEditor() }
            )
        }
        .confirmationDialog(
            "Delete this snippet?",
            isPresented: Binding(
                get: { snippetToDelete != nil },
                set: { if !$0 { snippetToDelete = nil; pendingSnippetDeleteConfirm = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Snippet", role: .destructive) {
                if let snippet = snippetToDelete {
                    pendingSnippetDeleteConfirm?()
                    DispatchQueue.main.async {
                        self.performDeleteSnippet(snippet)
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if let snippet = snippetToDelete {
                Text("This will move \"\(snippet.title.isEmpty ? "Untitled" : snippet.title)\" to the trash. You can restore it within 30 days.")
            }
        }
        .confirmationDialog(
            "Delete Collection?",
            isPresented: Binding(
                get: { collectionToDelete != nil },
                set: { if !$0 { collectionToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Collection Only", role: .destructive) {
                if let collection = collectionToDelete {
                    performDelete(collection, permanent: collectionToDeletePermanent)
                }
            }
            Button("Delete Collection & Contents", role: .destructive) {
                if let collection = collectionToDelete {
                    deleteCollectionContentsRecursively(collection, permanent: collectionToDeletePermanent)
                    performDelete(collection, permanent: collectionToDeletePermanent)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("What would you like to do with this collection and its contents?")
        }
    }

    private var theme: Theme { Theme.current(colorScheme) }


    private var currentStatusSegments: [StatusBar.Segment] {
        sidebarSelectionContext == .trash ? trashStatusSegments : detailStatusSegments()
    }

    private var trashStatusSegments: [StatusBar.Segment] {
        [
            .init(icon: "trash", label: "trash"),
            .init(label: "\(trashedItemCount) items"),
            .init(label: "auto-delete in 30 days", tint: .red),
        ]
    }

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
            segs.append(.init(label: "\(baseFilteredSnippets.count) / \(snippets.count)"))
            if !selectedLanguages.isEmpty {
                let langsStr = selectedLanguages.map { $0.rawValue.lowercased() }.joined(separator: ", ")
                segs.append(.init(label: "filter: \(langsStr)", tint: theme.accent))
            }
            if let selectedCollection {
                segs.append(.init(label: "collection: \(selectedCollection.name.lowercased())", tint: selectedCollection.displayColor))
            }
        }
        return segs
    }

    private func navigateBackFromCollection() {
        guard let id = selectedCollectionID else { return }
        let parentID = parentCollectionID(for: id)

        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            searchText = ""
            selectedSnippetID = nil
            selectedSearchCollections.removeAll()

            if let parentID {
                selectedCollectionID = parentID
                sidebarSelectionContext = .collection(parentID)
            } else {
                selectedCollectionID = nil
                sidebarSelectionContext = .allSnippets
            }
        }
    }

    private func parentCollectionID(for collectionID: PersistentIdentifier) -> PersistentIdentifier? {
        if let parentID = collections
            .first(where: { $0.persistentModelID == collectionID })?
            .parent?
            .persistentModelID {
            return parentID
        }

        return collections
            .first { parent in
                parent.children.contains { $0.persistentModelID == collectionID }
            }?
            .persistentModelID
    }

    @ViewBuilder
    private var sidebar: some View {
        modernSidebar
    }

    // MARK: - Modern sidebar

    private var modernSidebar: some View {
        ModernSidebar(
            snippets: snippets,
            uncategorizedSnippets: uncategorizedSnippets,
            collections: collections,
            frequentlyUsedSnippets: frequentlyUsedSnippets,
            favoriteSnippets: favoriteSnippets,
            favoriteCollections: favoriteCollections,
            availableLanguages: availableLanguages,
            sidebarFilteredLanguages: sidebarFilteredLanguages,
            trashedItemCount: trashedItemCount,
            sidebarSearch: $sidebarSearch,
            selectedLanguages: $selectedLanguages,
            selectedSearchCollections: $selectedSearchCollections,
            selectedSnippetID: $selectedSnippetID,
            sidebarSelectionContext: $sidebarSelectionContext,
            selectedCollectionID: $selectedCollectionID,
            isLibrarySectionExpanded: $isLibrarySectionExpanded,
            isFavoritesSectionExpanded: $isFavoritesSectionExpanded,
            isFrequentlyUsedSectionExpanded: $isFrequentlyUsedSectionExpanded,
            isLanguagesSectionExpanded: $isLanguagesSectionExpanded,
            isAllSnippetsExpanded: $isAllSnippetsExpanded,
            isCollectionsSectionExpanded: $isCollectionsSectionExpanded,
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



    private func delete(_ snippet: Snippet, onConfirmed: (() -> Void)? = nil) {
        if suppressSnippetDeleteWarning {
            onConfirmed?()
            DispatchQueue.main.async {
                self.performDeleteSnippet(snippet)
            }
            return
        }

        snippetToDelete = snippet
        pendingSnippetDeleteConfirm = onConfirmed
    }

    private func performDeleteSnippet(_ snippet: Snippet) {
        lastDeletedItem = .snippet(snippet.persistentModelID)

        if selectedSnippetID == snippet.persistentModelID {
            selectedSnippetID = nil
        }
        // Soft-delete: set deletedAt so the snippet is retained in Trash for 30 days
        snippet.deletedAt = Date.now
        snippet.updatedAt = .now
        try? modelContext.save()
        
        undoToastMessage = "Snippet moved to Trash."
        withAnimation { showUndoToast = true }
        hideToastAfterDelay()
    }

    private func undoLastDeletion() -> PersistentIdentifier? {
        guard let item = lastDeletedItem else { return nil }

        switch item {
        case .snippet(let id):
            if let existing = allSnippets.first(where: { $0.persistentModelID == id }) {
                existing.deletedAt = nil
                existing.updatedAt = .now
                try? modelContext.save()
                lastDeletedItem = nil
                return existing.persistentModelID
            }
        case .collection(let id):
            if let existing = collections.first(where: { $0.persistentModelID == id }) {
                existing.deletedAt = nil
                existing.updatedAt = .now
                try? modelContext.save()
                lastDeletedItem = nil
                return nil
            }
        }
        return nil
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
        collectionDraftColorDark = nil
        collectionDraftIconName = SnippetCollection.defaultIconName
        collectionDraftSnippetIDs = []
        collectionDraftParentID = nil
        isSubcollectionDraft = false
        isPresentingCollectionEditor = true
    }

    private func beginEditCollection(_ collection: SnippetCollection) {
        editingCollection = collection
        collectionDraftName = collection.name
        collectionDraftColor = Color(hex: collection.colorHex) ?? Color(hex: SnippetCollection.defaultColorHex) ?? theme.accent
        collectionDraftColorDark = collection.colorHexDark.flatMap { Color(hex: $0) }
        collectionDraftIconName = collection.displayIconName
        collectionDraftSnippetIDs = Set(collection.snippets.map(\.persistentModelID))
        collectionDraftParentID = collection.parent?.persistentModelID
        isSubcollectionDraft = collection.parent != nil
        isPresentingCollectionEditor = true
    }

    private func resetCollectionDraft() {
        collectionDraftName = ""
        collectionDraftColor = Color(hex: SnippetCollection.defaultColorHex) ?? theme.accent
        collectionDraftColorDark = nil
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
        let colorHexDark = collectionDraftColorDark?.hexString(fallback: "")
        let finalColorHexDark = colorHexDark?.isEmpty == false ? colorHexDark : nil
        let iconName = SnippetCollection.validSFSymbolName(collectionDraftIconName)
        let collection: SnippetCollection
        if let editingCollection {
            collection = editingCollection
            collection.name = trimmed
        } else if let existing = collections.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame && $0.parent?.persistentModelID == collectionDraftParentID }) {
            collection = existing
        } else {
            collection = SnippetCollection(name: trimmed, colorHex: colorHex, colorHexDark: finalColorHexDark, iconName: iconName)
            modelContext.insert(collection)
        }

        if isSubcollectionDraft, let parentID = collectionDraftParentID, let newParent = collections.first(where: { $0.persistentModelID == parentID }) {
            collection.parent = newParent
        } else {
            collection.parent = nil
        }
        collection.colorHex = colorHex
        collection.colorHexDark = finalColorHexDark
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
        
        if editingCollection == nil {
            selectedCollectionID = collection.persistentModelID
            sidebarSelectionContext = .collection(collection.persistentModelID)
            isLibrarySectionExpanded = true
            expandedCollections.insert(collection.persistentModelID)
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

    private func delete(_ collection: SnippetCollection, permanent: Bool = false) {
        if !permanent && !suppressCollectionDeleteWarning {
            collectionToDelete = collection
            collectionToDeletePermanent = permanent
            return
        }
        performDelete(collection, permanent: permanent)
    }

    private func deleteCollectionContentsRecursively(_ collection: SnippetCollection, permanent: Bool) {
        for snippet in collection.snippets {
            self.performDeleteSnippet(snippet)
        }
        for child in collection.children {
            deleteCollectionContentsRecursively(child, permanent: permanent)
            self.performDelete(child, permanent: permanent)
        }
    }

    private func performDelete(_ collection: SnippetCollection, permanent: Bool) {
        if permanent {
            for snippet in snippets {
                snippet.collections.removeAll(where: { $0.persistentModelID == collection.persistentModelID })
            }
            if selectedCollectionID == collection.persistentModelID {
                selectedCollectionID = nil
            }
            if sidebarSelectionContext == .collection(collection.persistentModelID)
                || sidebarSelectionContext == .favoriteCollection(collection.persistentModelID) {
                sidebarSelectionContext = .allSnippets
            }
            modelContext.delete(collection)
        } else {
            collection.deletedAt = .now
            collection.updatedAt = .now
            lastDeletedItem = .collection(collection.persistentModelID)
            if selectedCollectionID == collection.persistentModelID {
                selectedCollectionID = nil
            }
            if sidebarSelectionContext == .collection(collection.persistentModelID)
                || sidebarSelectionContext == .favoriteCollection(collection.persistentModelID) {
                sidebarSelectionContext = .allSnippets
            }
        }
        try? modelContext.save()
        
        if !permanent {
            undoToastMessage = "Collection moved to Trash."
            withAnimation { showUndoToast = true }
            hideToastAfterDelay()
        }
    }

    private func hideToastAfterDelay() {
        toastHideTask?.cancel()
        toastHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showUndoToast = false }
        }
    }

    private func restore(_ collection: SnippetCollection) {
        collection.deletedAt = nil
        collection.updatedAt = .now
        try? modelContext.save()
    }

    private func moveSnippetToLibrary(_ snippet: Snippet) {
        let currentCollections = snippet.collections
        for collection in currentCollections {
            collection.snippets.removeAll(where: { $0.persistentModelID == snippet.persistentModelID })
            collection.updatedAt = .now
        }
        snippet.collections.removeAll()
        snippet.updatedAt = .now
        try? modelContext.save()
    }

    private func moveSnippet(_ snippet: Snippet, to collection: SnippetCollection) {
        let currentCollections = snippet.collections
        for other in currentCollections where other.persistentModelID != collection.persistentModelID {
            other.snippets.removeAll(where: { $0.persistentModelID == snippet.persistentModelID })
            other.updatedAt = .now
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

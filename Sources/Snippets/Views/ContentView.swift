import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(AppIntentNavigator.self) private var navigator

    @Query(filter: #Predicate<Snippet> { $0.deletedAt == nil }, sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var snippets: [Snippet]
    @Query(filter: #Predicate<Snippet> { $0.deletedAt != nil }, sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
    private var trashedSnippets: [Snippet]
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
    @State private var showUncategorizedOnly: Bool = true
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
    /// Everything soft-deleted by the most recent delete action, so Undo can
    /// bring back the entire batch (snippets and collections alike).
    @State private var lastDeletion: [DeletedItem] = []

    /// Captures where an item lived before the most recent move, so Undo can
    /// put the whole batch back.
    enum MoveRecord {
        case snippet(id: PersistentIdentifier, previousCollectionIDs: [PersistentIdentifier])
        case collection(id: PersistentIdentifier, previousParentID: PersistentIdentifier?)
    }
    @State private var lastMove: [MoveRecord] = []

    /// Which kind of action the toast's Undo button (and ⌘Z) should reverse.
    private enum UndoKind { case deletion, move }
    @State private var lastUndoKind: UndoKind? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var snippetToDelete: Snippet?
    @State private var pendingSnippetDeleteConfirm: (() -> Void)?
    @State private var collectionToDelete: SnippetCollection?
    @State private var collectionToDeletePermanent: Bool = false

    private struct PendingBulkDelete {
        let snippets: [Snippet]
        let collections: [SnippetCollection]
        let askCollectionBehavior: Bool
        let deleteCollectionContents: Bool
        let onConfirmed: () -> Void
    }
    @State private var pendingBulkDelete: PendingBulkDelete?

    private struct Toast {
        let message: String
        let showsUndo: Bool
    }
    @State private var activeToast: Toast?
    @State private var toastHideTask: Task<Void, Never>? = nil

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

    /// Memoized collection indexes. Plain (non-observed) class on purpose:
    /// refreshing it during body evaluation must not invalidate the view, and
    /// the signature check keeps it consistent with the `collections` query.
    private final class CollectionIndexCache {
        var signature: Int? = nil
        var lookup: [PersistentIdentifier: SnippetCollection] = [:]
        var descendantIDs: [PersistentIdentifier: Set<PersistentIdentifier>] = [:]
    }
    @State private var collectionIndexCache = CollectionIndexCache()

    /// Hash of the collection graph's structure (membership + parent links) —
    /// the only inputs `collectionLookup`/`descendantIDsByCollectionID` depend on.
    private var collectionStructureSignature: Int {
        var hasher = Hasher()
        hasher.combine(collections.count)
        for collection in collections {
            hasher.combine(collection.persistentModelID)
            hasher.combine(collection.parent?.persistentModelID)
        }
        return hasher.finalize()
    }

    private func refreshCollectionIndexCacheIfNeeded() {
        let signature = collectionStructureSignature
        guard collectionIndexCache.signature != signature else { return }

        let lookup = Dictionary(uniqueKeysWithValues: collections.map { ($0.persistentModelID, $0) })
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

        collectionIndexCache.signature = signature
        collectionIndexCache.lookup = lookup
        collectionIndexCache.descendantIDs = cache
    }

    private var collectionLookup: [PersistentIdentifier: SnippetCollection] {
        refreshCollectionIndexCacheIfNeeded()
        return collectionIndexCache.lookup
    }

    private var descendantIDsByCollectionID: [PersistentIdentifier: Set<PersistentIdentifier>] {
        refreshCollectionIndexCacheIfNeeded()
        return collectionIndexCache.descendantIDs
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

    /// Case-insensitive substring match without allocating a lowercased copy
    /// of `haystack` (search runs over every snippet's full code per pass).
    private func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    private var searchResultCollections: [SnippetCollection] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return [] }

        return collections.filter { collection in
            !collection.isDeleted &&
            (!showFavoritesOnly || collection.isFavorite) &&
            matches(collection.name, needle)
        }
    }

    private var searchResultSnippets: [Snippet] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return [] }

        return searchFilteredSnippets.filter { snippet in
            matches(snippet.title, needle) ||
            matches(snippet.snippetDescription, needle) ||
            matches(snippet.code, needle) ||
            matches(snippet.language, needle) ||
            snippet.collections.contains { !$0.isDeleted && matches($0.name, needle) }
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
            // Exclude soft-deleted children: they keep their parent link while in
            // the trash, so without this they'd stay visible after deletion.
            let children = selectedCollection.children.filter { !$0.isDeleted }.sorted(by: collectionSort)
            return showFavoritesOnly ? children.filter(\.isFavorite) : children
        }
        if
            let selectedCollection,
            sidebarSelectionContext == .favoriteCollection(selectedCollection.persistentModelID)
        {
            let children = selectedCollection.children.filter { !$0.isDeleted }.sorted(by: collectionSort)
            return showFavoritesOnly ? children.filter(\.isFavorite) : children
        }

        if sidebarSelectionContext == .allSnippets {
            return showFavoritesOnly ? topLevelCollections.filter(\.isFavorite) : topLevelCollections
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
        trashedSnippets.count + collections.count(where: { $0.deletedAt != nil })
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
        // When inside a collection, only use language colors from that collection's snippets
        let sourceSnippets: [Snippet]
        if let collection = selectedCollection {
            sourceSnippets = collection.snippets.filter { $0.deletedAt == nil }
        } else {
            sourceSnippets = snippets
        }

        var colors: [Color] = []
        var seenHex = Set<String>()

        for snippet in sourceSnippets {
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
                .toolbar {
                    sidebarToolbar
                }
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
                                    showUncategorizedOnly = false
                                    if selectedCollectionID == nil {
                                        sidebarSelectionContext = .allSnippets
                                    }
                                }
                            },
                            onEditCollection: { collection in beginEditCollection(collection) },
                            onDeleteCollection: { collection in delete(collection) },
                            onEditSnippet: { snippet in editingSnippet = snippet },
                            onDelete: { snippet, onConfirmed in delete(snippet, onConfirmed: onConfirmed) },
                            onDeleteSelection: { snippets, collections, onConfirmed in
                                deleteSelection(snippets: snippets, collections: collections, onConfirmed: onConfirmed)
                            },
                            onUndoDelete: { undoLast() },
                            onMoveSnippetToLibrary: { snippet in moveSnippetToLibrary(snippet) },
                            onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },
                            onMoveSelection: { snippets, collections, target in
                                moveSelection(snippets: snippets, collections: collections, to: target)
                            },
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
                            } onOpenSnippet: { dependency in
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                    selectedSnippetID = dependency.persistentModelID
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
                            let w: CGFloat = 640
                            let h = min(max(proxy.size.height * 0.92, 660), 960)
                            SnippetEditorView(
                                mode: .create(preselectedCollectionID: newSnippetPreselectedCollectionID),
                                availableCollections: collections,
                                availableSnippets: snippets,
                                onRequestDismiss: {
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                                        isPresentingNew = false
                                    }
                                },
                                onSave: { newSnippet in
                                    modelContext.insert(newSnippet)
                                    saveOrToast(modelContext)
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
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

                    if let toast = activeToast {
                        VStack {
                            Spacer()
                            HStack(spacing: 12) {
                                Text(toast.message)
                                    .foregroundStyle(theme.text)
                                if toast.showsUndo {
                                    Button("Undo") {
                                        withAnimation {
                                            _ = undoLast()
                                            activeToast = nil
                                        }
                                    }
                                    .bold()
                                    .foregroundStyle(theme.accent)
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .background(WindowChromeConfigurator())
        .task {
            performTrashCleanup()
            debouncedSearchText = searchText
            rebuildDerivedCaches()
            // Cold launch: an intent that launched the app may have set the flag
            // before this view began observing, so onChange never fires for it.
            if navigator.pendingNewSnippet { presentNewSnippetFromIntent() }
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
        .onChange(of: selectedCollectionID) { _, _ in
            rebuildDerivedCaches()
        }
        .onChange(of: sidebarSelectionContext) { _, newValue in
            if newValue == .allSnippets {
                showUncategorizedOnly = true
            } else {
                showUncategorizedOnly = false
            }
            selectedSearchCollections.removeAll()
        }
        .onChange(of: navigator.pendingOpenSnippetUUID) { _, newValue in
            guard let uuid = newValue else { return }
            if let match = snippets.first(where: { $0.uuid == uuid }) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    searchText = ""
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                    selectedSnippetID = match.persistentModelID
                }
            }
            navigator.pendingOpenSnippetUUID = nil
        }
        .onChange(of: navigator.pendingNewSnippet) { _, isPending in
            guard isPending else { return }
            presentNewSnippetFromIntent()
        }
        .sheet(item: $editingSnippet) { snippet in
            SnippetEditorView(mode: .edit(snippet), availableCollections: collections, availableSnippets: snippets) { _ in
                saveOrToast(modelContext)
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
                        self.lastDeletion.removeAll()
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
                    lastDeletion.removeAll()
                    performDelete(collection, permanent: collectionToDeletePermanent)
                }
            }
            Button("Delete Collection & Contents", role: .destructive) {
                if let collection = collectionToDelete {
                    lastDeletion.removeAll()
                    deleteCollectionContentsRecursively(collection, permanent: collectionToDeletePermanent)
                    performDelete(collection, permanent: collectionToDeletePermanent)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("What would you like to do with this collection and its contents?")
        }
        .confirmationDialog(
            bulkDeleteTitle,
            isPresented: Binding(
                get: { pendingBulkDelete != nil },
                set: { if !$0 { pendingBulkDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pending = pendingBulkDelete {
                if pending.askCollectionBehavior {
                    Button("Delete, Keep Collection Contents", role: .destructive) {
                        performBulkDelete(
                            snippets: pending.snippets,
                            collections: pending.collections,
                            deleteContents: false,
                            onConfirmed: pending.onConfirmed
                        )
                    }
                    Button("Delete Collections & Contents", role: .destructive) {
                        performBulkDelete(
                            snippets: pending.snippets,
                            collections: pending.collections,
                            deleteContents: true,
                            onConfirmed: pending.onConfirmed
                        )
                    }
                } else {
                    Button("Delete", role: .destructive) {
                        performBulkDelete(
                            snippets: pending.snippets,
                            collections: pending.collections,
                            deleteContents: pending.deleteCollectionContents,
                            onConfirmed: pending.onConfirmed
                        )
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        } message: {
            if let pending = pendingBulkDelete {
                if pending.askCollectionBehavior {
                    Text("The selected items will be moved to the trash. Should the contents of the selected collections go to the trash as well?")
                } else {
                    Text("This will move the selected items to the trash. You can restore them within 30 days.")
                }
            }
        }
    }

    private var bulkDeleteTitle: String {
        guard let pending = pendingBulkDelete else { return "" }
        let snippetCount = pending.snippets.count
        let collectionCount = pending.collections.count
        if snippetCount > 0 && collectionCount > 0 {
            return "Delete \(snippetCount + collectionCount) selected items?"
        }
        if collectionCount > 0 {
            return collectionCount == 1 ? "Delete this collection?" : "Delete \(collectionCount) collections?"
        }
        return snippetCount == 1 ? "Delete this snippet?" : "Delete \(snippetCount) snippets?"
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

    /// Presents the blank new-snippet editor in response to `NewSnippetIntent`,
    /// clearing any open detail and the pending flag.
    private func presentNewSnippetFromIntent() {
        newSnippetPreselectedCollectionID = nil
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            selectedSnippetID = nil
            isPresentingNew = true
        }
        navigator.pendingNewSnippet = false
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

    // The sidebar toggle is provided by the system (NavigationSplitView), so it
    // automatically gets the native Liquid Glass toolbar treatment. Attaching
    // this to the sidebar column groups the button with the system toggle,
    // with the same native glass styling.
    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button {
                beginCreateCollection()
            } label: {
                Label("New Collection", systemImage: "folder.badge.plus")
            }
            .help("New Collection")
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }

    private var sidebar: some View {
        modernSidebar
    }

    // MARK: - Modern sidebar

    private var modernSidebar: some View {
        ModernSidebar(
            snippets: snippets,
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
        if !appearanceSettings.confirmSnippetDeletion {
            onConfirmed?()
            DispatchQueue.main.async {
                self.lastDeletion.removeAll()
                self.performDeleteSnippet(snippet)
            }
            return
        }

        snippetToDelete = snippet
        pendingSnippetDeleteConfirm = onConfirmed
    }

    private func deleteSelection(
        snippets: [Snippet],
        collections: [SnippetCollection],
        onConfirmed: @escaping () -> Void
    ) {
        switch BulkDeleteConfirmation.decide(
            snippetCount: snippets.count,
            collectionCount: collections.count,
            confirmSnippetDeletion: appearanceSettings.confirmSnippetDeletion,
            collectionDeletionBehavior: appearanceSettings.collectionDeletionBehavior
        ) {
        case .deleteImmediately(let deleteContents):
            performBulkDelete(snippets: snippets, collections: collections, deleteContents: deleteContents, onConfirmed: onConfirmed)
        case .confirmOnce(let deleteContents):
            pendingBulkDelete = PendingBulkDelete(
                snippets: snippets,
                collections: collections,
                askCollectionBehavior: false,
                deleteCollectionContents: deleteContents,
                onConfirmed: onConfirmed
            )
        case .askCollectionBehavior:
            pendingBulkDelete = PendingBulkDelete(
                snippets: snippets,
                collections: collections,
                askCollectionBehavior: true,
                deleteCollectionContents: false,
                onConfirmed: onConfirmed
            )
        }
    }

    private func performBulkDelete(
        snippets: [Snippet],
        collections: [SnippetCollection],
        deleteContents: Bool,
        onConfirmed: (() -> Void)?
    ) {
        // Fire the gallery's disintegration animation before the model changes,
        // matching the single-item delete flow.
        onConfirmed?()
        DispatchQueue.main.async {
            self.lastDeletion.removeAll()
            for snippet in snippets {
                self.performDeleteSnippet(snippet)
            }
            for collection in collections {
                if deleteContents {
                    self.deleteCollectionContentsRecursively(collection, permanent: false)
                }
                self.performDelete(collection, permanent: false)
            }
            let count = snippets.count + collections.count
            if count > 1 {
                self.showToast("\(count) items moved to Recently Deleted", showsUndo: true)
            }
        }
    }

    private func showToast(_ message: String, showsUndo: Bool = false) {
        withAnimation { activeToast = Toast(message: message, showsUndo: showsUndo) }
        hideToastAfterDelay()
    }

    private func saveOrToast(_ context: ModelContext) {
        do { try context.save() }
        catch { showToast("Couldn't save changes: \(error.localizedDescription)") }
    }

    private func performDeleteSnippet(_ snippet: Snippet) {
        lastDeletion.append(.snippet(snippet.persistentModelID))
        lastUndoKind = .deletion

        if selectedSnippetID == snippet.persistentModelID {
            selectedSnippetID = nil
        }
        // Soft-delete: set deletedAt so the snippet is retained in Trash for 30 days
        snippet.deletedAt = Date.now
        snippet.updatedAt = .now
        saveOrToast(modelContext)

        showToast("Snippet moved to Recently Deleted", showsUndo: true)
    }

    /// Restores everything from the most recent delete action. Returns whether
    /// anything was actually brought back.
    @discardableResult
    private func undoLastDeletion() -> Bool {
        guard !lastDeletion.isEmpty else { return false }

        var restoredAny = false
        for item in lastDeletion {
            switch item {
            case .snippet(let id):
                if let existing = trashedSnippets.first(where: { $0.persistentModelID == id }) {
                    existing.deletedAt = nil
                    existing.updatedAt = .now
                    restoredAny = true
                }
            case .collection(let id):
                if let existing = collections.first(where: { $0.persistentModelID == id }) {
                    existing.deletedAt = nil
                    existing.updatedAt = .now
                    restoredAny = true
                }
            }
        }
        if restoredAny {
            saveOrToast(modelContext)
        }
        lastDeletion.removeAll()
        lastUndoKind = nil
        return restoredAny
    }

    /// Reverses the most recent undoable action, whether it was a delete or a move.
    @discardableResult
    private func undoLast() -> Bool {
        switch lastUndoKind {
        case .deletion: return undoLastDeletion()
        case .move:     return undoLastMove()
        case nil:       return false
        }
    }

    /// Puts everything from the most recent move batch back where it was.
    @discardableResult
    private func undoLastMove() -> Bool {
        guard !lastMove.isEmpty else { return false }

        var undidAny = false
        for record in lastMove {
            switch record {
            case .snippet(let id, let previousCollectionIDs):
                guard let snippet = snippets.first(where: { $0.persistentModelID == id }) else { continue }
                let previous = collections.filter { previousCollectionIDs.contains($0.persistentModelID) }
                setSnippetCollections(snippet, to: previous)
                undidAny = true
            case .collection(let id, let previousParentID):
                guard let collection = collections.first(where: { $0.persistentModelID == id }) else { continue }
                let previousParent = previousParentID.flatMap { pid in
                    collections.first { $0.persistentModelID == pid }
                }
                setCollectionParent(collection, to: previousParent)
                undidAny = true
            }
        }
        if undidAny {
            saveOrToast(modelContext)
        }
        lastMove.removeAll()
        lastUndoKind = nil
        return undidAny
    }

    // MARK: - Trash lifecycle

    private func performTrashCleanup() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.distantPast
        do {
            try TrashLifecycle.cleanup(
                snippets: trashedSnippets,
                collections: collections.filter { $0.deletedAt != nil },
                cutoff: cutoff,
                context: modelContext
            )
        } catch {
            showToast("Couldn't save changes: \(error.localizedDescription)")
        }
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
        saveOrToast(modelContext)
        
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
            saveOrToast(modelContext)
            showToast("Copied to \u{201C}\(collection.name)\u{201D}.")
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
        if permanent {
            // Permanent deletion might still want confirmation, but we'll follow behavior or ask
            collectionToDelete = collection
            collectionToDeletePermanent = permanent
            return
        }

        switch appearanceSettings.collectionDeletionBehavior {
        case "collectionOnly":
            lastDeletion.removeAll()
            performDelete(collection, permanent: permanent)
        case "collectionAndContents":
            lastDeletion.removeAll()
            deleteCollectionContentsRecursively(collection, permanent: permanent)
            performDelete(collection, permanent: permanent)
        default:
            collectionToDelete = collection
            collectionToDeletePermanent = permanent
        }
    }

    private func deleteCollectionContentsRecursively(_ collection: SnippetCollection, permanent: Bool) {
        for snippet in collection.snippets {
            if permanent {
                if selectedSnippetID == snippet.persistentModelID {
                    selectedSnippetID = nil
                }
                TrashLifecycle.purgeSnippet(snippet, context: modelContext)
            } else {
                self.performDeleteSnippet(snippet)
            }
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
            lastDeletion.append(.collection(collection.persistentModelID))
            if selectedCollectionID == collection.persistentModelID {
                selectedCollectionID = nil
            }
            if sidebarSelectionContext == .collection(collection.persistentModelID)
                || sidebarSelectionContext == .favoriteCollection(collection.persistentModelID) {
                sidebarSelectionContext = .allSnippets
            }
        }
        saveOrToast(modelContext)

        if !permanent {
            showToast("Collection moved to Recently Deleted", showsUndo: true)
        }
    }

    private func hideToastAfterDelay() {
        toastHideTask?.cancel()
        toastHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { activeToast = nil }
        }
    }

    private func restore(_ collection: SnippetCollection) {
        collection.deletedAt = nil
        collection.updatedAt = .now
        saveOrToast(modelContext)
    }

    // MARK: - Move primitives (mutation only; no toast, save, or undo bookkeeping)

    /// Sets a snippet's membership to exactly `targets`, keeping the inverse
    /// links in sync, and returns an undo record of its prior membership.
    @discardableResult
    private func setSnippetCollections(_ snippet: Snippet, to targets: [SnippetCollection]) -> MoveRecord {
        let previousIDs = snippet.collections.map(\.persistentModelID)
        let targetIDs = Set(targets.map(\.persistentModelID))
        for current in snippet.collections where !targetIDs.contains(current.persistentModelID) {
            current.snippets.removeAll { $0.persistentModelID == snippet.persistentModelID }
            current.updatedAt = .now
        }
        snippet.collections = targets
        for target in targets where !target.snippets.contains(where: { $0.persistentModelID == snippet.persistentModelID }) {
            target.snippets.append(snippet)
            target.updatedAt = .now
        }
        snippet.updatedAt = .now
        return .snippet(id: snippet.persistentModelID, previousCollectionIDs: previousIDs)
    }

    /// Reparents a collection and returns an undo record of its prior parent.
    @discardableResult
    private func setCollectionParent(_ collection: SnippetCollection, to parent: SnippetCollection?) -> MoveRecord {
        let previousParentID = collection.parent?.persistentModelID
        collection.parent = parent
        collection.updatedAt = .now
        parent?.updatedAt = .now
        return .collection(id: collection.persistentModelID, previousParentID: previousParentID)
    }

    /// True when `collection` can legally become a child of `target` (no cycle).
    private func canMoveCollection(_ collection: SnippetCollection, to target: SnippetCollection) -> Bool {
        collection.persistentModelID != target.persistentModelID
            && !collection.allDescendantIDs.contains(target.persistentModelID)
    }

    // MARK: - Move actions (single item)

    private func moveSnippetToLibrary(_ snippet: Snippet) {
        lastMove = [setSnippetCollections(snippet, to: [])]
        lastUndoKind = .move
        saveOrToast(modelContext)
        showToast("Moved to Library", showsUndo: true)
    }

    private func moveSnippet(_ snippet: Snippet, to collection: SnippetCollection) {
        lastMove = [setSnippetCollections(snippet, to: [collection])]
        lastUndoKind = .move
        saveOrToast(modelContext)
        showToast("Moved to \u{201C}\(collection.name)\u{201D}", showsUndo: true)
    }

    // MARK: - Move action (bulk selection)

    /// Moves a whole selection to `target` (nil = Library) as one undoable batch,
    /// showing a single toast covering all of them.
    private func moveSelection(
        snippets movedSnippets: [Snippet],
        collections movedCollections: [SnippetCollection],
        to target: SnippetCollection?
    ) {
        var records: [MoveRecord] = []
        for snippet in movedSnippets {
            records.append(setSnippetCollections(snippet, to: target.map { [$0] } ?? []))
        }
        for collection in movedCollections {
            if let target {
                guard canMoveCollection(collection, to: target) else { continue }
            }
            records.append(setCollectionParent(collection, to: target))
        }
        guard !records.isEmpty else { return }

        lastMove = records
        lastUndoKind = .move
        saveOrToast(modelContext)

        let destination = target.map { "\u{201C}\($0.name)\u{201D}" } ?? "Library"
        if records.count == 1 {
            showToast("Moved to \(destination)", showsUndo: true)
        } else {
            showToast("\(records.count) items moved to \(destination)", showsUndo: true)
        }
    }
}

/// Hard-delete operations shared by the Trash cleanup and permanent collection
/// delete flows. Context-injected so the logic is testable outside the view.
@MainActor
enum TrashLifecycle {
    /// Hard-deletes a snippet: removes media files from disk, then deletes the model.
    static func purgeSnippet(_ snippet: Snippet, context: ModelContext) {
        for media in snippet.mediaItems {
            MediaManager.deleteFile(for: media)
        }
        context.delete(snippet)
    }

    /// Hard-deletes soft-deleted snippets and collections whose `deletedAt` is
    /// before `cutoff`. Live snippets belonging to an expired collection are
    /// kept; only their membership in the purged collection is removed.
    static func cleanup(
        snippets: [Snippet],
        collections: [SnippetCollection],
        cutoff: Date,
        context: ModelContext
    ) throws {
        for snippet in snippets {
            if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
                purgeSnippet(snippet, context: context)
            }
        }
        for collection in collections {
            if let deletedAt = collection.deletedAt, deletedAt < cutoff {
                for member in collection.snippets {
                    member.collections.removeAll { $0.persistentModelID == collection.persistentModelID }
                }
                context.delete(collection)
            }
        }
        try context.save()
    }
}


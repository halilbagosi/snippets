import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

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
    @State private var collectionDraftColorDark: Color? = nil
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
    enum DeletedItem {
        case snippet(PersistentIdentifier)
        case collection(PersistentIdentifier)
    }
    @State private var lastDeletedItem: DeletedItem? = nil
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage("suppressCollectionDeleteWarning") private var suppressCollectionDeleteWarning = false
    @AppStorage("suppressSnippetDeleteWarning") private var suppressSnippetDeleteWarning = false


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
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var baseFilteredSnippets: [Snippet] {
        snippets.filter { snippet in
            if !selectedLanguages.isEmpty, let lang = SupportedLanguage(rawValue: snippet.language), !selectedLanguages.contains(lang) { return false }

            let belongsDirectlyToCollection = { (colID: PersistentIdentifier) -> Bool in
                snippet.collections.contains(where: { $0.persistentModelID == colID })
            }

            let belongsToCollection = { (colID: PersistentIdentifier) -> Bool in
                if let collection = collections.first(where: { $0.persistentModelID == colID }) {
                    let allowedIDs = collection.allDescendantIDs
                    return snippet.collections.contains(where: { allowedIDs.contains($0.persistentModelID) })
                }
                return false
            }

            if let selectedCollectionID {
                if !belongsDirectlyToCollection(selectedCollectionID) { return false }
            }

            if !selectedSearchCollections.isEmpty {
                if !selectedSearchCollections.contains(where: { belongsToCollection($0) }) { return false }
            }

            return true
        }
    }

    private var searchFilteredSnippets: [Snippet] {
        snippets.filter { snippet in
            if !selectedLanguages.isEmpty, let lang = SupportedLanguage(rawValue: snippet.language), !selectedLanguages.contains(lang) { return false }

            guard !selectedSearchCollections.isEmpty else { return true }
            return selectedSearchCollections.contains { collectionID in
                guard let collection = collections.first(where: { $0.persistentModelID == collectionID }) else { return false }
                let allowedIDs = collection.allDescendantIDs
                return snippet.collections.contains { allowedIDs.contains($0.persistentModelID) }
            }
        }
    }

    private var searchResultCollections: [SnippetCollection] {
        let needle = trimmedSearchText.lowercased()
        guard !needle.isEmpty else { return [] }

        return collections.filter { collection in
            !collection.isDeleted && collection.name.lowercased().contains(needle)
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
            return selectedCollection.children.sorted(by: collectionSort)
        }

        guard selectedCollectionID == nil, sidebarSelectionContext != .trash else { return [] }
        return topLevelCollections
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

    private var trashedItemCount: Int {
        allSnippets.filter { $0.deletedAt != nil }.count + collections.filter { $0.deletedAt != nil }.count
    }

    private var selectedSnippet: Snippet? {
        guard let id = selectedSnippetID else { return nil }
        return snippets.first(where: { $0.persistentModelID == id })
    }

    private var selectedCollection: SnippetCollection? {
        guard let id = selectedCollectionID else { return nil }
        return collections.first(where: { $0.persistentModelID == id })
    }

    private func collectionSort(_ lhs: SnippetCollection, _ rhs: SnippetCollection) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
                        DotGridBackground(gradientPalette: backgroundPalette, lightModeStrength: 0.78)
                            .ignoresSafeArea()
                    }

                    VStack(spacing: 0) {
                        SnippetGalleryView(
                            snippets: gallerySnippets,
                            searchResultCollections: searchResultCollections,
                            searchResultSnippets: searchResultSnippets,
                            searchQuery: trimmedSearchText,
                            searchText: $searchText,
                            selectedLanguages: $selectedLanguages,
                            selectedSearchCollections: $selectedSearchCollections,
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
                            onNew: { isPresentingNew = true },
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
                            onDelete: { snippet in delete(snippet) },
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
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.88), value: selectedSnippetID)
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
            trashedItemCount: trashedItemCount,
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
        LegacySidebar(
            snippets: snippets,
            collections: collections,
            frequentlyUsedSnippets: frequentlyUsedSnippets,
            availableLanguages: availableLanguages,
            sidebarFilteredLanguages: sidebarFilteredLanguages,
            trashedItemCount: trashedItemCount,
            backgroundPalette: backgroundPalette,
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

    private func delete(_ snippet: Snippet) {
        if suppressSnippetDeleteWarning {
            performDeleteSnippet(snippet)
            return
        }

        #if canImport(AppKit)
        let alert = NSAlert()
        alert.messageText = "Delete this snippet?"
        alert.informativeText = "This will move \"\(snippet.title.isEmpty ? "Untitled" : snippet.title)\" to the trash. You can restore it within 30 days."
        alert.alertStyle = .warning

        _ = alert.addButton(withTitle: "Delete Snippet")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Do not ask again"

        let handler = { @MainActor (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn {
                if alert.suppressionButton?.state == .on {
                    self.suppressSnippetDeleteWarning = true
                }
                self.performDeleteSnippet(snippet)
            }
        }

        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
        #else
        performDeleteSnippet(snippet)
        #endif
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
            #if canImport(AppKit)
            let alert = NSAlert()
            alert.messageText = "Delete Collection?"
            alert.informativeText = "What would you like to do with this collection and its contents?"
            alert.alertStyle = .warning
            
            _ = alert.addButton(withTitle: "Delete Collection Only")
            let deleteWithContentsButton = alert.addButton(withTitle: "Delete Collection & Contents")
            deleteWithContentsButton.hasDestructiveAction = true
            alert.addButton(withTitle: "Cancel")
            
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Do not ask again"
            
            let handler = { @MainActor (response: NSApplication.ModalResponse) in
                if response == .alertFirstButtonReturn {
                    if alert.suppressionButton?.state == .on {
                        self.suppressCollectionDeleteWarning = true
                    }
                    self.performDelete(collection, permanent: permanent)
                } else if response == .alertSecondButtonReturn {
                    if alert.suppressionButton?.state == .on {
                        self.suppressCollectionDeleteWarning = true
                    }
                    self.deleteCollectionContentsRecursively(collection, permanent: permanent)
                    self.performDelete(collection, permanent: permanent)
                }
            }

            if let window = NSApplication.shared.windows.first(where: { $0.isKeyWindow }) {
                alert.beginSheetModal(for: window) { sheetResponse in
                    handler(sheetResponse)
                }
                return
            } else {
                let response = alert.runModal()
                handler(response)
                return
            }
            #endif
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
            if sidebarSelectionContext == .collection(collection.persistentModelID) {
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
            if sidebarSelectionContext == .collection(collection.persistentModelID) {
                sidebarSelectionContext = .allSnippets
            }
        }
        try? modelContext.save()
    }

    private func restore(_ collection: SnippetCollection) {
        collection.deletedAt = nil
        collection.updatedAt = .now
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

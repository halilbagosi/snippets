import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct SnippetGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppearanceSettings.self) private var appearanceSettings

    let snippets: [Snippet]
    let searchResultCollections: [SnippetCollection]
    let searchResultSnippets: [Snippet]
    let searchQuery: String
    @Binding var searchText: String
    @Binding var showFavoritesOnly: Bool
    @Binding var selectedLanguages: Set<SupportedLanguage>
    @Binding var selectedSearchCollections: Set<PersistentIdentifier>
    @Binding var showUncategorizedOnly: Bool
    let availableLanguages: [SupportedLanguage]
    let availableCollections: [SnippetCollection]
    let subcollections: [SnippetCollection]
    let onSelect: (Snippet) -> Void
    var onSelectCollection: ((SnippetCollection) -> Void)? = nil
    var onCreateCollection: (() -> Void)? = nil
    var onNew: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var onClearSelection: (() -> Void)? = nil
    var onEditCollection: ((SnippetCollection) -> Void)? = nil
    var onDeleteCollection: ((SnippetCollection) -> Void)? = nil
    var onEditSnippet: ((Snippet) -> Void)? = nil
    var onDelete: ((Snippet, @escaping () -> Void) -> Void)? = nil
    /// Bulk delete of the current selection: asks for confirmation once and
    /// deletes everything, instead of prompting per item.
    var onDeleteSelection: (([Snippet], [SnippetCollection], @escaping () -> Void) -> Void)? = nil
    /// Restores the last deletion batch; returns whether anything came back.
    var onUndoDelete: (() -> Bool)? = nil
    var onMoveSnippetToLibrary: ((Snippet) -> Void)? = nil
    var onMoveSnippetToCollection: ((Snippet, SnippetCollection) -> Void)? = nil
    /// Bulk move of the current selection to a target (nil = Library), handled
    /// as one undoable batch with a single toast.
    var onMoveSelection: (([Snippet], [SnippetCollection], SnippetCollection?) -> Void)? = nil
    var onCopySnippetToCollection: ((Snippet, SnippetCollection) -> Void)? = nil
    var isTrashMode: Bool = false
    var onRestore: ((Snippet) -> Void)? = nil
    var onPermanentDelete: ((Snippet, @escaping () -> Void) -> Void)? = nil
    var onRestoreCollection: ((SnippetCollection) -> Void)? = nil
    var onPermanentDeleteCollection: ((SnippetCollection) -> Void)? = nil

    @FocusState private var searchFocused: Bool
    @State private var viewModel = SnippetGalleryViewModel()
    @State private var hasAnimatedCards = false
    @State private var isCollectionsSectionExpanded = true
    @State private var isSnippetsSectionExpanded = true
    @State private var expandedLanguageSections: Set<String> = []
    @State private var fabHovered = false
    @State private var pressedSnippetID: PersistentIdentifier? = nil
    /// Stack entries whose connected snippets are currently fanned out.
    @State private var expandedStacks: Set<PersistentIdentifier> = []
    @State private var pressedResetTask: Task<Void, Never>? = nil
    @State private var showMoveSheet: Bool = false
    @State private var collectionFilterSearchText = ""
#if canImport(AppKit)
    @State private var keyEventMonitor: Any? = nil
#endif

    // Narrower columns keep snippet cards closer to square so the attachment
    // preview reads well for both landscape and portrait media. Collection
    // cards stay a touch wider, matching the ratio they had before.
    private let columns = [GridItem(.adaptive(minimum: 340, maximum: 440), spacing: 20)]
    private let subcollectionColumns = [GridItem(.adaptive(minimum: 360, maximum: 470), spacing: 16)]
    /// Deleted cards fade out with the same opacity transition used when
    /// collapsing gallery sections.
    private var cardRemovalAnimation: Animation {
        .interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)
    }
    private var sectionCollapseAnimation: Animation {
        .interactiveSpring(response: 0.34, dampingFraction: 0.96, blendDuration: 0.08)
    }
    /// Changes whenever the Snippets strip (or the empty state that replaces it)
    /// appears or disappears, so the section itself fades in/out with the same
    /// opacity transition the cards use — e.g. when the last snippet is deleted.
    private var snippetsSectionVisibilityKey: Int {
        var hasher = Hasher()
        hasher.combine(hasAnyGalleryContent)
        hasher.combine(snippets.isEmpty)
        hasher.combine(searchResultSnippets.isEmpty)
        return hasher.finalize()
    }
    private var hasVisibleSubcollections: Bool {
        searchQuery.isEmpty && !subcollections.isEmpty && selectedLanguages.isEmpty && selectedSearchCollections.isEmpty
    }
    private var hasAnyGalleryContent: Bool {
        hasAnyResults || hasVisibleSubcollections || (!subcollections.isEmpty && !selectedLanguages.isEmpty)
    }
    private var hasAnyResults: Bool {
        viewModel.hasAnyResults(
            snippets: snippets,
            searchResultCollections: searchResultCollections,
            searchResultSnippets: searchResultSnippets,
            searchQuery: searchQuery
        )
    }
    private var displaySnippets: [Snippet] {
        viewModel.displaySnippets(
            snippets: snippets,
            searchResultSnippets: searchResultSnippets,
            searchQuery: searchQuery
        )
    }
    private var collectionFilterQuery: String {
        collectionFilterSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var collectionFilterMatches: [SnippetCollection] {
        guard !collectionFilterQuery.isEmpty else { return availableCollections }
        return availableCollections.filter { collection in
            collection.name.range(of: collectionFilterQuery, options: .caseInsensitive) != nil
        }
    }
    private var collectionFilterSectionCount: Int {
        collectionFilterMatches.isEmpty ? 0 : 1
    }
    private var collectionFilterPopoverWidth: CGFloat {
        380
    }
    private var collectionFilterMaxListHeight: CGFloat {
        360
    }
    private var isFilterSelected: Bool {
        !selectedSearchCollections.isEmpty || showUncategorizedOnly
    }
    private var collectionFilterPopoverHeight: CGFloat {
        // Obsolete, using fixedSize dynamically in the view instead
        0
    }
    private var collectionFilterListHeight: CGFloat {
        let hasSystemFilters = collectionFilterQuery.isEmpty
        let matchesCount = collectionFilterMatches.count

        if !hasSystemFilters && matchesCount == 0 {
            return 77 // 68 (No matches minHeight) + 9 (bottom padding)
        }

        var contentHeight: CGFloat = 0
        
        if hasSystemFilters {
            contentHeight += 59 // systemFiltersSection height
        }
        
        if matchesCount > 0 {
            if hasSystemFilters {
                contentHeight += 8 // parent VStack spacing
            }
            contentHeight += 22 + CGFloat(matchesCount) * 37 // collectionFilterSection height
        }
        
        contentHeight += 9 // bottom padding
        
        return min(contentHeight, collectionFilterMaxListHeight)
    }
    private var backButtonTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        )
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 22) {
                            if !hasAnyGalleryContent {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 36)
                                    .transition(.opacity)
                            } else if !searchQuery.isEmpty {
                                if !searchResultCollections.isEmpty && selectedLanguages.isEmpty {
                                    GallerySection(
                                        title: "Collections",
                                        count: searchResultCollections.count,
                                        icon: "folder",
                                        tint: theme.accent,
                                        actionIcon: "plus",
                                        action: onCreateCollection,
                                        isExpanded: $isCollectionsSectionExpanded,
                                        animation: sectionCollapseAnimation
                                    ) {
                                        subcollectionGrid(searchResultCollections)
                                    }
                                }
                                if !searchResultSnippets.isEmpty {
                                    if !selectedLanguages.isEmpty {
                                        languageGroupedSnippets(viewModel.ordered(searchResultSnippets))
                                    } else {
                                        GallerySection(
                                            title: "Snippets",
                                            count: searchResultSnippets.count,
                                            icon: "square.stack.3d.up",
                                            tint: theme.textMuted,
                                            isExpanded: $isSnippetsSectionExpanded,
                                            animation: sectionCollapseAnimation
                                        ) {
                                            snippetGrid(viewModel.ordered(searchResultSnippets))
                                        }
                                        .transition(.opacity)
                                    }
                                }
                            } else {
                                if hasVisibleSubcollections {
                                    GallerySection(
                                        title: "Collections",
                                        count: subcollections.count,
                                        icon: "folder",
                                        tint: theme.accent,
                                        actionIcon: "plus",
                                        action: onCreateCollection,
                                        isExpanded: $isCollectionsSectionExpanded,
                                        animation: sectionCollapseAnimation
                                    ) {
                                        subcollectionGrid(subcollections)
                                    }
                                }
                                if !selectedLanguages.isEmpty {
                                    languageGroupedSnippets(viewModel.ordered(snippets))
                                } else if !snippets.isEmpty {
                                    if !selectedSearchCollections.isEmpty {
                                        snippetGrid(viewModel.ordered(snippets))
                                    } else {
                                        GallerySection(
                                            title: "Snippets",
                                            count: snippets.count,
                                            icon: "square.stack.3d.up",
                                            tint: theme.textMuted,
                                            isExpanded: $isSnippetsSectionExpanded,
                                            animation: sectionCollapseAnimation
                                        ) {
                                            snippetGrid(viewModel.ordered(snippets))
                                        }
                                        .transition(.opacity)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .padding(.bottom, isTrashMode ? 24 : 112)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(cardRemovalAnimation, value: snippetsSectionVisibilityKey)
                }
            }
            .scrollIndicators(.never)
            // The bar lives in the top safe-area inset: it is laid out below
            // the window toolbar automatically (and at the window top in full
            // screen), content scrolls beneath it, and its glass background
            // extends up through the transparent toolbar via ignoresSafeArea.
            .safeAreaInset(edge: .top, spacing: 0) {
                topBar
            }

            fab
                .padding(.trailing, 32)
                .padding(.bottom, 24)

            if showMoveSheet {
                moveToCollectionOverlay
                    .zIndex(9)
            }
        }
        .onAppear {
            hasAnimatedCards = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                hasAnimatedCards = true
            }
            #if canImport(AppKit)
            guard keyEventMonitor == nil else { return }
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let chars = event.charactersIgnoringModifiers ?? ""
                if event.keyCode == 53, showMoveSheet {
                    showMoveSheet = false
                    return nil
                }
            if event.modifierFlags.contains(.command), chars.lowercased() == "z" {
                if onUndoDelete?() == true {
                    return nil
                }
                return event
            }
                if event.modifierFlags.contains(.command), chars.lowercased() == "f", !showMoveSheet {
                    searchFocused = true
                    return nil
                }
                if event.keyCode == 53 {
                    if searchFocused {
                        searchFocused = false
                        return nil
                    }
                    if !searchText.isEmpty {
                        searchText = ""
                        return nil
                    }
                }
                return event
            }
            #endif
        }

        .onChange(of: searchQuery) { _, newValue in
            guard !newValue.isEmpty else { return }
            isCollectionsSectionExpanded = true
            isSnippetsSectionExpanded = true
        }
        .onDisappear {
            #if canImport(AppKit)
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
            #endif
            pressedResetTask?.cancel()
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: showMoveSheet)
    }

    private var selectedSnippetsForMove: [Snippet] {
        viewModel.selectedSnippets(from: snippets)
    }

    private var selectedCollectionsForMove: [SnippetCollection] {
        viewModel.selectedCollections(from: subcollections)
    }

    private func moveTargetCollections(
        selectedSnippets: [Snippet],
        selectedCollections: [SnippetCollection]
    ) -> [SnippetCollection] {
        // Excluded targets: the selected collections themselves, any collection
        // already containing a selected snippet, and the current parent of any
        // selected collection. Collected once so the filter below is O(1) per target.
        var excludedIDs = Set(selectedCollections.map(\.persistentModelID))
        for snippet in selectedSnippets {
            for collection in snippet.collections {
                excludedIDs.insert(collection.persistentModelID)
            }
        }
        for collection in selectedCollections {
            if let parentID = collection.parent?.persistentModelID {
                excludedIDs.insert(parentID)
            }
        }

        return availableCollections.filter { !excludedIDs.contains($0.persistentModelID) }
    }

    private func moveShowsLibraryOption(
        selectedSnippets: [Snippet],
        selectedCollections: [SnippetCollection]
    ) -> Bool {
        let allSnippetsInCollections = selectedSnippets.allSatisfy { !$0.collections.isEmpty }
        let allCollectionsAreSubcollections = selectedCollections.allSatisfy { $0.parent != nil }
        let hasAnySelection = !selectedSnippets.isEmpty || !selectedCollections.isEmpty
        return hasAnySelection && allSnippetsInCollections && allCollectionsAreSubcollections
    }

    @ViewBuilder
    private var moveToCollectionOverlay: some View {
        Color.black
            .opacity(colorScheme == .dark ? 0.34 : 0.22)
            .ignoresSafeArea()
            .onTapGesture { showMoveSheet = false }
            .transition(.opacity)

        GeometryReader { proxy in
            let cardWidth = min(max(proxy.size.width * 0.5, 380), 460)
            let cardHeight = min(max(proxy.size.height * 0.6, 420), 640)
            let selectedSnippets = selectedSnippetsForMove
            let selectedCollections = selectedCollectionsForMove

            MoveToCollectionCard(
                collections: moveTargetCollections(
                    selectedSnippets: selectedSnippets,
                    selectedCollections: selectedCollections
                ),
                showLibraryOption: moveShowsLibraryOption(
                    selectedSnippets: selectedSnippets,
                    selectedCollections: selectedCollections
                ),
                itemCount: selectedSnippets.count + selectedCollections.count,
                onMove: { collection in
                    onMoveSelection?(selectedSnippets, selectedCollections, collection)
                    withAnimation {
                        viewModel.clearSelectionAndExitSelectMode()
                    }
                    showMoveSheet = false
                },
                onCancel: { showMoveSheet = false }
            )
            .frame(width: cardWidth, height: cardHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(
                .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
                    removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
                )
            )
        }
    }

    private var theme: Theme {
        let _ = appearanceSettings.themeColorHex
        return Theme.current(colorScheme)
    }

    /// Deletion just removes the card from the grid; the grid's identity-keyed
    /// animation plays the card's `.transition(.opacity)`, matching the fade
    /// used when a section is collapsed.
    private func requestDelete(_ snippet: Snippet) {
        onDelete?(snippet) {}
    }

    private func requestPermanentDelete(_ snippet: Snippet) {
        onPermanentDelete?(snippet) {}
    }

    private func subcollectionGrid(_ source: [SnippetCollection]) -> some View {
        let ordered = viewModel.ordered(source)
        return DSGlassContainer(spacing: 18) {
            LazyVGrid(columns: subcollectionColumns, spacing: 14) {
                ForEach(Array(ordered.enumerated()), id: \.element.persistentModelID) { index, collection in
                    ZStack {
                        SnippetCollectionCard(
                            collection: collection,
                            isSelected: viewModel.selectedForAction.contains(collection.persistentModelID),
                            inTrashView: isTrashMode,
                            isSelectionMode: viewModel.isSelectMode,
                            onOpen: {
                                if viewModel.isSelectMode {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        viewModel.toggleSelection(for: collection)
                                    }
                                } else {
                                    onSelectCollection?(collection)
                                }
                            },
                            onEdit: {
                                onEditCollection?(collection)
                            },
                            onDelete: {
                                onDeleteCollection?(collection)
                            },
                            onRestore: {
                                onRestoreCollection?(collection)
                            },
                            onPermanentDelete: {
                                onPermanentDeleteCollection?(collection)
                            }
                        )

                        if viewModel.isSelectMode {
                            let isSelected = viewModel.selectedForAction.contains(collection.persistentModelID)
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 3)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? theme.accent : theme.textMuted.opacity(0.5))
                                        .font(.title2)
                                        .padding(DSToken.Spacing.sm)
                                        .background {
                                            Circle().fill(theme.surfaceElevated).padding(DSToken.Spacing.sm)
                                        }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(hasAnimatedCards ? 1 : 0)
                    .offset(y: hasAnimatedCards ? 0 : 6)
                    .transition(.opacity)
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.94)
                            .delay(min(Double(index) * 0.02, 0.12)),
                        value: hasAnimatedCards
                    )
                }
            }
            .animation(cardRemovalAnimation, value: collectionIdentityKey(for: ordered))
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
    }

    private struct StackDisplayItem {
        let snippet: Snippet
        let connectedCount: Int
        let isConnected: Bool
    }

    /// Flattens the source into display rows: connected snippets are hidden
    /// behind their entry's card (SnippetLinker.stacks) and appear as rows
    /// only while that stack is expanded. Trash stays flat.
    private func stackDisplayItems(_ source: [Snippet]) -> [StackDisplayItem] {
        guard !isTrashMode else {
            return source.map { StackDisplayItem(snippet: $0, connectedCount: 0, isConnected: false) }
        }
        var added: Set<PersistentIdentifier> = []
        var items: [StackDisplayItem] = []
        for (entry, connected) in SnippetLinker.stacks(in: source) {
            guard added.insert(entry.persistentModelID).inserted else { continue }
            items.append(StackDisplayItem(snippet: entry, connectedCount: connected.count, isConnected: false))
            guard expandedStacks.contains(entry.persistentModelID) else { continue }
            for member in connected where added.insert(member.persistentModelID).inserted {
                items.append(StackDisplayItem(snippet: member, connectedCount: 0, isConnected: true))
            }
        }
        return items
    }

    private func snippetGrid(_ source: [Snippet]) -> some View {
        let items = stackDisplayItems(source)
        return LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(items.enumerated()), id: \.element.snippet.persistentModelID) { index, item in
                snippetCell(
                    item.snippet,
                    index: index,
                    linkedCount: item.connectedCount,
                    isStackExpanded: expandedStacks.contains(item.snippet.persistentModelID),
                    onToggleStack: { toggleStack(item.snippet.persistentModelID) }
                )
                    .overlay {
                        // Revealed stack members read as part of the group via
                        // a subtle accent ring instead of shapes behind the
                        // glass card (which show through its material).
                        if item.isConnected {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1)
                                .allowsHitTesting(false)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if item.isConnected { connectedMarker }
                    }
            }
        }
        .animation(cardRemovalAnimation, value: snippetIdentityKey(for: source))
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    private func snippetCell(
        _ snippet: Snippet,
        index: Int,
        linkedCount: Int = 0,
        isStackExpanded: Bool = false,
        onToggleStack: (() -> Void)? = nil
    ) -> some View {
        ZStack {
                    SnippetCard(
                        snippet: snippet,
                        inTrashView: isTrashMode,
                        isSelectionMode: viewModel.isSelectMode,
                        onRestore: { onRestore?(snippet) },
                        onPermanentDelete: { requestPermanentDelete(snippet) },
                        linkedCount: linkedCount,
                        isStackExpanded: isStackExpanded,
                        onToggleStack: onToggleStack
                    )

                    if viewModel.isSelectMode {
                        let isSelected = viewModel.selectedForAction.contains(snippet.persistentModelID)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 3)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? theme.accent : theme.textMuted.opacity(0.5))
                                    .font(.title2)
                                    .padding(DSToken.Spacing.sm)
                                    .background {
                                        Circle().fill(theme.surfaceElevated).padding(DSToken.Spacing.sm)
                                    }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                    .scaleEffect(pressedSnippetID == snippet.persistentModelID ? 0.97 : 1.0)
                    .opacity(pressedSnippetID == snippet.persistentModelID ? 0.92 : 1.0)
                    .opacity(hasAnimatedCards ? 1 : 0)
                    .offset(y: hasAnimatedCards ? 0 : 8)
                    .transition(.opacity)
                    .zIndex(pressedSnippetID == snippet.persistentModelID ? 2 : 0)
                    .animation(
                        .spring(response: 0.34, dampingFraction: 0.92)
                            .delay(min(Double(index) * 0.02, 0.12)),
                        value: hasAnimatedCards
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: pressedSnippetID)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .contextMenu {
                        if isTrashMode {
                            Button { onRestore?(snippet) } label: {
                                Label("Put back", systemImage: "arrow.uturn.left")
                            }
                            Button(role: .destructive) { requestPermanentDelete(snippet) } label: {
                                Label("Delete permanently", systemImage: "trash")
                            }
                        } else {
                            Button { onEditSnippet?(snippet) } label: {
                                Label("Edit snippet", systemImage: "pencil")
                            }
                            Menu {
                                if !snippet.collections.isEmpty {
                                    Button { onMoveSnippetToLibrary?(snippet) } label: {
                                        Label("All snippets", systemImage: "square.grid.2x2")
                                    }
                                }
                                let targetCollections = availableCollections.filter { target in
                                    !snippet.collections.contains(where: { $0.persistentModelID == target.persistentModelID })
                                }
                                ForEach(targetCollections) { target in
                                    Button { onMoveSnippetToCollection?(snippet, target) } label: {
                                        Label(target.name, systemImage: target.displayIconName)
                                    }
                                }
                            } label: {
                                Label("Move to", systemImage: "folder")
                            }
                            Divider()
                            Button(role: .destructive) { requestDelete(snippet) } label: {
                                Label("Delete snippet", systemImage: "trash")
                            }
                        }
                    }
                    .onTapGesture {
                        if viewModel.isSelectMode {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                viewModel.toggleSelection(for: snippet)
                            }
                            return
                        }
                        
                        onSelect(snippet)
                        
                        withAnimation(.easeOut(duration: 0.11)) {
                            pressedSnippetID = snippet.persistentModelID
                        }
                        pressedResetTask?.cancel()
                        pressedResetTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            guard !Task.isCancelled else { return }
                            withAnimation(.easeOut(duration: 0.14)) {
                                pressedSnippetID = nil
                            }
                        }
                    }
    }

    private func toggleStack(_ entryID: PersistentIdentifier) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
            if expandedStacks.contains(entryID) {
                expandedStacks.remove(entryID)
            } else {
                expandedStacks.insert(entryID)
            }
        }
    }

    /// Marks a revealed stack member as belonging to the entry it was fanned
    /// out from. Top-trailing: the only card corner without content (title is
    /// top-leading; language/copy/favorite and date own the bottom row).
    private var connectedMarker: some View {
        HStack(spacing: 4) {
            Image(systemName: "link")
                .font(Mono.font(size: 9, weight: .bold))
            Text("connected")
                .font(Mono.font(size: 10, weight: .semibold))
        }
        .foregroundStyle(theme.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(theme.surfaceElevated)
                .overlay { Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1) }
        }
        .padding(10)
        .allowsHitTesting(false)
    }

    private func snippetIdentityKey(for source: [Snippet]) -> Int {
        var hasher = Hasher()
        hasher.combine(source.count)
        hasher.combine(source.first?.persistentModelID)
        hasher.combine(source.last?.persistentModelID)
        return hasher.finalize()
    }

    private func collectionIdentityKey(for source: [SnippetCollection]) -> Int {
        var hasher = Hasher()
        hasher.combine(source.count)
        hasher.combine(source.first?.persistentModelID)
        hasher.combine(source.last?.persistentModelID)
        return hasher.finalize()
    }

    @ViewBuilder
    private func languageGroupedSnippets(_ source: [Snippet]) -> some View {
        let grouped = Dictionary(grouping: source) { snippet in
            SupportedLanguage(rawValue: snippet.language) ?? .unknown
        }
        let sortedLanguages = selectedLanguages
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }
        let isFilteringByCollection = !selectedSearchCollections.isEmpty
        let collectionsByLanguage = isFilteringByCollection
            ? [:]
            : subcollectionsByLanguage(subcollections, favoritesOnly: showFavoritesOnly)

        ForEach(sortedLanguages) { language in
            let langSnippets = grouped[language] ?? []
            let langCollections = collectionsByLanguage[language] ?? []

            if !langSnippets.isEmpty || !langCollections.isEmpty {
                let visibleSnippets = langSnippets
                
                let baseAccent = Color(hex: language.accentHex) ?? theme.accent
                let accent = colorScheme == .dark 
                    ? baseAccent.saturation(3.0).brightness(0.22)
                    : baseAccent.saturation(3.0).brightness(-0.15)
                let isExpanded = Binding(
                    get: { !expandedLanguageSections.contains(language.rawValue) },
                    set: { newValue in
                        if newValue {
                            expandedLanguageSections.remove(language.rawValue)
                        } else {
                            expandedLanguageSections.insert(language.rawValue)
                        }
                    }
                )
                GallerySection(
                    title: "lang:\(language.rawValue.lowercased())",
                    count: visibleSnippets.count + langCollections.count,
                    icon: language.symbolName,
                    tint: accent,
                    isExpanded: isExpanded,
                    animation: sectionCollapseAnimation
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        if !langCollections.isEmpty {
                            subcollectionGrid(langCollections)
                                .padding(.bottom, 16)
                        }
                        if !visibleSnippets.isEmpty {
                            snippetGrid(visibleSnippets)
                        }
                    }
                }
            }
        }
    }

    private func subcollectionsByLanguage(
        _ collections: [SnippetCollection],
        favoritesOnly: Bool
    ) -> [SupportedLanguage: [SnippetCollection]] {
        var result: [SupportedLanguage: [SnippetCollection]] = [:]

        for collection in collections {
            for language in languages(in: collection, favoritesOnly: favoritesOnly) {
                result[language, default: []].append(collection)
            }
        }

        return result
    }

    private func languages(
        in collection: SnippetCollection,
        favoritesOnly: Bool
    ) -> Set<SupportedLanguage> {
        var result = Set<SupportedLanguage>()

        for snippet in collection.snippets where !snippet.isDeleted && (!favoritesOnly || snippet.isFavorite) {
            if let language = SupportedLanguage(rawValue: snippet.language) {
                result.insert(language)
            }
        }

        for child in collection.children {
            result.formUnion(languages(in: child, favoritesOnly: favoritesOnly))
        }

        return result
    }

    private var topBar: some View {
        DSGlassContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if let onBack {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.text)
                                .frame(width: 32, height: 32)
                                .liquidGlassSurface(
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                                    interactive: true,
                                    borderOpacity: colorScheme == .dark ? 0.18 : 0.36,
                                    shadowRadius: 5,
                                    shadowY: 2
                                )
                                .compositingGroup()
                                // Horizontal padding only: vertical padding would
                                // make the back button taller than the search bar,
                                // growing the row and shifting the filter tags down
                                // when a collection is open.
                                .padding(.horizontal, DSToken.Spacing.xs)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .transition(backButtonTransition)
                    }

                    searchBar
                        .frame(maxWidth: .infinity)
                    
                    HStack(spacing: 8) {
                        FilterTag(
                            label: viewModel.isSelectMode ? "done" : "select",
                            icon: viewModel.isSelectMode ? "checkmark.circle" : "checklist",
                            accent: viewModel.isSelectMode ? theme.accent : theme.textMuted,
                            isSelected: viewModel.isSelectMode
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.toggleSelectMode()
                            }
                        }

                        if viewModel.isSelectMode {
                            let isAllSelected = viewModel.selectedForAction.count == (displaySnippets.count + subcollections.count) && (!displaySnippets.isEmpty || !subcollections.isEmpty)
                            FilterTag(
                                label: isAllSelected ? "deselect all" : "select all",
                                icon: isAllSelected ? "circle.dashed" : "checkmark.circle.fill",
                                accent: theme.textMuted,
                                isSelected: isAllSelected
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    if isAllSelected {
                                        viewModel.clearSelectionAndExitSelectMode()
                                        viewModel.isSelectMode = true
                                    } else {
                                        let snippetIDs = displaySnippets.map(\.persistentModelID)
                                        let collectionIDs = subcollections.map(\.persistentModelID)
                                        let allIDs = Set(snippetIDs + collectionIDs)
                                        viewModel.selectedForAction = allIDs
                                    }
                                }
                            }
                            .transition(.opacity)

                            if isTrashMode {
                                FilterTag(
                                    label: "put back (\(viewModel.selectedForAction.count))",
                                    icon: "arrow.uturn.left",
                                    accent: theme.accent,
                                    isSelected: false
                                ) {
                                    let toRestoreSnippets = viewModel.selectedSnippets(from: displaySnippets)
                                    let toRestoreCollections = viewModel.selectedCollections(from: subcollections)
                                    for snip in toRestoreSnippets { onRestore?(snip) }
                                    for coll in toRestoreCollections { onRestoreCollection?(coll) }
                                    withAnimation {
                                        viewModel.clearSelectionAndExitSelectMode()
                                    }
                                }
                                .disabled(viewModel.selectedForAction.isEmpty)
                                .opacity(viewModel.selectedForAction.isEmpty ? 0.5 : 1.0)
                                .transition(.opacity)
                            }

                            if !isTrashMode {
                                FilterTag(
                                    label: "move (\(viewModel.selectedForAction.count))",
                                    icon: "folder",
                                    accent: theme.accent,
                                    isSelected: false
                                ) {
                                    showMoveSheet = true
                                }
                                .disabled(viewModel.selectedForAction.isEmpty)
                                .opacity(viewModel.selectedForAction.isEmpty ? 0.5 : 1.0)
                                .transition(.opacity)
                            }

                            FilterTag(
                                label: "delete (\(viewModel.selectedForAction.count))",
                                icon: "trash",
                                accent: .red,
                                isSelected: false
                            ) {
                                let toDeleteSnippets = viewModel.selectedSnippets(from: displaySnippets)
                                let toDeleteCollections = viewModel.selectedCollections(from: subcollections)
                                if isTrashMode {
                                    for snip in toDeleteSnippets {
                                        requestPermanentDelete(snip)
                                    }
                                    for coll in toDeleteCollections { onPermanentDeleteCollection?(coll) }
                                } else if let onDeleteSelection {
                                    onDeleteSelection(toDeleteSnippets, toDeleteCollections) {}
                                } else {
                                    for snip in toDeleteSnippets {
                                        requestDelete(snip)
                                    }
                                    for coll in toDeleteCollections { onDeleteCollection?(coll) }
                                }
                                withAnimation {
                                    viewModel.clearSelectionAndExitSelectMode()
                                }
                            }
                            .disabled(viewModel.selectedForAction.isEmpty)
                            .opacity(viewModel.selectedForAction.isEmpty ? 0.5 : 1.0)
                            .transition(.opacity)
                        }

                        if !viewModel.isSelectMode {
                            FilterTag(
                                label: viewModel.isOldestToNewest ? "sort:oldest" : "sort:newest",
                                icon: viewModel.isOldestToNewest ? "arrow.up" : "arrow.down",
                                accent: theme.textMuted,
                                isSelected: false
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.isOldestToNewest.toggle()
                                }
                            }
                            .transition(.opacity)

                            if !isTrashMode {
                                FilterTag(
                                    label: (selectedSearchCollections.isEmpty && !showUncategorizedOnly) ? "collections:all" : (showUncategorizedOnly ? "collections:none" : "collections:\(selectedSearchCollections.count)"),
                                    icon: "folder",
                                    accent: theme.textMuted,
                                    isSelected: !selectedSearchCollections.isEmpty || showUncategorizedOnly
                                ) {
                                    viewModel.isShowingCollectionFilter.toggle()
                                }
                                .popover(isPresented: $viewModel.isShowingCollectionFilter, arrowEdge: .bottom) {
                                    // No presentationBackground override: the system
                                    // popover already provides native Liquid Glass.
                                    collectionFilterPopover
                                }
                                .transition(.opacity)

                                FilterTag(
                                    label: "favorites",
                                    icon: showFavoritesOnly ? "star.fill" : "star",
                                    accent: Color(red: 1.0, green: 0.80, blue: 0.20),
                                    isSelected: showFavoritesOnly
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        showFavoritesOnly.toggle()
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: onBack != nil)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isSelectMode)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isOldestToNewest)
                if !availableLanguages.isEmpty {
                    filterBar
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .liquidGlassBar(divider: .bottom)
    }

    private var collectionFilterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            collectionFilterSearchField
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if collectionFilterQuery.isEmpty {
                        systemFiltersSection
                    }
                    if !collectionFilterMatches.isEmpty {
                        collectionFilterSection(
                            "Collections",
                            collections: collectionFilterMatches
                        )
                    }

                    if collectionFilterMatches.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                            Text(collectionFilterQuery.isEmpty ? "No collections" : "No matches")
                        }
                        .font(Sans.font(size: 13, weight: .medium))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 68)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
            .frame(height: collectionFilterListHeight)

            if isFilterSelected {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.34))
                        .frame(height: 1)

                    Button {
                        guard isFilterSelected else { return }
                        if let onClearSelection = onClearSelection {
                            onClearSelection()
                        } else {
                            selectedSearchCollections.removeAll()
                            showUncategorizedOnly = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle")
                            Text("Clear Selection")
                            Spacer()
                            Text("\(selectedSearchCollections.count + (showUncategorizedOnly ? 1 : 0))")
                                .monospacedDigit()
                        }
                        .font(Sans.font(size: 13, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 14)
                        .frame(height: 53)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: collectionFilterPopoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isFilterSelected)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: collectionFilterMatches.count)
        .onDisappear {
            collectionFilterSearchText = ""
        }
    }

    private var collectionFilterSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(Sans.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .frame(width: 16)

            TextField("Filter", text: $collectionFilterSearchText)
                .textFieldStyle(.plain)
                .font(Sans.font(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)

            if !collectionFilterSearchText.isEmpty {
                Button {
                    collectionFilterSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Sans.font(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 8, style: .continuous),
            interactive: true,
            borderOpacity: colorScheme == .dark ? 0.12 : 0.24,
            shadowRadius: 2,
            shadowY: 1
        )
    }

    @ViewBuilder
    private var systemFiltersSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("System")
                .font(Sans.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 3)

            Button {
                showUncategorizedOnly.toggle()
                if showUncategorizedOnly {
                    selectedSearchCollections.removeAll()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark")
                        .font(Sans.font(size: 13, weight: .semibold))
                        .foregroundStyle(showUncategorizedOnly ? theme.text : .clear)
                        .frame(width: 18)

                    CollectionIconView(
                        iconName: "tray",
                        color: theme.textMuted,
                        size: 14,
                        isSelected: false
                    )
                    .frame(width: 22, height: 22)

                    Text("No Collection")
                        .font(Sans.font(size: 14, weight: showUncategorizedOnly ? .semibold : .medium))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 8)
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .frame(height: 34)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(showUncategorizedOnly ? theme.textMuted.opacity(colorScheme == .dark ? 0.18 : 0.12) : Color.clear)
                }
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func collectionFilterSection(_ title: String, collections: [SnippetCollection]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Sans.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 3)

            ForEach(collections) { collection in
                collectionFilterRow(collection)
            }
        }
    }

    private func collectionFilterRow(_ collection: SnippetCollection) -> some View {
        let isSelected = selectedSearchCollections.contains(collection.persistentModelID)
        let accent = collection.displayColor
        let activeCount = collection.snippets.count(where: { $0.deletedAt == nil })

        return Button {
            if isSelected {
                selectedSearchCollections.remove(collection.persistentModelID)
            } else {
                selectedSearchCollections.insert(collection.persistentModelID)
                showUncategorizedOnly = false
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(Sans.font(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.text : .clear)
                    .frame(width: 18)

                CollectionIconView(
                    iconName: collection.displayIconName,
                    color: accent,
                    size: 14,
                    isSelected: false
                )
                .frame(width: 22, height: 22)

                Text(collection.name)
                    .font(Sans.font(size: 14, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Text("\(activeCount)")
                    .font(Mono.font(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .monospacedDigit()
            }
            .padding(.leading, 12)
            .padding(.trailing, 12)
            .frame(height: 34)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? accent.opacity(colorScheme == .dark ? 0.18 : 0.12) : Color.clear)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(Mono.font(size: 10, weight: .semibold))
                Text("snippets")
                    .font(Mono.font(size: 11, weight: .semibold))
            }
            .foregroundStyle(theme.text)
            // Keep the "snippets" label at full width; the flexible text field
            // and its helper placeholder absorb any shrinking as the window
            // narrows, so only the helper text truncates.
            .fixedSize()

            Text(">")
                .font(Mono.font(size: 12, weight: .bold))
                .foregroundStyle(searchFocused ? theme.text : theme.safeAccentText(theme.accent))

            TextField("", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(Mono.font(size: 13))
                .foregroundStyle(theme.text)
                .tint(searchFocused ? theme.safeAccentText(theme.accent) : theme.accent)
                .overlay(alignment: .leading) {
                    if searchText.isEmpty {
                        Text("search title, description, or code…")
                            .font(Mono.font(size: 13))
                            .foregroundStyle(colorScheme == .dark ? theme.text.opacity(0.72) : theme.textMuted.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .allowsHitTesting(false)
                    }
                }

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Mono.font(size: 12))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
            }

            Text(searchFocused ? "esc" : "⌘F")
                .font(Mono.font(size: 10, weight: .semibold))
                .foregroundStyle(searchFocused ? theme.textMuted : theme.text.opacity(0.78))
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 7, style: .continuous),
            tint: searchFocused ? theme.accent : nil,
            interactive: true,
            borderOpacity: searchFocused ? 0.48 : (colorScheme == .dark ? 0.16 : 0.36),
            shadowRadius: 6,
            shadowY: 3
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(searchFocused ? theme.accent.opacity(0.42) : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            DSGlassContainer(spacing: 8) {
                HStack(spacing: 8) {
                    FilterTag(
                        label: "lang:all",
                        icon: "asterisk",
                        accent: theme.accent,
                        selectedFillAccent: theme.accent.blended(with: .black, ratio: 0.1),
                        isSelected: selectedLanguages.isEmpty
                    ) {
                        withAnimation(.snappy) {
                            selectedLanguages.removeAll()
                        }
                    }
                    ForEach(availableLanguages) { language in
                        let baseAccent = Color(hex: language.accentHex) ?? theme.accent
                        let accent = colorScheme == .dark 
                            ? baseAccent.saturation(3.0).brightness(0.22)
                            : baseAccent.saturation(3.0).brightness(-0.15)
                        let selectedAccent = (Color(hex: language.accentHexSelectedFill) ?? accent)
                            .saturation(2.5)
                            .brightness(0.15)
                        FilterTag(
                            label: "lang:\(language.rawValue.lowercased())",
                            icon: language.symbolName,
                            accent: accent,
                            foregroundAccent: colorScheme == .dark ? .white : accent.blended(with: .black, ratio: 0.18),
                            selectedFillAccent: selectedAccent,
                            isSelected: selectedLanguages.contains(language)
                        ) {
                            withAnimation(.snappy) {
                                if selectedLanguages.contains(language) {
                                    selectedLanguages.remove(language)
                                } else {
                                    selectedLanguages.insert(language)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .padding(.vertical, 6)
        }
        .scrollClipDisabled()
        .frame(height: 48)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text(isTrashMode ? "// trash is empty" : "// no snippets yet")
                .font(Mono.font(size: 13, weight: .semibold))
                .foregroundStyle(theme.comment)
            if !isTrashMode {
                Button { onNew?() } label: {
                    Text("new snippet")
                        .font(Mono.font(size: 13, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.surface))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 480)
        .padding(DSToken.Spacing.xl)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.surface.opacity(0.6)))
    }

    @ViewBuilder
    private var fab: some View {
        if !isTrashMode {
            Button(action: { onNew?() }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(Mono.font(size: 14, weight: .bold))
                    Text("new snippet")
                        .font(Mono.font(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .foregroundStyle(colorScheme == .dark ? .white : theme.text)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                    tint: theme.accent,
                    interactive: true,
                    borderOpacity: colorScheme == .dark ? 0.26 : 0.46,
                    shadowRadius: fabHovered ? 16 : 10,
                    shadowY: fabHovered ? 8 : 5
                )
                .overlay {
                    if colorScheme == .light {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.accent.opacity(0.12))
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(showMoveSheet)
            .scaleEffect(fabHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fabHovered)
            .onHover { fabHovered = $0 }
        }
    }

}

private struct MoveToCollectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let collections: [SnippetCollection]
    let showLibraryOption: Bool
    let itemCount: Int
    let onMove: (SnippetCollection?) -> Void
    let onCancel: () -> Void

    @State private var searchText: String = ""
    @State private var hoveredRowID: PersistentIdentifier? = nil
    @State private var isLibraryRowHovered: Bool = false

    private var theme: Theme { Theme.current(colorScheme) }

    private var rows: [CollectionMoveRow] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MoveCollectionTree.rows(from: collections)
            : MoveCollectionTree.searchRows(from: collections, matching: searchText)
    }

    private var titleText: String {
        itemCount == 1 ? "move 1 item" : "move \(itemCount) items"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DSGlassContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeader(titleText)
                        .padding(.trailing, 34)

                    searchField
                        .padding(.top, 8)

                    ScrollView {
                        VStack(spacing: 0) {
                            if showLibraryOption {
                                libraryRow
                                if !rows.isEmpty {
                                    divider
                                }
                            }

                            if rows.isEmpty {
                                Text("no matching collections")
                                    .font(Mono.font(size: 11, weight: .semibold))
                                    .foregroundStyle(theme.textMuted)
                                    .frame(maxWidth: .infinity, minHeight: 60)
                            } else {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    collectionRow(row)
                                    if index < rows.count - 1 {
                                        divider
                                    }
                                }
                            }
                        }
                        .liquidGlassSurface(
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                            shadowRadius: 8,
                            shadowY: 4
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.text)
                    .frame(width: 30, height: 30)
                    .contentShape(Circle())
                    .liquidGlassSurface(
                        in: Circle(),
                        shadowRadius: 12,
                        shadowY: 6
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel("Close")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(Mono.font(size: 10, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            TextField(
                "",
                text: $searchText,
                prompt: Text("filter collections…")
                    .font(Mono.font(size: 11))
                    .foregroundColor(theme.textMuted.opacity(0.85))
            )
            .textFieldStyle(.plain)
            .font(Mono.font(size: 12))
            .foregroundStyle(theme.text)
            .tint(theme.accent)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Mono.font(size: 11))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 7, style: .continuous),
            interactive: true,
            shadowRadius: 6,
            shadowY: 3
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(theme.border)
            .frame(height: 1)
    }

    private var libraryRow: some View {
        Button(action: { onMove(nil) }) {
            HStack(spacing: 10) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 22, height: 22)

                Text("All Snippets")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(isLibraryRowHovered ? theme.accent.opacity(colorScheme == .dark ? 0.12 : 0.08) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { isLibraryRowHovered = $0 }
    }

    private func collectionRow(_ row: CollectionMoveRow) -> some View {
        let collection = row.collection
        let snippetCount = collection.snippets.count { $0.deletedAt == nil }
        let isHovered = hoveredRowID == row.id
        return Button(action: { onMove(collection) }) {
            HStack(spacing: 10) {
                // Tree guides: a vertical rule per ancestor level, then an
                // elbow marking this row as a child of the row above it.
                if row.depth > 0 {
                    HStack(spacing: 0) {
                        ForEach(0..<row.depth, id: \.self) { level in
                            Group {
                                if level == row.depth - 1 {
                                    Image(systemName: "arrow.turn.down.right")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(theme.textFaint)
                                } else {
                                    Rectangle()
                                        .fill(theme.border)
                                        .frame(width: 1, height: 18)
                                }
                            }
                            .frame(width: 18)
                        }
                    }
                }

                Image(systemName: collection.displayIconName)
                    .font(.system(size: row.depth == 0 ? 14 : 12, weight: .semibold))
                    .foregroundStyle(collection.displayColor)
                    .frame(width: 22, height: 22)

                Text(collection.name)
                    .font(.system(size: row.depth == 0 ? 13 : 12.5, weight: .medium))
                    .foregroundStyle(theme.text)

                Spacer()

                Text("\(snippetCount)")
                    .font(Mono.font(size: 10, weight: .semibold))
                    .foregroundStyle(theme.textFaint)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.textFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .background(isHovered ? collection.displayColor.opacity(colorScheme == .dark ? 0.12 : 0.08) : .clear)
        }
        .buttonStyle(.plain)
        .onHover { hoveredRowID = $0 ? row.id : nil }
    }
}

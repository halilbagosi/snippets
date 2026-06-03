import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct SnippetGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme

    let snippets: [Snippet]
    let searchResultCollections: [SnippetCollection]
    let searchResultSnippets: [Snippet]
    let searchQuery: String
    @Binding var searchText: String
    @Binding var selectedLanguages: Set<SupportedLanguage>
    @Binding var selectedSearchCollections: Set<PersistentIdentifier>
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
    var onDelete: ((Snippet) -> Void)? = nil
    var onUndoDelete: (() -> PersistentIdentifier?)? = nil
    var onMoveSnippetToLibrary: ((Snippet) -> Void)? = nil
    var onMoveSnippetToCollection: ((Snippet, SnippetCollection) -> Void)? = nil
    var onCopySnippetToCollection: ((Snippet, SnippetCollection) -> Void)? = nil
    var isTrashMode: Bool = false
    var onRestore: ((Snippet) -> Void)? = nil
    var onPermanentDelete: ((Snippet) -> Void)? = nil
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
    @State private var draggingSnippetID: PersistentIdentifier? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var dragLocation: CGPoint = .zero
    @State private var pullOffset: CGSize = .zero
    @State private var trashFrame: CGRect = .zero
    @State private var isTrashTargeted = false
    @State private var minimizingSnippetID: PersistentIdentifier? = nil
    @State private var reassemblingSnippetID: PersistentIdentifier? = nil
    @State private var pendingReassemblingSnippetID: PersistentIdentifier? = nil
    @State private var minimizeProgress: CGFloat = 0.0
    @State private var unminimizeProgress: CGFloat = 1.0
    @State private var cardSizes: [PersistentIdentifier: CGSize] = [:]
    @State private var genieSnapshots: [PersistentIdentifier: NSImage] = [:]
    @State private var collectionFilterSearchText = ""
#if canImport(AppKit)
    @State private var keyEventMonitor: Any? = nil
#endif

    private let columns = [GridItem(.adaptive(minimum: 420, maximum: 640), spacing: 20)]
    private let subcollectionColumns = [GridItem(.adaptive(minimum: 440, maximum: 680), spacing: 16)]
    private var sectionCollapseAnimation: Animation {
        .interactiveSpring(response: 0.34, dampingFraction: 0.96, blendDuration: 0.08)
    }
    private var hasVisibleSubcollections: Bool {
        searchQuery.isEmpty && !subcollections.isEmpty && selectedLanguages.isEmpty && selectedSearchCollections.isEmpty
    }
    private var hasAnyGalleryContent: Bool {
        hasAnyResults || hasVisibleSubcollections
    }
    private var hasAnyResults: Bool {
        viewModel.hasAnyResults(
            snippets: snippets,
            searchResultCollections: searchResultCollections,
            searchResultSnippets: searchResultSnippets,
            searchQuery: searchQuery
        )
    }
    private var visibleSnippetIDs: Set<PersistentIdentifier> {
        viewModel.visibleSnippetIDs(
            snippets: snippets,
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
        collectionFilterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private var collectionFilterMatches: [SnippetCollection] {
        guard !collectionFilterQuery.isEmpty else { return availableCollections }
        return availableCollections.filter { collection in
            collection.name.lowercased().contains(collectionFilterQuery)
        }
    }
    private var selectedCollectionFilterMatches: [SnippetCollection] {
        collectionFilterMatches.filter { selectedSearchCollections.contains($0.persistentModelID) }
    }
    private var unselectedCollectionFilterMatches: [SnippetCollection] {
        collectionFilterMatches.filter { !selectedSearchCollections.contains($0.persistentModelID) }
    }
    private var collectionFilterSectionCount: Int {
        var count = 0
        if !selectedCollectionFilterMatches.isEmpty { count += 1 }
        if !unselectedCollectionFilterMatches.isEmpty { count += 1 }
        return count
    }
    private var collectionFilterListHeight: CGFloat {
        if collectionFilterMatches.isEmpty { return 76 }

        let rowHeight: CGFloat = 37
        let sectionHeaderHeight: CGFloat = 28
        let sectionSpacing: CGFloat = collectionFilterSectionCount > 1 ? 8 : 0
        let bottomPadding: CGFloat = 9
        let contentHeight = CGFloat(collectionFilterMatches.count) * rowHeight
            + CGFloat(collectionFilterSectionCount) * sectionHeaderHeight
            + sectionSpacing
            + bottomPadding

        return min(contentHeight, 400)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(alignment: .leading, spacing: 22) {
                            if !hasAnyGalleryContent {
                                emptyState
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 36)
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
                                if !snippets.isEmpty {
                                    if !selectedLanguages.isEmpty {
                                        languageGroupedSnippets(viewModel.ordered(snippets))
                                    } else if !selectedSearchCollections.isEmpty {
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
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.top, 16)
                        .padding(.bottom, isTrashMode ? 24 : 112)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        topBar
                    }
                }
            }
            .scrollIndicators(.never)

            dragTrashTarget
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(.leading, 32)
                .padding(.bottom, 28)

            fab
                .padding(.trailing, 32)
                .padding(.bottom, 24)
        }
        .coordinateSpace(name: "galleryDragSpace")
        .onAppear {
            hasAnimatedCards = false
            withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) {
                hasAnimatedCards = true
            }
            #if canImport(AppKit)
            guard keyEventMonitor == nil else { return }
            keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let chars = event.charactersIgnoringModifiers ?? ""
            if event.modifierFlags.contains(.command), chars.lowercased() == "z" {
                if let restoredID = onUndoDelete?() {
                    queueUndoDeleteAnimation(for: restoredID)
                    return nil
                }
                return event
            }
                if event.modifierFlags.contains(.command), chars.lowercased() == "f" {
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
        .onChange(of: snippets.count) { _, _ in
            hasAnimatedCards = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                hasAnimatedCards = true
            }
        }
        .onChange(of: subcollections.count) { _, _ in
            hasAnimatedCards = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                hasAnimatedCards = true
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            guard !newValue.isEmpty else { return }
            isCollectionsSectionExpanded = true
            isSnippetsSectionExpanded = true
        }
        .onChange(of: visibleSnippetIDs) { _, _ in
            startPendingReassemblyIfVisible()
        }
        .onDisappear {
            #if canImport(AppKit)
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
            #endif
        }
    }

    private var theme: Theme { Theme.current(colorScheme) }

    private func queueUndoDeleteAnimation(for restoredID: PersistentIdentifier) {
        pendingReassemblingSnippetID = restoredID
        DispatchQueue.main.async {
            startPendingReassemblyIfVisible()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            startPendingReassemblyIfVisible()
        }
    }

    private func startPendingReassemblyIfVisible() {
        guard let restoredID = pendingReassemblingSnippetID, visibleSnippetIDs.contains(restoredID) else { return }
        pendingReassemblingSnippetID = nil
        withAnimation(.easeOut(duration: 0.12)) {
            reassemblingSnippetID = restoredID
        }

        // Start unshatter progress (1 -> 0) when the reassembly animation plays
        unminimizeProgress = 1.0
        withAnimation(.easeOut(duration: 0.78).delay(0.06)) {
            unminimizeProgress = 0.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) {
            if reassemblingSnippetID == restoredID {
                withAnimation(.easeOut(duration: 0.18)) {
                    reassemblingSnippetID = nil
                }
            }
        }
    }

    private func subcollectionGrid(_ source: [SnippetCollection]) -> some View {
        GlassEffectContainer(spacing: 18) {
            LazyVGrid(columns: subcollectionColumns, spacing: 14) {
                ForEach(Array(source.enumerated()), id: \.element.persistentModelID) { index, collection in
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
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 3)
                                .overlay(alignment: .topTrailing) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? theme.accent : theme.textMuted.opacity(0.5))
                                        .font(.title2)
                                        .padding(12)
                                        .background {
                                            Circle().fill(theme.surfaceElevated).padding(12)
                                        }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .opacity(hasAnimatedCards ? 1 : 0)
                    .offset(y: hasAnimatedCards ? 0 : 6)
                    .animation(
                        .spring(response: 0.32, dampingFraction: 0.94)
                            .delay(min(Double(index) * 0.02, 0.12)),
                        value: hasAnimatedCards
                    )
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
    }

    private func dragOffset(for snippet: Snippet) -> CGSize {
        if draggingSnippetID == snippet.persistentModelID && !isTrashMode {
            return CGSize(
                width: dragTranslation.width + pullOffset.width,
                height: dragTranslation.height + pullOffset.height
            )
        }
        return .zero
    }

    private func genieDistortionProgress(for snippet: Snippet) -> CGFloat {
        if minimizingSnippetID == snippet.persistentModelID {
            return minimizeProgress
        }
        if reassemblingSnippetID == snippet.persistentModelID {
            return unminimizeProgress
        }
        guard draggingSnippetID == snippet.persistentModelID else { return 0 }
        let trashCenter = CGPoint(x: trashFrame.midX, y: trashFrame.midY)
        let distance = hypot(dragLocation.x - trashCenter.x, dragLocation.y - trashCenter.y)
        let pullRadius: CGFloat = 350
        guard distance < pullRadius else { return 0 }
        let proximity = 1.0 - (distance / pullRadius)
        return min(pow(proximity, 1.8) * 0.45, 0.45)
    }

    private func cardDragGesture(for snippet: Snippet) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("galleryDragSpace"))
            .onChanged { value in
                if minimizingSnippetID != nil { return }
                if draggingSnippetID == nil {
                    // Capture snapshot for Metal shader effect
                    #if canImport(AppKit)
                    if MetalGenieOverlay.isSupported, genieSnapshots[snippet.persistentModelID] == nil {
                        if let size = cardSizes[snippet.persistentModelID] {
                            let cardView = SnippetCard(snippet: snippet, isSelectionMode: viewModel.isSelectMode).frame(width: size.width, height: size.height)
                            if let img = ViewSnapshot.snapshot(of: cardView, size: size) {
                                genieSnapshots[snippet.persistentModelID] = img
                            }
                        }
                    }
                    #endif
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.8)) {
                        draggingSnippetID = snippet.persistentModelID
                    }
                }
                dragTranslation = value.translation
                dragLocation = value.location

                let trashCenter = CGPoint(x: trashFrame.midX, y: trashFrame.midY)
                let distance = hypot(value.location.x - trashCenter.x, value.location.y - trashCenter.y)
                let pullRadius: CGFloat = 350

                if distance < pullRadius {
                    let strength = 1.0 - (distance / pullRadius)
                    let magneticFactor = pow(strength, 2.5) * 0.6
                    let dx = trashCenter.x - value.location.x
                    let dy = trashCenter.y - value.location.y
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 18)) {
                        pullOffset = CGSize(width: dx * magneticFactor, height: dy * magneticFactor)
                    }
                } else {
                    withAnimation(.interpolatingSpring(stiffness: 280, damping: 18)) {
                        pullOffset = .zero
                    }
                }

                withAnimation(.easeOut(duration: 0.12)) {
                    isTrashTargeted = trashFrame.insetBy(dx: -12, dy: -12).contains(value.location) || distance < 50
                }
            }
            .onEnded { value in
                let trashCenter = CGPoint(x: trashFrame.midX, y: trashFrame.midY)
                let distance = hypot(value.location.x - trashCenter.x, value.location.y - trashCenter.y)
                let droppedInTrash = trashFrame.insetBy(dx: -12, dy: -12).contains(value.location) || distance < 50

                if droppedInTrash {
                    minimize(snippet, from: value.location)
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                        draggingSnippetID = nil
                        dragTranslation = .zero
                        pullOffset = .zero
                        isTrashTargeted = false
                    }
                }
            }
    }

    private func minimize(_ snippet: Snippet, from location: CGPoint) {
        let target = CGPoint(x: trashFrame.midX, y: trashFrame.midY) // suck exactly into center
        let additionalTranslation = CGSize(width: target.x - location.x, height: target.y - location.y)

        withAnimation(.easeInOut(duration: 0.24)) {
            dragTranslation = CGSize(
                width: dragTranslation.width + pullOffset.width + additionalTranslation.width,
                height: dragTranslation.height + pullOffset.height + additionalTranslation.height
            )
            pullOffset = .zero
            isTrashTargeted = true
        }

        // Prepare snapshot for metal shader if supported
        #if canImport(AppKit)
        if MetalGenieOverlay.isSupported {
            if let size = cardSizes[snippet.persistentModelID] {
                let cardView = SnippetCard(snippet: snippet, isSelectionMode: viewModel.isSelectMode).frame(width: size.width, height: size.height)
                if let img = ViewSnapshot.snapshot(of: cardView, size: size) {
                    genieSnapshots[snippet.persistentModelID] = img
                }
            }
        }

        withAnimation(.easeOut(duration: 0.16).delay(0.10)) {
            minimizingSnippetID = snippet.persistentModelID
        }

        // Drive Metal shatter progress from 0 -> 1 over ~0.70s
        minimizeProgress = 0.0
        withAnimation(.easeInOut(duration: 0.70).delay(0.10)) {
            minimizeProgress = 1.0
        }
        #endif

        // After the visual shatter completes, perform deletion and cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.92) {
            onDelete?(snippet)
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                draggingSnippetID = nil
                minimizingSnippetID = nil
                dragTranslation = .zero
                pullOffset = .zero
                isTrashTargeted = false
            }
            // Reset progress for potential future use
            minimizeProgress = 0.0
        }
    }

    private func snippetGrid(_ source: [Snippet]) -> some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(Array(source.enumerated()), id: \.element.persistentModelID) { index, snippet in
                let gProgress = genieDistortionProgress(for: snippet)
                ZStack {
                    SnippetCard(
                        snippet: snippet,
                        inTrashView: isTrashMode,
                        isSelectionMode: viewModel.isSelectMode,
                        onRestore: { onRestore?(snippet) },
                        onPermanentDelete: { onPermanentDelete?(snippet) }
                    )
                    .opacity(gProgress > 0.001 ? 0 : 1)

                    if gProgress > 0.001 {
                        if MetalGenieOverlay.isSupported {
                            MetalGenieOverlay(
                                progress: gProgress,
                                accent: theme.accentColor(for: snippet.language),
                                snapshot: genieSnapshots[snippet.persistentModelID]
                            )
                            .transition(.opacity)
                        } else {
                            if reassemblingSnippetID == snippet.persistentModelID {
                                ReverseGenieOverlay(accent: theme.accentColor(for: snippet.language))
                                    .transition(.opacity)
                            } else {
                                GenieOverlay(accent: theme.accentColor(for: snippet.language))
                                    .transition(.opacity)
                            }
                        }
                    } else if viewModel.isSelectMode {
                        let isSelected = viewModel.selectedForAction.contains(snippet.persistentModelID)
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 3)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isSelected ? theme.accent : theme.textMuted.opacity(0.5))
                                    .font(.title2)
                                    .padding(12)
                                    .background {
                                        Circle().fill(theme.surfaceElevated).padding(12)
                                    }
                            }
                    }
                }
                .frame(maxWidth: .infinity)
                .background(GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            cardSizes[snippet.persistentModelID] = proxy.size
                        }
                })
                    .scaleEffect(pressedSnippetID == snippet.persistentModelID ? 0.97 : 1.0)
                    .scaleEffect(draggingSnippetID == snippet.persistentModelID ? (isTrashTargeted ? 0.58 : 1.03) : 1.0)
                    .opacity(pressedSnippetID == snippet.persistentModelID ? 0.92 : 1.0)
                    .opacity(1.0)
                    .opacity(hasAnimatedCards ? 1 : 0)
                    .offset(dragOffset(for: snippet))
                    .offset(y: hasAnimatedCards ? 0 : 8)
                    .rotationEffect(.degrees(draggingSnippetID == snippet.persistentModelID ? Double(dragTranslation.width / 42) : 0))
                    .zIndex(
                        draggingSnippetID == snippet.persistentModelID ? 4 :
                        minimizingSnippetID == snippet.persistentModelID ? 3 :
                        reassemblingSnippetID == snippet.persistentModelID ? 3 :
                        pressedSnippetID == snippet.persistentModelID ? 2 : 0
                    )
                    .animation(
                        .spring(response: 0.34, dampingFraction: 0.92)
                            .delay(min(Double(index) * 0.02, 0.12)),
                        value: hasAnimatedCards
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: pressedSnippetID)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: draggingSnippetID)
                    .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isTrashTargeted)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // .simultaneousGesture(isTrashMode ? nil : cardDragGesture(for: snippet))
                    .contextMenu {
                        if isTrashMode {
                            Button { onRestore?(snippet) } label: {
                                Label("Put back", systemImage: "arrow.uturn.left")
                            }
                            Button(role: .destructive) { onPermanentDelete?(snippet) } label: {
                                Label("Delete permanently", systemImage: "trash")
                            }
                        } else {
                            Button { onEditSnippet?(snippet) } label: {
                                Label("Edit snippet", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete?(snippet)
                            } label: {
                                Label("Delete snippet", systemImage: "trash")
                            }
                            Divider()
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
                        }
                    }
                    .onTapGesture {
                        if viewModel.isSelectMode {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                viewModel.toggleSelection(for: snippet)
                            }
                            return
                        }
                        guard draggingSnippetID == nil, minimizingSnippetID == nil else { return }
                        
                        onSelect(snippet)
                        
                        withAnimation(.easeOut(duration: 0.11)) {
                            pressedSnippetID = snippet.persistentModelID
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeOut(duration: 0.14)) {
                                pressedSnippetID = nil
                            }
                        }
                    }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private func languageGroupedSnippets(_ source: [Snippet]) -> some View {
        let grouped = Dictionary(grouping: source) { snippet in
            SupportedLanguage(rawValue: snippet.language) ?? .unknown
        }
        let sortedLanguages = selectedLanguages
            .sorted { $0.rawValue.localizedCaseInsensitiveCompare($1.rawValue) == .orderedAscending }

        ForEach(sortedLanguages) { language in
            let langSnippets = grouped[language] ?? []
            let isFilteringByCollection = !selectedSearchCollections.isEmpty
            let langCollections = isFilteringByCollection ? [] : subcollections.filter { collection in
                let allowedIDs = collection.allDescendantIDs
                return source.contains { snippet in
                    snippet.language == language.rawValue &&
                    snippet.collections.contains { allowedIDs.contains($0.persistentModelID) }
                }
            }

            if !langSnippets.isEmpty || !langCollections.isEmpty {
                let visibleSnippets = langSnippets.filter { snippet in
                    !langCollections.contains { collection in
                        let allowedIDs = collection.allDescendantIDs
                        return snippet.collections.contains { allowedIDs.contains($0.persistentModelID) }
                    }
                }
                
                let baseAccent = Color(hex: language.accentHex) ?? theme.accent
                let accent = baseAccent.saturation(3.0).brightness(0.22)
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

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(alignment: .leading, spacing: 12) {
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
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                        .transition(.scale(scale: 0.85, anchor: .leading).combined(with: .opacity))
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
                                    let snippetIDs = displaySnippets.map(\.persistentModelID)
                                    let collectionIDs = subcollections.map(\.persistentModelID)
                                    let allIDs = Set(snippetIDs + collectionIDs)
                                    if viewModel.selectedForAction == allIDs, !allIDs.isEmpty {
                                        viewModel.selectedForAction.removeAll()
                                    } else {
                                        viewModel.selectedForAction = allIDs
                                    }
                                }
                            }

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
                                    for snip in toDeleteSnippets { onPermanentDelete?(snip) }
                                    for coll in toDeleteCollections { onPermanentDeleteCollection?(coll) }
                                } else {
                                    for snip in toDeleteSnippets { onDelete?(snip) }
                                    for coll in toDeleteCollections { onDeleteCollection?(coll) }
                                }
                                withAnimation {
                                    viewModel.clearSelectionAndExitSelectMode()
                                }
                            }
                            .disabled(viewModel.selectedForAction.isEmpty)
                            .opacity(viewModel.selectedForAction.isEmpty ? 0.5 : 1.0)
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

                            if !isTrashMode {
                                FilterTag(
                                    label: selectedSearchCollections.isEmpty ? "collections:all" : "collections:\(selectedSearchCollections.count)",
                                    icon: "folder",
                                    accent: theme.textMuted,
                                    isSelected: !selectedSearchCollections.isEmpty
                                ) {
                                    viewModel.isShowingCollectionFilter.toggle()
                                }
                                .popover(isPresented: $viewModel.isShowingCollectionFilter, arrowEdge: .bottom) {
                                    collectionFilterPopover
                                }
                            }
                        }
                    }
                }
                .frame(height: 36)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: onBack != nil)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isSelectMode)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.isOldestToNewest)
                if !availableLanguages.isEmpty {
                    filterBar
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background {
            Rectangle()
                .fill(.clear)
                .liquidGlassSurface(
                    in: Rectangle(),
                    borderOpacity: colorScheme == .dark ? 0.08 : 0.22,
                    shadowRadius: 0,
                    shadowY: 0
                )
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .frame(height: 1)
                        .foregroundStyle(.white.opacity(colorScheme == .dark ? 0.15 : 0.40))
                }
        }
    }

    private var collectionFilterPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            collectionFilterSearchField
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 5)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !selectedCollectionFilterMatches.isEmpty {
                        collectionFilterSection(
                            "Selected",
                            collections: selectedCollectionFilterMatches
                        )
                    }

                    if !unselectedCollectionFilterMatches.isEmpty {
                        collectionFilterSection(
                            selectedCollectionFilterMatches.isEmpty ? "Collections" : "All Collections",
                            collections: unselectedCollectionFilterMatches
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

            if !selectedSearchCollections.isEmpty {
                Rectangle()
                    .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.34))
                    .frame(height: 1)

                Button {
                    if let onClearSelection = onClearSelection {
                        onClearSelection()
                    } else {
                        selectedSearchCollections.removeAll()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                        Text("Clear Selection")
                        Spacer()
                        Text("\(selectedSearchCollections.count)")
                            .monospacedDigit()
                    }
                    .font(Sans.font(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 330)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .onDisappear {
            collectionFilterSearchText = ""
        }
        .fixedSize(horizontal: false, vertical: true)
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
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surface.opacity(colorScheme == .dark ? 0.26 : 0.30))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.10 : 0.34), lineWidth: 1)
                }
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
        let activeCount = collection.snippets.filter { $0.deletedAt == nil }.count

        return Button {
            withAnimation(.snappy(duration: 0.16)) {
                if isSelected {
                    selectedSearchCollections.remove(collection.persistentModelID)
                } else {
                    selectedSearchCollections.insert(collection.persistentModelID)
                }
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
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? accent.opacity(colorScheme == .dark ? 0.18 : 0.12) : Color.clear)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(Mono.font(size: 10, weight: .semibold))
                Text("snippets")
                    .font(Mono.font(size: 11, weight: .semibold))
            }
            .foregroundStyle(theme.textMuted)

            Text(">")
                .font(Mono.font(size: 12, weight: .bold))
                .foregroundStyle(theme.accent)

            TextField("search title, description, or code…", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(Mono.font(size: 13))
                .foregroundStyle(theme.text)

            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(Mono.font(size: 12))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(.plain)
            }

            Text(searchFocused ? "esc" : "⌘F")
                .font(Mono.font(size: 10, weight: .semibold))
                .foregroundStyle(theme.textFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            tint: searchFocused ? theme.accent : nil,
            interactive: true,
            borderOpacity: searchFocused ? 0.48 : (colorScheme == .dark ? 0.16 : 0.36),
            shadowRadius: 6,
            shadowY: 3
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(searchFocused ? theme.accent.opacity(0.42) : .clear, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
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
                        let accent = baseAccent
                            .saturation(3.0)
                            .brightness(0.22)
                        let selectedAccent = (Color(hex: language.accentHexSelectedFill) ?? accent)
                            .saturation(2.5)
                            .brightness(0.15)
                        FilterTag(
                            label: "lang:\(language.rawValue.lowercased())",
                            icon: language.symbolName,
                            accent: accent,
                            foregroundAccent: colorScheme == .dark ? accent : accent.blended(with: .black, ratio: 0.18),
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
                .padding(.vertical, 12)
            }
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .frame(height: 68)
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
        .padding(28)
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
                    in: Capsule(style: .continuous),
                    tint: .green,
                    interactive: true,
                    borderOpacity: colorScheme == .dark ? 0.26 : 0.46,
                    shadowRadius: fabHovered ? 16 : 10,
                    shadowY: fabHovered ? 8 : 5
                )
                .overlay {
                    if colorScheme == .light {
                        Capsule(style: .continuous)
                            .fill(Color.green.opacity(0.12))
                            .allowsHitTesting(false)
                    }
                }
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .scaleEffect(fabHovered ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: fabHovered)
            .onHover { fabHovered = $0 }
        }
    }

    @ViewBuilder
    private var dragTrashTarget: some View {
        if !isTrashMode {
            let isVisible = draggingSnippetID != nil || minimizingSnippetID != nil
            ZStack {
                Circle()
                    .fill(.clear)
                    .frame(width: 120, height: 120)
                    .liquidGlassSurface(
                        in: Circle(),
                        tint: isTrashTargeted ? .red : nil,
                        borderOpacity: isTrashTargeted ? 0.50 : (colorScheme == .dark ? 0.18 : 0.36),
                        shadowRadius: 20,
                        shadowY: 10
                    )
                    .overlay {
                        Circle()
                            .fill(isTrashTargeted ? Color.red.opacity(colorScheme == .dark ? 0.14 : 0.22) : theme.surface.opacity(0.18))
                    }
                    .overlay {
                        if isTrashTargeted {
                            Circle()
                                .strokeBorder(Color.red.opacity(colorScheme == .dark ? 0.55 : 0.70), lineWidth: 1.5)
                        }
                    }
                    .blur(radius: 0.4)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.12), radius: 20, y: 10)

                Image("Trashcan", bundle: .snippetsResources)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 90)
                    .blendMode(colorScheme == .dark ? .screen : .multiply)
                    .colorMultiply(isTrashTargeted ? Color.red.opacity(0.85) : Color.white)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.18), radius: 10, y: 8)
                    .overlay(alignment: .top) {
                        Ellipse()
                            .stroke(Color.red.opacity(isTrashTargeted ? 0.72 : 0), lineWidth: 1.8)
                            .frame(width: 60, height: 15)
                            .blur(radius: 1.0)
                            .offset(y: 12)
                    }
                    .scaleEffect(isTrashTargeted ? 1.06 : 1.0)
            }
            .frame(width: 140, height: 140)
            .scaleEffect(isTrashTargeted ? 1.08 : 1.0)
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .allowsHitTesting(false)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            trashFrame = proxy.frame(in: .named("galleryDragSpace"))
                        }
                        .onChange(of: proxy.frame(in: .named("galleryDragSpace"))) { _, newFrame in
                            trashFrame = newFrame
                        }
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: isVisible)
            .animation(.spring(response: 0.24, dampingFraction: 0.68), value: isTrashTargeted)
        }
    }
}

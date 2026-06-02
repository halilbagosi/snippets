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
    var onNew: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var onClearSelection: (() -> Void)? = nil
    var onEditCollection: ((SnippetCollection) -> Void)? = nil
    var onDeleteCollection: ((SnippetCollection) -> Void)? = nil
    var onEditSnippet: ((Snippet) -> Void)? = nil
    var onDelete: ((Snippet) -> Void)? = nil
    var onUndoDelete: (() -> PersistentIdentifier?)? = nil
    var isTrashMode: Bool = false
    var onRestore: ((Snippet) -> Void)? = nil
    var onPermanentDelete: ((Snippet) -> Void)? = nil

    @FocusState private var searchFocused: Bool
    @State private var viewModel = SnippetGalleryViewModel()
    @State private var hasAnimatedCards = false
    @State private var isCollectionsSectionExpanded = true
    @State private var isSnippetsSectionExpanded = true
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
#if canImport(AppKit)
    @State private var keyEventMonitor: Any? = nil
#endif

    private let columns = [GridItem(.adaptive(minimum: 420, maximum: 640), spacing: 20)]
    private let subcollectionColumns = [GridItem(.adaptive(minimum: 440, maximum: 680), spacing: 16)]
    private var sectionCollapseAnimation: Animation {
        .interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)
    }
    private var hasVisibleSubcollections: Bool {
        !isTrashMode && searchQuery.isEmpty && !subcollections.isEmpty
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
                                if !searchResultCollections.isEmpty {
                                    GallerySection(
                                        title: "Collections",
                                        count: searchResultCollections.count,
                                        icon: "folder",
                                        tint: theme.accent,
                                        isExpanded: $isCollectionsSectionExpanded,
                                        animation: sectionCollapseAnimation
                                    ) {
                                        subcollectionGrid(searchResultCollections)
                                    }
                                }
                                if !searchResultSnippets.isEmpty {
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
                            } else {
                                if hasVisibleSubcollections {
                                    GallerySection(
                                        title: "Collections",
                                        count: subcollections.count,
                                        icon: "folder",
                                        tint: theme.accent,
                                        isExpanded: $isCollectionsSectionExpanded,
                                        animation: sectionCollapseAnimation
                                    ) {
                                        subcollectionGrid(subcollections)
                                    }
                                }
                                if !snippets.isEmpty {
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
                .padding(.bottom, 28)
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
                    SnippetCollectionCard(
                        collection: collection,
                        isSelectionMode: viewModel.isSelectMode,
                        onOpen: {
                            guard !viewModel.isSelectMode else { return }
                            onSelectCollection?(collection)
                        },
                        onEdit: {
                            onEditCollection?(collection)
                        },
                        onDelete: {
                            onDeleteCollection?(collection)
                        }
                    )
                    .frame(maxWidth: .infinity)
                    .opacity(hasAnimatedCards ? 1 : 0)
                    .offset(y: hasAnimatedCards ? 0 : 16)
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.86)
                            .delay(min(Double(index) * 0.03, 0.24)),
                        value: hasAnimatedCards
                    )
                }
            }
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
                    .offset(y: hasAnimatedCards ? 0 : 16)
                    .rotationEffect(.degrees(draggingSnippetID == snippet.persistentModelID ? Double(dragTranslation.width / 42) : 0))
                    .zIndex(
                        draggingSnippetID == snippet.persistentModelID ? 4 :
                        minimizingSnippetID == snippet.persistentModelID ? 3 :
                        reassemblingSnippetID == snippet.persistentModelID ? 3 :
                        pressedSnippetID == snippet.persistentModelID ? 2 : 0
                    )
                    .animation(
                        .spring(response: 0.45, dampingFraction: 0.86)
                            .delay(min(Double(index) * 0.03, 0.24)),
                        value: hasAnimatedCards
                    )
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: pressedSnippetID)
                    .animation(.spring(response: 0.28, dampingFraction: 0.8), value: draggingSnippetID)
                    .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isTrashTargeted)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .simultaneousGesture(isTrashMode ? nil : cardDragGesture(for: snippet))
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
                                draggingSnippetID = snippet.persistentModelID
                                minimize(snippet, from: CGPoint(x: trashFrame.midX, y: trashFrame.midY))
                            } label: {
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
                        guard draggingSnippetID == nil, minimizingSnippetID == nil else { return }
                        withAnimation(.easeOut(duration: 0.11)) {
                            pressedSnippetID = snippet.persistentModelID
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                            onSelect(snippet)
                            withAnimation(.easeOut(duration: 0.14)) {
                                pressedSnippetID = nil
                            }
                        }
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .padding(.horizontal, -14)
        .padding(.top, -14)
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
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
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
                            let isAllSelected = viewModel.selectedForAction.count == displaySnippets.count && !displaySnippets.isEmpty
                            FilterTag(
                                label: isAllSelected ? "deselect all" : "select all",
                                icon: isAllSelected ? "circle.dashed" : "checkmark.circle.fill",
                                accent: theme.textMuted,
                                isSelected: isAllSelected
                            ) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.toggleSelectAll(for: displaySnippets)
                                }
                            }

                            if isTrashMode {
                                FilterTag(
                                    label: "put back (\(viewModel.selectedForAction.count))",
                                    icon: "arrow.uturn.left",
                                    accent: theme.accent,
                                    isSelected: false
                                ) {
                                    let toRestore = viewModel.selectedSnippets(from: displaySnippets)
                                    for snip in toRestore { onRestore?(snip) }
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
                                let toDelete = viewModel.selectedSnippets(from: displaySnippets)
                                if isTrashMode {
                                    for snip in toDelete { onPermanentDelete?(snip) }
                                } else {
                                    for snip in toDelete { onDelete?(snip) }
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
            Text("Filter by Collections")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            let rowHeight: CGFloat = 32
            let visibleRows = min(CGFloat(max(availableCollections.count, 1)), 5.5)
            let scrollHeight = visibleRows * rowHeight + 16

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(availableCollections) { collection in
                        Button {
                            if selectedSearchCollections.contains(collection.persistentModelID) {
                                selectedSearchCollections.remove(collection.persistentModelID)
                            } else {
                                selectedSearchCollections.insert(collection.persistentModelID)
                            }
                        } label: {
                            HStack {
                                Image(systemName: selectedSearchCollections.contains(collection.persistentModelID) ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedSearchCollections.contains(collection.persistentModelID) ? theme.accent : theme.textFaint)
                                Text(collection.name)
                                    .foregroundStyle(theme.text)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 16)
                            .frame(height: rowHeight)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
            }
            .frame(height: scrollHeight)

            if !selectedSearchCollections.isEmpty {
                Divider()
                Button {
                    if let onClearSelection = onClearSelection {
                        onClearSelection()
                    } else {
                        selectedSearchCollections.removeAll()
                    }
                } label: {
                    Text("Clear Selection")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 240)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 14, style: .continuous),
            borderOpacity: colorScheme == .dark ? 0.18 : 0.34,
            shadowRadius: 16,
            shadowY: 10
        )
        .padding(4)
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
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
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
                .foregroundStyle(theme.text)
                .liquidGlassSurface(
                    in: Capsule(style: .continuous),
                    tint: theme.accent,
                    interactive: true,
                    borderOpacity: colorScheme == .dark ? 0.26 : 0.46,
                    shadowRadius: fabHovered ? 16 : 10,
                    shadowY: fabHovered ? 8 : 5
                )
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

private struct SnippetCollectionCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let collection: SnippetCollection
    var isSelectionMode: Bool = false
    let onOpen: () -> Void
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var hoverLocation: CGPoint = .zero
    @State private var cardSize: CGSize = .zero
    @State private var didAppear = false

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter
    }()

    private var activeSnippets: [Snippet] {
        var seenIDs = Set<PersistentIdentifier>()
        var collected: [Snippet] = []

        func collect(from collection: SnippetCollection) {
            for snippet in collection.snippets where snippet.deletedAt == nil {
                guard !seenIDs.contains(snippet.persistentModelID) else { continue }
                seenIDs.insert(snippet.persistentModelID)
                collected.append(snippet)
            }

            for child in collection.children {
                collect(from: child)
            }
        }

        collect(from: collection)
        return collected.sorted {
            if $0.updatedAt != $1.updatedAt {
                return $0.updatedAt > $1.updatedAt
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private var hoverCenter: CGPoint {
        CGPoint(x: max(cardSize.width, 1) * 0.5, y: max(cardSize.height, 1) * 0.5)
    }

    private var hoverVector: CGVector {
        guard cardSize.width > 0, cardSize.height > 0 else { return .zero }
        return CGVector(
            dx: min(max((hoverLocation.x / cardSize.width - 0.5) * 2, -1), 1),
            dy: min(max((hoverLocation.y / cardSize.height - 0.5) * 2, -1), 1)
        )
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        let accent = collection.displayColor
        let effectiveIsHovered = isSelectionMode ? false : isHovered
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let iconShape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let snippetSummary = "\(activeSnippets.count) Snippet\(activeSnippets.count == 1 ? "" : "s")"

        HStack(spacing: 14) {
            ZStack {
                CollectionIconView(
                    iconName: collection.displayIconName,
                    color: accent,
                    size: 23,
                    isSelected: effectiveIsHovered
                )
            }
            .frame(width: 54, height: 54)
            .liquidGlassSurface(
                in: iconShape,
                tint: accent,
                borderOpacity: colorScheme == .dark ? 0.22 : 0.40,
                shadowRadius: 6,
                shadowY: 3
            )

            Text(collection.name)
                .font(Sans.font(size: 19, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .layoutPriority(1)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: "square.stack.3d.up")
                        .font(Sans.font(size: 14, weight: .semibold))
                    Text(snippetSummary)
                        .font(Sans.font(size: 13, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                        .monospacedDigit()
                }
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous),
                    tint: accent,
                    borderOpacity: colorScheme == .dark ? 0.24 : 0.42,
                    shadowRadius: 6,
                    shadowY: 3
                )

                Text("Created at \(Self.dateFormatter.string(from: collection.createdAt))")
                    .font(Sans.font(size: 12, weight: .regular))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .frame(minWidth: 130, alignment: .trailing)
            .layoutPriority(2)
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 100)
        .contentShape(shape)
        .liquidGlassSurface(
            in: shape,
            tint: effectiveIsHovered ? accent : nil,
            interactive: true,
            borderOpacity: colorScheme == .dark ? 0.20 : 0.46,
            shadowRadius: effectiveIsHovered ? 22 : 15,
            shadowY: effectiveIsHovered ? 12 : 8
        )
        .overlay {
            shape
                .stroke(
                    accent.opacity(effectiveIsHovered ? (colorScheme == .dark ? 0.52 : 0.42) : 0),
                    lineWidth: effectiveIsHovered ? 1.2 : 0
                )
                .allowsHitTesting(false)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        cardSize = proxy.size
                        hoverLocation = CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        cardSize = newSize
                        if !isHovered {
                            hoverLocation = CGPoint(x: newSize.width * 0.5, y: newSize.height * 0.5)
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        .scaleEffect(effectiveIsHovered ? 1.006 : 1.0)
        .rotation3DEffect(
            .degrees(isHovered ? -Double(hoverVector.dy) * 1.4 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.72
        )
        .rotation3DEffect(
            .degrees(isHovered ? Double(hoverVector.dx) * 1.8 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.72
        )
        .offset(
            x: isHovered ? hoverVector.dx * 1.2 : 0,
            y: isHovered ? hoverVector.dy * 1.0 : 0
        )
        .opacity(didAppear ? 1 : 0)
        .offset(y: didAppear ? 0 : 10)
        .shadow(
            color: accent.opacity(effectiveIsHovered ? (colorScheme == .dark ? 0.22 : 0.12) : 0),
            radius: effectiveIsHovered ? 14 : 0,
            x: 0,
            y: effectiveIsHovered ? 8 : 0
        )
        .contentShape(shape)
        .onTapGesture {
            guard !isSelectionMode else { return }
            onOpen()
        }
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.84)) {
                didAppear = true
            }
        }
        .onContinuousHover { phase in
            guard !isSelectionMode else { return }
            switch phase {
            case .active(let location):
                hoverLocation = CGPoint(
                    x: min(max(location.x, 0), max(cardSize.width, 1)),
                    y: min(max(location.y, 0), max(cardSize.height, 1))
                )
                if !isHovered {
                    withAnimation(.easeOut(duration: 0.16)) {
                        isHovered = true
                    }
                }
            case .ended:
                withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                    isHovered = false
                    hoverLocation = hoverCenter
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: isHovered)
        .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.74), value: hoverLocation)
        .accessibilityLabel("\(collection.name), \(snippetSummary), created at \(Self.dateFormatter.string(from: collection.createdAt))")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard !isSelectionMode else { return }
            onOpen()
        }
        .contextMenu {
            if let onEdit {
                Button { onEdit() } label: { Label("Edit collection", systemImage: "pencil") }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: { Label("Delete collection", systemImage: "trash") }
            }
        }
    }
}

private struct GlassShard: Identifiable {
    let id: Int
    let points: [CGPoint]
    let offset: CGSize
    let rotation: Double

    var center: CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let sum = points.reduce(CGPoint.zero) { partial, point in
            CGPoint(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }
}

private struct GlassShardShape: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: CGPoint(x: first.x * rect.width, y: first.y * rect.height))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x * rect.width, y: point.y * rect.height))
        }
        path.closeSubpath()
        return path
    }
}

private struct GenieOverlay: View {
    let accent: Color
    @State private var breakProgress: CGFloat = 0

    private let shards: [GlassShard] = [
        GlassShard(id: 0, points: [CGPoint(x: 0.03, y: 0.05), CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.22, y: 0.42)], offset: CGSize(width: -34, height: -22), rotation: -16),
        GlassShard(id: 1, points: [CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.50, y: 0.40)], offset: CGSize(width: 4, height: -34), rotation: 9),
        GlassShard(id: 2, points: [CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.97, y: 0.04), CGPoint(x: 0.80, y: 0.35)], offset: CGSize(width: 38, height: -20), rotation: 18),
        GlassShard(id: 3, points: [CGPoint(x: 0.04, y: 0.48), CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -42, height: 10), rotation: -22),
        GlassShard(id: 4, points: [CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -8, height: 18), rotation: -6),
        GlassShard(id: 5, points: [CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.73, y: 0.78), CGPoint(x: 0.45, y: 0.74)], offset: CGSize(width: 16, height: 20), rotation: 7),
        GlassShard(id: 6, points: [CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.98, y: 0.48), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.73, y: 0.78)], offset: CGSize(width: 46, height: 12), rotation: 24),
        GlassShard(id: 7, points: [CGPoint(x: 0.08, y: 0.86), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: -28, height: 36), rotation: 15),
        GlassShard(id: 8, points: [CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.67, y: 0.98), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: 30, height: 38), rotation: -13)
    ]

    var body: some View {
        GeometryReader { proxy in
            let progress = min(max(breakProgress, 0), 1)
            let crackPhase = min(progress / 0.34, 1)
            let fallPhase = min(max((progress - 0.24) / 0.76, 0), 1)

            ZStack {
                ForEach(shards) { shard in
                    GlassShardFragmentView(
                        shard: shard,
                        accent: accent,
                        sinkOffset: shardSinkOffset(for: shard, in: proxy.size),
                        crackPhase: crackPhase,
                        fallPhase: fallPhase
                    )
                }
            }
            .background(.white.opacity(0.12 * (1 - fallPhase)))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.70)) {
                breakProgress = 1
            }
        }
    }

    private func shardSinkOffset(for shard: GlassShard, in size: CGSize) -> CGSize {
        let sinkX = size.width * 0.5
        let sinkY = size.height * 1.12
        let currentX = shard.center.x * size.width
        let currentY = shard.center.y * size.height
        let jitter = CGFloat(shard.id % 3 - 1) * 8
        return CGSize(width: sinkX - currentX + jitter, height: sinkY - currentY)
    }
}

// MARK: - Glass Unbreak (reverse: shards assemble from trash back into card)

private struct ReverseGenieOverlay: View {
    let accent: Color
    /// Starts fully broken (1.0) and animates to whole (0.0)
    @State private var breakProgress: CGFloat = 1.0

    private let shards: [GlassShard] = [
        GlassShard(id: 0, points: [CGPoint(x: 0.03, y: 0.05), CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.22, y: 0.42)], offset: CGSize(width: -34, height: -22), rotation: -16),
        GlassShard(id: 1, points: [CGPoint(x: 0.34, y: 0.13), CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.50, y: 0.40)], offset: CGSize(width: 4, height: -34), rotation: 9),
        GlassShard(id: 2, points: [CGPoint(x: 0.66, y: 0.08), CGPoint(x: 0.97, y: 0.04), CGPoint(x: 0.80, y: 0.35)], offset: CGSize(width: 38, height: -20), rotation: 18),
        GlassShard(id: 3, points: [CGPoint(x: 0.04, y: 0.48), CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -42, height: 10), rotation: -22),
        GlassShard(id: 4, points: [CGPoint(x: 0.22, y: 0.42), CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.18, y: 0.78)], offset: CGSize(width: -8, height: 18), rotation: -6),
        GlassShard(id: 5, points: [CGPoint(x: 0.50, y: 0.40), CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.73, y: 0.78), CGPoint(x: 0.45, y: 0.74)], offset: CGSize(width: 16, height: 20), rotation: 7),
        GlassShard(id: 6, points: [CGPoint(x: 0.80, y: 0.35), CGPoint(x: 0.98, y: 0.48), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.73, y: 0.78)], offset: CGSize(width: 46, height: 12), rotation: 24),
        GlassShard(id: 7, points: [CGPoint(x: 0.08, y: 0.86), CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: -28, height: 36), rotation: 15),
        GlassShard(id: 8, points: [CGPoint(x: 0.45, y: 0.74), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.67, y: 0.98), CGPoint(x: 0.34, y: 0.98)], offset: CGSize(width: 30, height: 38), rotation: -13)
    ]

    var body: some View {
        GeometryReader { proxy in
            let progress = min(max(breakProgress, 0), 1)
            // Derive phases from the same formula as GenieOverlay so they mirror exactly
            let crackPhase = min(progress / 0.34, 1)
            let fallPhase  = min(max((progress - 0.24) / 0.76, 0), 1)

            ZStack {
                ForEach(shards) { shard in
                    GlassShardFragmentView(
                        shard: shard,
                        accent: accent,
                        sinkOffset: shardRiseOffset(for: shard, in: proxy.size),
                        crackPhase: crackPhase,
                        fallPhase: fallPhase
                    )
                }
            }
            // Frosted pane brightens as shards lock together
            .background(.white.opacity(0.12 * (1 - fallPhase)))
        }
        .onAppear {
            // Animate from broken (1) to whole (0), mirroring GenieOverlay.
            withAnimation(.easeOut(duration: 0.78)) {
                breakProgress = 0
            }
        }
    }

    /// Rise origin is the same sink point used during breaking (bottom-center / trash area),
    /// so shards appear to fly up from where they were discarded and snap back into place.
    private func shardRiseOffset(for shard: GlassShard, in size: CGSize) -> CGSize {
        let originX = size.width * 0.5
        let originY = size.height * 1.12
        let currentX = shard.center.x * size.width
        let currentY = shard.center.y * size.height
        let jitter = CGFloat(shard.id % 3 - 1) * 8
        return CGSize(width: originX - currentX + jitter, height: originY - currentY)
    }
}

private struct GlassShardFragmentView: View {
    let shard: GlassShard
    let accent: Color
    let sinkOffset: CGSize
    let crackPhase: CGFloat
    let fallPhase: CGFloat

    private var crackOffset: CGSize {
        CGSize(width: shard.offset.width * crackPhase, height: shard.offset.height * crackPhase)
    }

    private var fallOffset: CGSize {
        CGSize(width: sinkOffset.width * fallPhase, height: sinkOffset.height * fallPhase)
    }

    var body: some View {
        GlassShardShape(points: shard.points)
            .fill(.white.opacity(0.20))
            .overlay {
                GlassShardShape(points: shard.points)
                    .stroke(.white.opacity(0.58), lineWidth: 0.9)
            }
            .overlay {
                GlassShardShape(points: shard.points)
                    .stroke(accent.opacity(0.30), lineWidth: 1.4)
                    .blur(radius: 2.5)
            }
            .shadow(color: .white.opacity(0.20 * (1 - fallPhase)), radius: 7)
            .offset(x: crackOffset.width + fallOffset.width, y: crackOffset.height + fallOffset.height)
            .rotationEffect(.degrees(shard.rotation * (crackPhase + fallPhase * 1.35)))
            .scaleEffect(1.0 - fallPhase * 0.48)
            .opacity(1.0 - fallPhase * 0.92)
    }
}

private struct FilterTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let icon: String
    let accent: Color
    var foregroundAccent: Color? = nil
    var selectedFillAccent: Color? = nil
    let isSelected: Bool
    let action: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    private var resolvedForeground: Color {
        if isSelected {
            return colorScheme == .dark ? .white : (foregroundAccent ?? theme.safeAccentText(accent))
        }
        if colorScheme == .dark { return accent }
        if let foregroundAccent { return foregroundAccent }
        return theme.safeAccentText(accent)
    }

    private var resolvedFill: Color {
        if isSelected {
            if let fill = selectedFillAccent {
                return fill
            }
            if colorScheme == .light {
                return foregroundAccent ?? accent
            }
            return accent
        }
        return accent.opacity(0.18)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Mono.font(size: 10, weight: .semibold))
                Text(label)
                    .font(Mono.font(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(resolvedForeground)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(resolvedFill.opacity(isSelected ? (colorScheme == .dark ? 0.20 : 0.12) : 0.03))
            }
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 7, style: .continuous),
                tint: resolvedFill,
                interactive: true,
                borderOpacity: isSelected ? 0.44 : (colorScheme == .dark ? 0.20 : 0.38),
                shadowRadius: colorScheme == .dark ? 4 : 0,
                shadowY: colorScheme == .dark ? 2 : 0
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(accent.opacity(isSelected ? 0.50 : (colorScheme == .dark ? 0.28 : 0.30)), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.12), value: isSelected)
    }
}

private extension Bundle {
    static var snippetsResources: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}

extension Color {
    func saturation(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: min(s * amount, 1.0), brightness: b, opacity: a)
    }

    func brightness(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return Color(hue: h, saturation: s, brightness: min(b + amount, 1.0), opacity: a)
    }
}

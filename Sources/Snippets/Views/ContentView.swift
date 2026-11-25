import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(AppIntentNavigator.self) private var navigator
    @Environment(PreviewTrust.self) private var previewTrust

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
    /// Code captured from the clipboard, seeding the next new-snippet editor.
    @State private var newSnippetDraftCode: String? = nil
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
    /// Snippets visited before the current one, so the detail view can offer a
    /// back button when navigating into connected snippets. Cleared whenever the
    /// detail overlay closes (see `.onChange(of: selectedSnippetID)`).
    @State private var snippetHistory: [PersistentIdentifier] = []
    enum SidebarSelectionContext: Hashable {
        case frequentlyUsed
        case favorites
        case allSnippets
        case trash
        case collection(PersistentIdentifier)
        case favoriteCollection(PersistentIdentifier)
    }
    @State private var sidebarSelectionContext: SidebarSelectionContext? = .allSnippets

    /// All Snippets opens scoped to snippets outside any collection (the
    /// collections are shown as cards above them). A language filter is an
    /// explicit request to see that language wherever it lives, so it lifts
    /// the scope — otherwise picking a language in the sidebar hides every
    /// match inside a collection while the row's count still includes them.
    ///
    /// A collection filter lifts it too: "no collection" and "in collection X"
    /// can never both hold, so restoring the scope while collections are
    /// picked (say, on clearing the last language) empties the gallery.
    static func showsUncategorizedOnly(
        context: SidebarSelectionContext?,
        selectedLanguages: Set<SupportedLanguage>,
        hasCollectionFilter: Bool = false
    ) -> Bool {
        context == .allSnippets && selectedLanguages.isEmpty && !hasCollectionFilter
    }

    /// Search is global: the automatic All Snippets scope above only shapes
    /// the browsing grid, so it is lifted while a query is active. A
    /// "No collection" filter the user picked themselves still applies.
    static func effectiveUncategorizedOnly(
        showUncategorizedOnly: Bool,
        isAutomaticScope: Bool,
        isSearching: Bool
    ) -> Bool {
        showUncategorizedOnly && !(isSearching && isAutomaticScope)
    }
    @State private var selectedCollectionID: PersistentIdentifier? = nil
    @State private var sidebarSearch: String = ""
    @State private var showFavoritesOnly: Bool = false
    @State private var showUncategorizedOnly: Bool = true
    /// True while `showUncategorizedOnly` holds the value navigation set, not
    /// one the user picked from the collection filter.
    @State private var uncategorizedScopeIsAutomatic: Bool = true

    private var effectiveUncategorizedOnly: Bool {
        Self.effectiveUncategorizedOnly(
            showUncategorizedOnly: showUncategorizedOnly,
            isAutomaticScope: uncategorizedScopeIsAutomatic,
            isSearching: !trimmedSearchText.isEmpty
        )
    }

    /// The gallery's view of the filter: shows the effective state (so the
    /// chip reads "collections:all" during a global search), and any change
    /// made through it is the user's own choice.
    private var uncategorizedOnlyBinding: Binding<Bool> {
        Binding(
            get: { effectiveUncategorizedOnly },
            set: { newValue in
                showUncategorizedOnly = newValue
                uncategorizedScopeIsAutomatic = false
            }
        )
    }
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
    /// Whether the open snippet's preview is expanded to fill the window.
    /// The card then grows over the sidebar too, and everything behind it
    /// is shaded and blurred.
    @State private var isPreviewExpanded = false
    /// The same flag (and the card's frames) for the views inside the detail
    /// card's stage, which live in their own hosting view; see
    /// `DetailStageLayout`. Always set together with `isPreviewExpanded`,
    /// through `setPreviewExpanded(_:)`.
    @State private var stageLayout = DetailStageLayout()
    /// The detail column's content area in window coordinates, which places
    /// the detail card while it is not expanded.
    @State private var detailFrame: CGRect = .zero
    /// Where the click that opened the card landed, in window coordinates.
    /// The card grows out of that point and shrinks back into it on close;
    /// nil (keyboard, Shortcuts, links) grows it from its own centre.
    @State private var detailOrigin: CGPoint? = nil
    /// The snippet the detail card shows. It follows `selectedSnippetID`
    /// on the way in, but outlives it on the way out, so the card can shrink
    /// and fade after the selection is cleared.
    @State private var presentedSnippetID: PersistentIdentifier? = nil
    /// Bumped for every open from closed, so the stage restarts from the
    /// gallery card rather than continuing a previous animation.
    @State private var detailOpenToken = 0
    /// Gallery card positions, written by the gallery, read on open/close.
    @State private var cardGeometry = GalleryCardGeometry()
    /// The gallery card the detail card morphs out of and back into, in
    /// window coordinates. Nil for the zoom style, and for opens that did
    /// not come from a visible card (keyboard, Shortcuts, links).
    @State private var morphSource: GalleryCardGeometry.Entry? = nil
    /// The gallery card the morph came out of. Its spot in the grid stays
    /// empty for as long as the detail card is open — the card is "in" the
    /// detail card — and it comes back only when a close lands on it.
    @State private var morphSourceID: PersistentIdentifier? = nil
    @AppStorage("gallery.compactCards") private var compactCards = false
    /// False while the card flies open; see `SnippetDetailView.defersHeavyContent`.
    @State private var detailSettled = true
    /// What the card is currently animating towards, so a second request
    /// for the same state (the click starts the open directly, and the
    /// selection's `onChange` then asks again) doesn't restart it.
    @State private var detailTargetID: PersistentIdentifier? = nil

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

    private struct Toast: Equatable {
        /// Distinguishes consecutive toasts so replacing a live one cross-fades
        /// the message instead of teleporting the text inside a static pill.
        let id = UUID()
        let message: String
        let showsUndo: Bool
    }
    @State private var activeToast: Toast?
    @State private var toastHideTask: Task<Void, Never>? = nil


    /// Overlay editors and the detail card appear centred, so scaling from the
    /// centre is right here. Reduce Motion drops the scale and keeps the fade,
    /// which still explains that a layer arrived.
    private var modalTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .center))
        )
    }

    // MARK: - Detail card layer

    /// The open snippet's card, laid over the entire split view rather than
    /// inside the detail column. Collapsed it sits exactly where the column
    /// would centre it; expanded, its frame grows over the sidebar to almost
    /// the whole window — one view the whole way, so the preview inside keeps
    /// its identity and the motion is a single continuous resize. The toast
    /// lives here too, so it still shows above an open card.
    @ViewBuilder
    private var detailCardLayer: some View {
        GeometryReader { proxy in
            let window = proxy.frame(in: .global)
            let column = detailFrame.offsetBy(dx: -window.minX, dy: -window.minY)
            let cardFrame = detailCardFrame(column: column, windowSize: proxy.size, expanded: false)
            let expandedCardFrame = detailCardFrame(column: column, windowSize: proxy.size, expanded: true)
            ZStack(alignment: .topLeading) {
                if isPreviewExpanded {
                    expandedBackdrop
                        .zIndex(1)
                }
                if sidebarSelectionContext != .trash, detailFrame != .zero {
                    detailStage(window: window, cardFrame: cardFrame, expandedCardFrame: expandedCardFrame)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .zIndex(2)
                }
                if sidebarSelectionContext != .trash, detailFrame != .zero {
                    Group {
                        if let toast = activeToast {
                            VStack {
                                Spacer()
                                HStack(spacing: 12) {
                                    Text(toast.message)
                                        .foregroundStyle(theme.text)
                                    if toast.showsUndo {
                                        Button("Undo") {
                                            withAnimation(DSToken.Motion.toastOut) {
                                                _ = undoLast()
                                                activeToast = nil
                                            }
                                        }
                                        .bold()
                                        .foregroundStyle(theme.accent)
                                        .buttonStyle(.plain)
                                    }
                                }
                                // Keyed on the toast's identity so a message that
                                // replaces a live toast cross-fades in place rather
                                // than swapping text inside a motionless pill.
                                // Order matters: `.transition` has to sit inside the
                                // `.id` so it travels with the view being swapped,
                                // and `.animation` outside it to drive that swap.
                                .transition(.opacity)
                                .id(toast.id)
                                .animation(DSToken.Motion.toastIn, value: toast.id)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .padding(.bottom, 60)
                            }
                            .zIndex(100)
                            // Asymmetric on purpose: the toast rises into view, but
                            // dismissal is the system getting out of the way, so it
                            // fades rather than sliding back down.
                            .transition(toastTransition)
                        }
                    }
                    .frame(width: column.width, height: column.height)
                    .position(x: column.midX, y: column.midY)
                    .zIndex(100)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        // Covers the title bar strip too, so the expanded shade reaches the
        // window's top edge, as the sidebar does.
        .ignoresSafeArea()
    }

    private var presentedSnippet: Snippet? {
        guard let id = presentedSnippetID else { return nil }
        return snippets.first(where: { $0.persistentModelID == id })
    }

    /// Opens or closes the detail card to match the selection. The card
    /// grows out of the gallery card that was clicked and shrinks back into
    /// it: a zoom anchored on the click point from about a gallery card's
    /// size, a slight stretch of its bottom edge on the way open, and a fade.
    ///
    /// Zoom and fade are separate animations. Opening, the card is opaque
    /// early, so a solid card grows rather than a ghost drifting. Closing, it
    /// fades from the first frame and is gone before it is back at a gallery
    /// card's size — fading late left a washed-out card over the gallery card
    /// it shrank into. The card leaves the hierarchy only once the fade has
    /// finished, and only if nothing re-opened it meanwhile. Numbers live in
    /// `DetailMotionTuning` (Debug ▸ Detail Motion… in debug builds).
    private func syncDetailPresentation(to id: PersistentIdentifier?) {
        guard id != detailTargetID else { return }
        detailTargetID = id
        let tuning = DetailMotionTuning.shared.values
        if let id {
            let wasClosed = presentedSnippetID == nil
            presentedSnippetID = id
            if wasClosed {
                detailSettled = false
                detailOpenToken += 1
                morphSourceID = morphSource != nil ? id : nil
            }
        } else {
            // Morph back into wherever the card is now; if it is no longer
            // in the grid (scrolled away, filtered out, a linked snippet),
            // fall back to the zoom. Only from fully open (or a morph that
            // is being reversed): at full size the two paths are the same
            // picture, but mid-zoom switching would jump.
            if tuning.morph, detailSettled || morphSource != nil, let presentedSnippetID,
               let entry = cardGeometry.entries[presentedSnippetID] {
                morphSource = entry
                morphSourceID = presentedSnippetID
            } else if morphSource == nil {
                morphSourceID = nil
            }
        }
    }

    /// The window-wide stage that presents the detail card: dim, card, and
    /// the morph's copy of the gallery card. Its motion runs in Core
    /// Animation, not SwiftUI; see `DetailCardStage`.
    private func detailStage(window: CGRect, cardFrame: CGRect, expandedCardFrame: CGRect) -> some View {
        let tuning = DetailMotionTuning.shared.values
        let snippet = presentedSnippet
        let path: DetailCardPath
        if let source = morphSource {
            path = .morph(source: source.frame.offsetBy(dx: -window.minX, dy: -window.minY))
        } else if let origin = detailOrigin {
            path = .zoom(
                anchor: CGPoint(x: origin.x - window.minX - cardFrame.minX, y: origin.y - window.minY - cardFrame.minY),
                startScale: tuning.startScale
            )
        } else {
            path = .zoom(anchor: CGPoint(x: cardFrame.width / 2, y: cardFrame.height / 2), startScale: 0.94)
        }
        return DetailCardStage(
            isOpen: selectedSnippetID != nil && snippet != nil,
            openToken: detailOpenToken,
            card: snippet.map { AnyView(detailCard(for: $0)) },
            galleryCopy: {
                guard let snippet, let source = morphSource else { return nil }
                return AnyView(
                    SnippetCard(
                        snippet: snippet,
                        linkedCount: source.linkedCount,
                        isConnected: source.isConnected,
                        collectionTags: source.collectionTags,
                        isCompact: compactCards
                    )
                    .allowsHitTesting(false)
                )
            }(),
            layout: stageLayout,
            collapsedFrame: cardFrame,
            expandedFrame: expandedCardFrame,
            path: path,
            dimOpacity: isPreviewExpanded ? 0 : detailDimOpacity,
            stretch: (detailOrigin == nil && morphSource == nil) ? 0 : tuning.warp,
            tuning: tuning,
            reduceMotion: reduceMotion,
            onDismissTap: { selectedSnippetID = nil },
            onOpened: {
                guard selectedSnippetID != nil else { return }
                detailSettled = true
            },
            onClosed: {
                guard selectedSnippetID == nil else { return }
                presentedSnippetID = nil
                morphSource = nil
                morphSourceID = nil
            }
        )
    }

    /// The current mouse event's location in the key window, top-left origin
    /// like SwiftUI's global space. Nil when the selection did not come from
    /// a click.
    private static func clickLocationInWindow() -> CGPoint? {
        guard let event = NSApp.currentEvent,
              [.leftMouseDown, .leftMouseUp].contains(event.type),
              let window = event.window,
              let content = window.contentView else { return nil }
        let point = content.convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: content.isFlipped ? point.y : content.bounds.height - point.y)
    }

    /// Collapsed: the size the card always had, centred in the detail column.
    /// Expanded: the window less a margin, starting below the toolbar.
    private func detailCardFrame(column: CGRect, windowSize: CGSize, expanded: Bool) -> CGRect {
        if expanded {
            let margin = Self.expandedCardMargin
            let top = column.minY + margin
            return CGRect(
                x: margin,
                y: top,
                width: max(windowSize.width - margin * 2, 0),
                height: max(windowSize.height - top - margin, 0)
            )
        }
        // Centred on the window, not the detail column: with the sidebar
        // open the card overlaps it (the sidebar is shaded and inert while
        // the card is up — see `DetailCardStage`). Vertically it keeps to the
        // column, which starts below the toolbar.
        let width = min(max(windowSize.width * 0.86, 720), 1180, max(windowSize.width - 40, 0))
        let height = min(max(column.height * 0.9, 520), 940, max(column.height - 24, 0))
        return CGRect(x: windowSize.width / 2 - width / 2, y: column.midY - height / 2, width: width, height: height)
    }

    /// Shade and blur behind an expanded preview, over the sidebar and the
    /// gallery alike. A click on it collapses the preview back to the card.
    private var expandedBackdrop: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(detailDimOpacity)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DSToken.Motion.overlay) {
                setPreviewExpanded(false)
            }
        }
        .transition(.opacity)
    }

    /// Expands or collapses the open snippet's preview. Sets the flag for
    /// this view and for the stage's own view graph in the same transaction,
    /// so a caller's `withAnimation` animates both.
    private func setPreviewExpanded(_ expanded: Bool) {
        // One transaction for both: the shade behind the card, and the card's
        // own frame and contents inside the stage's view graph. The preview
        // grows out of its place in the card while everything else steps
        // aside, exactly as the released card did.
        let tuning = DetailMotionTuning.shared.values
        withAnimation(.smooth(duration: tuning.expandDuration * tuning.slowMotion)) {
            isPreviewExpanded = expanded
            stageLayout.setExpanded(expanded)
        }
    }

    private func detailCard(for snippet: Snippet) -> some View {
        // Read inside the stage's view graph, so expanding animates the
        // card's chrome and contents along with its frame.
        StageExpansionReader(layout: stageLayout) { expanded in
            let radius = expanded ? SnippetDetailView.expandedCardCornerRadius : SnippetDetailView.cardCornerRadius
            SnippetDetailView(
                snippet: snippet,
                canGoBack: !snippetHistory.isEmpty,
                isPreviewExpanded: Binding(
                    get: { stageLayout.isExpanded },
                    set: { setPreviewExpanded($0) }
                ),
                defersHeavyContent: !detailSettled
            ) {
                editingSnippet = snippet
            } onDelete: {
                delete(snippet)
            } onClose: {
                // No `withAnimation`: the stage animates the close itself, and a
                // SwiftUI transaction here would animate the window behind it.
                selectedSnippetID = nil
            } onOpenSnippet: { dependency in
                withAnimation(DSToken.Motion.overlay) {
                    if let current = selectedSnippetID {
                        snippetHistory.append(current)
                    }
                    selectedSnippetID = dependency.persistentModelID
                }
            } onBack: {
                withAnimation(DSToken.Motion.overlay) {
                    if let previous = snippetHistory.popLast() {
                        selectedSnippetID = previous
                    }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(theme.surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(theme.borderStrong, lineWidth: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            // The shadow is cast by a plain shape behind the clipped card, not by
            // the card: a shadow on the card is derived from all of its content's
            // pixels, and redone on every frame of the expand animation. A
            // shape's shadow is the same picture at a fraction of the cost.
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(theme.surface)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.52 : 0.24), radius: 30, x: 0, y: 18)
            }
        }
    }

    /// Margin between the window and an expanded preview's card: enough of
    /// the faded, blurred gallery to show the card floats over it.
    private static let expandedCardMargin: CGFloat = 20
    /// Gallery blur behind an expanded preview: soft enough to keep the
    /// layout recognisable, strong enough that nothing in it competes.
    private static let expandedGalleryBlur: CGFloat = 14
    private static let expandedBackdropBlur: CGFloat = 8

    private var galleryBlurRadius: CGFloat {
        guard selectedSnippet != nil else { return 0 }
        return isPreviewExpanded ? Self.expandedGalleryBlur : 2
    }

    /// The shade behind the detail card, deepened for an expanded preview so
    /// the preview is the only bright thing in the window.
    private var detailDimOpacity: Double {
        if isPreviewExpanded { return colorScheme == .dark ? 0.55 : 0.40 }
        return colorScheme == .dark ? 0.34 : 0.22
    }

    /// Reduce Motion strips the upward slide; the fade alone still reads.
    private var toastTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        )
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

    /// Memoized gallery filter results, following the `CollectionIndexCache`
    /// pattern: a non-observed class so refreshing during body evaluation
    /// doesn't invalidate the view; the signature keeps it consistent.
    ///
    /// Signature audit (plan 010): mutation paths and how the signature sees
    /// them —
    /// - title/code/language/description: editor save bumps `updatedAt`
    ///   (`SnippetEditorViewModel.save`).
    /// - deletedAt: the `snippets` query filters on it, so the array itself
    ///   changes (and delete/restore paths bump `updatedAt` anyway).
    /// - isFavorite: SnippetCard/SnippetDetailView/SnippetCollectionCard
    ///   toggle WITHOUT bumping `updatedAt` → hashed directly.
    /// - collection membership: `commitCollectionEditor` removals don't bump
    ///   the snippet's `updatedAt` → membership ids hashed directly.
    /// - collection name/isFavorite/deletedAt feed the search predicates →
    ///   hashed directly; parent links via `collectionStructureSignature`.
    private final class SnippetFilterCache {
        var signature: Int? = nil
        var base: [Snippet] = []
        var searchFiltered: [Snippet] = []
        var searchResults: [Snippet] = []
        var searchResultCollections: [SnippetCollection] = []
    }
    @State private var snippetFilterCache = SnippetFilterCache()

    /// Every input the filter predicates read. Any new gallery filter MUST be
    /// added here — a missing input means stale results, not slow ones.
    private var filterSignature: Int {
        var hasher = Hasher()
        hasher.combine(collectionStructureSignature)
        hasher.combine(snippets.count)
        for snippet in snippets {
            hasher.combine(snippet.persistentModelID)
            hasher.combine(snippet.updatedAt)
            hasher.combine(snippet.isFavorite)
            for collection in snippet.collections {
                hasher.combine(collection.persistentModelID)
            }
        }
        for collection in collections {
            hasher.combine(collection.name)
            hasher.combine(collection.isFavorite)
            hasher.combine(collection.deletedAt)
        }
        hasher.combine(selectedLanguages)
        hasher.combine(selectedCollectionID)
        hasher.combine(effectiveUncategorizedOnly)
        hasher.combine(selectedSearchCollections)
        hasher.combine(showFavoritesOnly)
        hasher.combine(trimmedSearchText)
        return hasher.finalize()
    }

    private func refreshFilterCacheIfNeeded() {
        let signature = filterSignature
        guard snippetFilterCache.signature != signature else { return }

        let lookup = collectionLookup
        let descendantIDs = descendantIDsByCollectionID
        let needle = trimmedSearchText

        snippetFilterCache.base = GallerySnippetFilter.base(
            snippets: snippets,
            selectedLanguages: selectedLanguages,
            selectedCollectionID: selectedCollectionID,
            showUncategorizedOnly: effectiveUncategorizedOnly,
            selectedSearchCollections: selectedSearchCollections,
            showFavoritesOnly: showFavoritesOnly,
            lookup: lookup,
            descendantIDs: descendantIDs
        )
        let pool = GallerySnippetFilter.searchPool(
            snippets: snippets,
            selectedLanguages: selectedLanguages,
            showUncategorizedOnly: effectiveUncategorizedOnly,
            selectedSearchCollections: selectedSearchCollections,
            showFavoritesOnly: showFavoritesOnly,
            lookup: lookup,
            descendantIDs: descendantIDs
        )
        snippetFilterCache.searchFiltered = pool
        snippetFilterCache.searchResults = GallerySnippetFilter.searchResults(in: pool, needle: needle)
        snippetFilterCache.searchResultCollections = GallerySnippetFilter.searchCollections(
            collections, needle: needle, showFavoritesOnly: showFavoritesOnly
        )
        snippetFilterCache.signature = signature
    }

    private var baseFilteredSnippets: [Snippet] {
        refreshFilterCacheIfNeeded()
        return snippetFilterCache.base
    }

    private var searchFilteredSnippets: [Snippet] {
        refreshFilterCacheIfNeeded()
        return snippetFilterCache.searchFiltered
    }

    private var searchResultCollections: [SnippetCollection] {
        refreshFilterCacheIfNeeded()
        return snippetFilterCache.searchResultCollections
    }

    private var searchResultSnippets: [Snippet] {
        refreshFilterCacheIfNeeded()
        return snippetFilterCache.searchResults
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
        let used = Set(snippets.map { SupportedLanguage(stored: $0.language) })
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

    /// The split view with the detail card layer over it. Its own property
    /// so `body`'s long modifier chain stays within the type checker's budget.
    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                // Blurred and desaturated like the gallery while the detail
                // card is open; the stage in `detailCardLayer` dims it
                // and swallows its clicks.
                .blur(radius: sidebarSelectionContext == .trash ? 0 : galleryBlurRadius)
                .saturation(selectedSnippet == nil || sidebarSelectionContext == .trash ? 1.0 : 0.95)
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
                    // Only the expanded preview softens the backdrop too; the
                    // ordinary detail card leaves the dot grid crisp.
                    .blur(radius: isPreviewExpanded ? Self.expandedBackdropBlur : 0)

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
                            showUncategorizedOnly: uncategorizedOnlyBinding,
                            availableLanguages: availableLanguages,
                            availableCollections: collections,
                            subcollections: gallerySubcollections,
                            onSelect: { snippet in
                                // Only from fully closed: re-opening a card
                                // that is still shrinking keeps the anchor it
                                // is shrinking towards, or it would jump to
                                // the new click point mid-flight.
                                if presentedSnippetID == nil {
                                    detailOrigin = Self.clickLocationInWindow()
                                    morphSource = DetailMotionTuning.shared.values.morph
                                        ? cardGeometry.entries[snippet.persistentModelID]
                                        : nil
                                }
                                // No `withAnimation`: the stage animates the
                                // open in Core Animation. A SwiftUI animation
                                // running alongside makes every glass element
                                // in the window refresh each frame.
                                selectedSnippetID = snippet.persistentModelID
                                if let colID = selectedCollectionID {
                                    sidebarSelectionContext = .collection(colID)
                                } else {
                                    sidebarSelectionContext = .allSnippets
                                }
                                // Start the card in this same update, not on
                                // the next one via the selection's onChange
                                // (which then finds it already under way).
                                syncDetailPresentation(to: snippet.persistentModelID)
                            },
                            onSelectCollection: { collection in
                                withAnimation(DSToken.Motion.overlay) {
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
                                withAnimation(DSToken.Motion.overlay) {
                                    selectedSearchCollections.removeAll()
                                    showUncategorizedOnly = false
                                    uncategorizedScopeIsAutomatic = false
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
                            isDetailCardOpen: { selectedSnippetID != nil },
                            cardGeometry: cardGeometry,
                            hiddenSnippetID: morphSourceID,
                            onMoveSnippetToLibrary: { snippet in moveSnippetToLibrary(snippet) },
                            onMoveSnippetToCollection: { snippet, collection in moveSnippet(snippet, to: collection) },
                            onMoveSelection: { snippets, collections, target in
                                moveSelection(snippets: snippets, collections: collections, to: target)
                            },
                            onCopySnippetToCollection: { snippet, collection in copySnippet(snippet, to: collection) }
                        )
                        .blur(radius: galleryBlurRadius)
                        .saturation(selectedSnippet == nil ? 1.0 : 0.95)
                        .allowsHitTesting(selectedSnippet == nil)
                    }

                    // Where the detail card sits when not expanded. The card
                    // itself lives in `detailCardLayer`, above the whole split
                    // view, so that expanding can grow it over the sidebar.
                    Color.clear
                        .allowsHitTesting(false)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { frame in
                            detailFrame = frame
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
                                mode: .create(
                                    preselectedCollectionID: newSnippetPreselectedCollectionID,
                                    draftCode: newSnippetDraftCode
                                ),
                                availableCollections: collections,
                                availableSnippets: snippets,
                                onRequestDismiss: {
                                    newSnippetDraftCode = nil
                                    withAnimation(DSToken.Motion.overlay) {
                                        isPresentingNew = false
                                    }
                                },
                                onSave: { newSnippet in
                                    modelContext.insert(newSnippet)
                                    saveOrToast(modelContext)
                                    newSnippetDraftCode = nil
                                    withAnimation(DSToken.Motion.overlay) {
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
                            .transition(modalTransition)
                        }
                        .zIndex(4)
                    }

                }
                        // Closing the detail overlay (X, tap-outside, delete) ends the
                // navigation session, so drop any accumulated back history.
                .onChange(of: selectedSnippetID) { _, newValue in
                    syncDetailPresentation(to: newValue)
                    if newValue == nil {
                        snippetHistory.removeAll()
                    }
                    // Expansion belongs to one snippet's preview: opening
                    // another, or closing the card, starts from the card.
                    setPreviewExpanded(false)
                }
                .animation(DSToken.Motion.overlay, value: isPresentingNew)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    StatusBar(
                        segments: currentStatusSegments,
                        contentLeadingInset: 0
                    )
                }
            }
        }
        .overlay {
            detailCardLayer
        }
    }

    var body: some View {
        splitView
        .background(WindowChromeConfigurator())
        .task {
            performTrashCleanup()
            debouncedSearchText = searchText
            rebuildDerivedCaches()
            drainPendingWork()
        }
        .onChange(of: SnippetTransferController.shared.notice, initial: true) { _, notice in
            guard let notice else { return }
            showToast(notice.message)
            SnippetTransferController.shared.clearNotice()
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
            showUncategorizedOnly = Self.showsUncategorizedOnly(context: newValue, selectedLanguages: selectedLanguages)
            uncategorizedScopeIsAutomatic = true
            selectedSearchCollections.removeAll()
        }
        .onChange(of: selectedLanguages) { _, newValue in
            // The sidebar's language rows and its All Snippets row both stay
            // in `.allSnippets`, so they never pass through the context
            // change above; only the language set moves.
            showUncategorizedOnly = Self.showsUncategorizedOnly(
                context: sidebarSelectionContext,
                selectedLanguages: newValue,
                hasCollectionFilter: !selectedSearchCollections.isEmpty
            )
            uncategorizedScopeIsAutomatic = true
        }
        .onChange(of: navigator.pendingOpenSnippetUUID) { _, newValue in
            guard let uuid = newValue else { return }
            openPendingSnippet(uuid)
        }
        .onChange(of: navigator.pendingNewSnippet) { _, isPending in
            guard isPending else { return }
            presentNewSnippetFromIntent()
        }
        .onChange(of: CaptureDraft.shared.pending) { _, candidate in
            guard let candidate else { return }
            presentCapturedDraft(candidate)
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
        withAnimation(DSToken.Motion.overlay) {
            selectedSnippetID = nil
            isPresentingNew = true
        }
        navigator.pendingNewSnippet = false
    }

    /// Opens the snippet `OpenSnippetIntent` or the quick-copy panel asked for,
    /// clearing the request either way — an unclearable request would make every
    /// later request for the same snippet a no-op, because `onChange` fires on
    /// change and not on value.
    private func openPendingSnippet(_ uuid: UUID) {
        if let match = snippets.first(where: { $0.uuid == uuid }) {
            withAnimation(DSToken.Motion.overlay) {
                searchText = ""
                selectedCollectionID = nil
                sidebarSelectionContext = .allSnippets
                selectedSnippetID = match.persistentModelID
            }
        }
        navigator.pendingOpenSnippetUUID = nil
    }

    /// Opens the new-snippet editor seeded with captured clipboard code.
    /// Nothing is written to the store — the user still has to save.
    private func presentCapturedDraft(_ candidate: ClipboardCapture.Candidate) {
        newSnippetPreselectedCollectionID = nil
        newSnippetDraftCode = candidate.code
        withAnimation(DSToken.Motion.overlay) {
            selectedSnippetID = nil
            isPresentingNew = true
        }
        CaptureDraft.shared.pending = nil
    }

    /// Acts on work that was requested before this view existed.
    ///
    /// Two ways in: an App Intent that launched the app cold, and the menu bar
    /// panel handing off after `MainWindowOpener` had to build a fresh window.
    /// Both set their flag and return immediately, so the value is already in
    /// place by the time this view first runs its body — and `onChange` fires on
    /// a change, never on the value it started with. Without this drain the
    /// request is dropped, and because each handler is also what clears its own
    /// flag, it stays dropped: every later request for the same snippet writes
    /// the same value and changes nothing.
    private func drainPendingWork() {
        if navigator.pendingNewSnippet { presentNewSnippetFromIntent() }
        if let uuid = navigator.pendingOpenSnippetUUID { openPendingSnippet(uuid) }
        if let candidate = CaptureDraft.shared.pending { presentCapturedDraft(candidate) }
    }

    private func navigateBackFromCollection() {
        guard let id = selectedCollectionID else { return }
        let parentID = parentCollectionID(for: id)

        withAnimation(DSToken.Motion.overlay) {
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
        withAnimation(DSToken.Motion.toastIn) { activeToast = Toast(message: message, showsUndo: showsUndo) }
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
                context: modelContext,
                forgetTrust: { previewTrust.forget($0) }
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
                TrashLifecycle.purgeSnippet(
                    snippet,
                    context: modelContext,
                    forgetTrust: { previewTrust.forget($0) }
                )
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
            withAnimation(DSToken.Motion.toastOut) { activeToast = nil }
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

/// Pure filter core for the gallery — plain functions of inputs to outputs,
/// no SwiftUI or view state, so the predicates are directly unit-testable.
/// Predicate logic moved verbatim from the former computed properties.
@MainActor
enum GallerySnippetFilter {
    static func base(
        snippets: [Snippet],
        selectedLanguages: Set<SupportedLanguage>,
        selectedCollectionID: PersistentIdentifier?,
        showUncategorizedOnly: Bool,
        selectedSearchCollections: Set<PersistentIdentifier>,
        showFavoritesOnly: Bool,
        lookup: [PersistentIdentifier: SnippetCollection],
        descendantIDs: [PersistentIdentifier: Set<PersistentIdentifier>]
    ) -> [Snippet] {
        snippets.filter { snippet in
            if !selectedLanguages.isEmpty, !selectedLanguages.contains(SupportedLanguage(stored: snippet.language)) { return false }

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

    static func searchPool(
        snippets: [Snippet],
        selectedLanguages: Set<SupportedLanguage>,
        showUncategorizedOnly: Bool,
        selectedSearchCollections: Set<PersistentIdentifier>,
        showFavoritesOnly: Bool,
        lookup: [PersistentIdentifier: SnippetCollection],
        descendantIDs: [PersistentIdentifier: Set<PersistentIdentifier>]
    ) -> [Snippet] {
        snippets.filter { snippet in
            if !selectedLanguages.isEmpty, !selectedLanguages.contains(SupportedLanguage(stored: snippet.language)) { return false }

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

    static func searchResults(in pool: [Snippet], needle: String) -> [Snippet] {
        let terms = SnippetSearch.terms(needle)
        guard !terms.isEmpty else { return [] }

        return pool.filter { snippet in
            let collectionNames = snippet.collections.compactMap { $0.isDeleted ? nil : $0.name }
            return SnippetSearch.matches(
                terms: terms,
                in: [snippet.title, snippet.snippetDescription, snippet.code, snippet.language] + collectionNames
            )
        }
    }

    static func searchCollections(
        _ collections: [SnippetCollection], needle: String, showFavoritesOnly: Bool
    ) -> [SnippetCollection] {
        let terms = SnippetSearch.terms(needle)
        guard !terms.isEmpty else { return [] }

        return collections.filter { collection in
            !collection.isDeleted &&
            (!showFavoritesOnly || collection.isFavorite) &&
            SnippetSearch.matches(terms: terms, in: [collection.name])
        }
    }
}

/// Hard-delete operations shared by the Trash cleanup and permanent collection
/// delete flows. Context-injected so the logic is testable outside the view.
@MainActor
enum TrashLifecycle {
    /// Hard-deletes a snippet: removes media files from disk, drops any preview
    /// consent recorded for it, then deletes the model.
    ///
    /// `forgetTrust` is `PreviewTrust.forget` at the call sites that have one.
    /// It is a parameter rather than a global because this type is
    /// context-injected precisely so it stays testable outside a view, and the
    /// object being reached for is the one that gates code execution and
    /// network egress — the last one that should become ambient state.
    ///
    /// It fires *before* the delete, deliberately: reading `snippet.uuid` off a
    /// model the context has already deleted is reading an invalidated object.
    static func purgeSnippet(
        _ snippet: Snippet,
        context: ModelContext,
        forgetTrust: (@MainActor (UUID?) -> Void)? = nil
    ) {
        forgetTrust?(snippet.uuid)
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
        context: ModelContext,
        forgetTrust: (@MainActor (UUID?) -> Void)? = nil
    ) throws {
        for snippet in snippets {
            if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
                purgeSnippet(snippet, context: context, forgetTrust: forgetTrust)
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



# Liquid Glass Modals & Full-Screen Titlebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Move-to popup, the New/Edit Collection sheet, and the full-screen window titlebar consistent with the app's existing Liquid Glass design language, and standardize on native liquid glass toggle switches.

**Architecture:** No new visual primitives. Everything reuses the app's existing glass vocabulary (`liquidGlassSurface`, `DSGlassContainer`, `Theme`, the floating-card-over-dimmed-backdrop pattern already used by `SnippetDetailView`/`SnippetEditorView`). The Move-to popup moves from a native `.sheet()` to an in-window overlay card; the Collection editor keeps its `.sheet()` presentation but drops its native `NavigationStack`/`.toolbar` chrome for a hand-built glass header; the full-screen titlebar fix is a two-line AppKit change; two unused fake-glass toggle styles are deleted in favor of the native `.switch` style already used once in the codebase.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, AppKit interop (`NSViewRepresentable`), XCTest (existing `SnippetsTests` target). macOS 26+ deployment target (see Global Constraints).

## Global Constraints

- Deployment target is macOS 26+ (`Package.swift`: `platforms: [.macOS(.v26)]`) — the real `glassEffect` API is always available at runtime, but keep using the existing `#available(macOS 26.0, *)` guard pattern inside `DSGlassModifier`/`DSGlassContainer` for consistency with the rest of the codebase; do not add new unguarded `.glassEffect()` calls outside those two files.
- Reuse existing primitives only: `liquidGlassSurface(in:tint:interactive:borderOpacity:shadowRadius:shadowY:)`, `DSGlassContainer`, `Theme.current(colorScheme)`. Do not introduce new glass modifiers.
- This codebase has no SwiftUI view-rendering tests — only view-model / pure-logic unit tests exist (`Tests/SnippetsTests/*ViewModelTests.swift`). Follow that convention: pure logic gets XCTest coverage; view/chrome changes are verified by building and manually running the app (no fake snapshot/UI tests).
- Native system controls (e.g. `Toggle().toggleStyle(.switch)`) are the standard "liquid glass" toggle going forward — they inherit real Liquid Glass automatically on macOS 26. Do not hand-roll new glass toggle styles.
- Frequent, small commits — one commit per task (or per logical step group within a task), following the repo's existing commit style (short imperative subject line).

---

## Task 1: Fix opaque full-screen titlebar

**Files:**
- Modify: `Sources/Snippets/SnippetsApp.swift:47-61`

**Interfaces:**
- Consumes: nothing (self-contained AppKit change).
- Produces: nothing consumed by later tasks (independent).

- [ ] **Step 1: Apply the transparency fix**

In `Sources/Snippets/SnippetsApp.swift`, find `WindowChromeConfigurator.ChromeView.applyChrome()`:

```swift
        @objc private func applyChrome() {
            guard let window = configuredWindow else { return }
            window.titleVisibility = .hidden

            // Make the green button offer real full screen (arrows) instead
            // of plain zoom ("+"): the window must advertise that it can be
            // a primary full-screen window.
            window.collectionBehavior.insert(.fullScreenPrimary)

            let isFullScreen = window.styleMask.contains(.fullScreen)
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for type in buttons {
                window.standardWindowButton(type)?.alphaValue = isFullScreen ? 0 : 1
            }
        }
```

Replace it with:

```swift
        @objc private func applyChrome() {
            guard let window = configuredWindow else { return }
            window.titleVisibility = .hidden

            // Match windowed mode's translucent chrome in full screen too:
            // without this, the full-screen auto-hide titlebar strip falls
            // back to the OS's default opaque titlebar material, because it's
            // a separate AppKit-drawn surface that SwiftUI's
            // .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // (used in SnippetsApp's body) doesn't reach.
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            // Make the green button offer real full screen (arrows) instead
            // of plain zoom ("+"): the window must advertise that it can be
            // a primary full-screen window.
            window.collectionBehavior.insert(.fullScreenPrimary)

            let isFullScreen = window.styleMask.contains(.fullScreen)
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for type in buttons {
                window.standardWindowButton(type)?.alphaValue = isFullScreen ? 0 : 1
            }
        }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds with no errors or new warnings.

- [ ] **Step 3: Manual verification**

Run: `swift run Snippets` (or open `Snippets.xcodeproj` in Xcode and Run).

Checklist:
- Windowed mode: titlebar area still looks the same as before this change (translucent, no visible title text, traffic lights visible).
- Enter full screen (green button, or Control-Command-F): the top auto-hide strip should now be translucent/glassy (matching the app's own glass bars) instead of an opaque gray/black bar when it reveals itself.
- Traffic lights are still hidden while in full screen and reappear correctly when exiting full screen.
- Resize the window in windowed mode: no visual regression in the toolbar/search-bar area.

- [ ] **Step 4: Commit**

```bash
git add Sources/Snippets/SnippetsApp.swift
git commit -m "$(cat <<'EOF'
Fix opaque titlebar in full-screen mode

titlebarAppearsTransparent was never set, so the full-screen auto-hide
titlebar strip fell back to the OS's default opaque material even
though windowed mode already fakes translucency via toolbar background
hiding.
EOF
)"
```

---

## Task 2: Delete unused fake-glass toggle styles

**Files:**
- Delete: `Sources/Snippets/DesignSystem/Components/DSToggle.swift`
- Delete: `Sources/Snippets/Views/Components/LiquidGlassToggleStyle.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing consumed by later tasks (independent cleanup — confirmed via grep that neither `DSToggle` nor `LiquidGlassToggleStyle`/`.liquidGlass(tint:)` is referenced anywhere outside their own files' `#Preview` blocks).

- [ ] **Step 1: Confirm there are no external references**

Run: `grep -rn "DSToggle\|LiquidGlassToggleStyle\|\.liquidGlass(" Sources --include="*.swift"`
Expected output: only matches inside `Sources/Snippets/DesignSystem/Components/DSToggle.swift` and `Sources/Snippets/Views/Components/LiquidGlassToggleStyle.swift` themselves.

- [ ] **Step 2: Delete the files**

```bash
rm Sources/Snippets/DesignSystem/Components/DSToggle.swift
rm Sources/Snippets/Views/Components/LiquidGlassToggleStyle.swift
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: Build succeeds — no references were broken (confirmed by Step 1).

- [ ] **Step 4: Commit**

```bash
git add -A Sources/Snippets/DesignSystem/Components/DSToggle.swift Sources/Snippets/Views/Components/LiquidGlassToggleStyle.swift
git commit -m "$(cat <<'EOF'
Remove unused fake-glass toggle styles

Neither DSToggle nor LiquidGlassToggleStyle was referenced outside its
own preview. Both hand-drew a flat capsule pretending to be glass;
native Toggle().toggleStyle(.switch) (already used for the
Sub-Collection toggle) inherits real Liquid Glass automatically on
macOS 26 and is strictly better.
EOF
)"
```

---

## Task 3: Extract and test collection hierarchy/search logic

**Files:**
- Create: `Sources/Snippets/Features/Gallery/CollectionMoveTree.swift`
- Test: `Tests/SnippetsTests/CollectionMoveTreeTests.swift`

**Interfaces:**
- Consumes: `SnippetCollection` (existing model, `Sources/Snippets/Models/Collection.swift`) — uses only `.persistentModelID`, `.name`, `.parent`.
- Produces (consumed by Task 4):
  - `struct CollectionMoveRow: Identifiable { let collection: SnippetCollection; let depth: Int; var id: PersistentIdentifier }`
  - `enum MoveCollectionTree { static func rows(from collections: [SnippetCollection]) -> [CollectionMoveRow]; static func searchRows(from collections: [SnippetCollection], matching query: String) -> [CollectionMoveRow] }`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SnippetsTests/CollectionMoveTreeTests.swift`:

```swift
import XCTest
@testable import Snippets

@MainActor
final class CollectionMoveTreeTests: XCTestCase {
    func test_rows_whenCollectionsAreFlat_returnsThemAtDepthZeroInInputOrder() {
        let work = SnippetCollection(name: "Work")
        let personal = SnippetCollection(name: "Personal")

        let rows = MoveCollectionTree.rows(from: [work, personal])

        XCTAssertEqual(rows.map { $0.collection.name }, ["Work", "Personal"])
        XCTAssertEqual(rows.map(\.depth), [0, 0])
    }

    func test_rows_whenCollectionHasChildPresentInList_nestsChildDirectlyAfterParent() {
        let work = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: work)
        let personal = SnippetCollection(name: "Personal")

        let rows = MoveCollectionTree.rows(from: [work, archived, personal])

        XCTAssertEqual(rows.map { $0.collection.name }, ["Work", "Archived", "Personal"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
    }

    func test_rows_whenChildsParentIsNotInList_treatsChildAsTopLevel() {
        let outsideParent = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: outsideParent)

        let rows = MoveCollectionTree.rows(from: [archived])

        XCTAssertEqual(rows.map { $0.collection.name }, ["Archived"])
        XCTAssertEqual(rows.map(\.depth), [0])
    }

    func test_searchRows_whenQueryMatchesSubstring_returnsFlatMatchesCaseInsensitively() {
        let work = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: work)
        let personal = SnippetCollection(name: "Personal")

        let rows = MoveCollectionTree.searchRows(from: [work, archived, personal], matching: "ARCH")

        XCTAssertEqual(rows.map { $0.collection.name }, ["Archived"])
        XCTAssertEqual(rows.map(\.depth), [0])
    }

    func test_searchRows_whenQueryIsBlank_returnsFullHierarchy() {
        let work = SnippetCollection(name: "Work")
        let archived = SnippetCollection(name: "Archived", parent: work)

        let rows = MoveCollectionTree.searchRows(from: [work, archived], matching: "   ")

        XCTAssertEqual(rows.map { $0.collection.name }, ["Work", "Archived"])
        XCTAssertEqual(rows.map(\.depth), [0, 1])
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CollectionMoveTreeTests`
Expected: FAIL to compile — `MoveCollectionTree` and `CollectionMoveRow` don't exist yet.

- [ ] **Step 3: Write the implementation**

Create `Sources/Snippets/Features/Gallery/CollectionMoveTree.swift`:

```swift
import SwiftData

/// A single row in the Move-to popup's collection list: the collection to
/// show plus how deeply it's nested under its parent (0 = top level).
struct CollectionMoveRow: Identifiable {
    let collection: SnippetCollection
    let depth: Int

    var id: PersistentIdentifier { collection.persistentModelID }
}

/// Builds the display order for the Move-to popup's collection list out of
/// an already-filtered flat list of valid move targets.
enum MoveCollectionTree {
    /// Orders `collections` depth-first: a collection whose parent is absent
    /// from `collections` (nil, or filtered out as an invalid target) is
    /// treated as top level; each collection is immediately followed by its
    /// children that are present in `collections`. Every input collection
    /// appears exactly once, in `collections`' relative order at each level.
    static func rows(from collections: [SnippetCollection]) -> [CollectionMoveRow] {
        let presentIDs = Set(collections.map(\.persistentModelID))
        let roots = collections.filter { collection in
            guard let parentID = collection.parent?.persistentModelID else { return true }
            return !presentIDs.contains(parentID)
        }

        var visited = Set<PersistentIdentifier>()
        var result: [CollectionMoveRow] = []
        for root in roots {
            appendSubtree(root, depth: 0, collections: collections, visited: &visited, into: &result)
        }
        return result
    }

    /// Flat (depth 0), case-insensitive substring match against `query`.
    /// Falls back to the full hierarchy when `query` is blank.
    static func searchRows(from collections: [SnippetCollection], matching query: String) -> [CollectionMoveRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return rows(from: collections) }
        return collections
            .filter { $0.name.lowercased().contains(needle) }
            .map { CollectionMoveRow(collection: $0, depth: 0) }
    }

    private static func appendSubtree(
        _ collection: SnippetCollection,
        depth: Int,
        collections: [SnippetCollection],
        visited: inout Set<PersistentIdentifier>,
        into result: inout [CollectionMoveRow]
    ) {
        let id = collection.persistentModelID
        guard !visited.contains(id) else { return }
        visited.insert(id)
        result.append(CollectionMoveRow(collection: collection, depth: depth))

        let children = collections.filter { $0.parent?.persistentModelID == id }
        for child in children {
            appendSubtree(child, depth: depth + 1, collections: collections, visited: &visited, into: &result)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CollectionMoveTreeTests`
Expected: PASS — all 5 tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Snippets/Features/Gallery/CollectionMoveTree.swift Tests/SnippetsTests/CollectionMoveTreeTests.swift
git commit -m "$(cat <<'EOF'
Add CollectionMoveTree for hierarchical/searchable move targets

Pure, tested logic that turns a flat list of valid move targets into
depth-first display rows (nesting subcollections under their parent)
or a flat search-filtered list. No view code yet — used by the
redesigned Move-to popup in the next task.
EOF
)"
```

---

## Task 4: Replace Move-to sheet with in-window glass card

**Files:**
- Modify: `Sources/Snippets/Views/SnippetGalleryView.swift:257-266` (ZStack content — add overlay)
- Modify: `Sources/Snippets/Views/SnippetGalleryView.swift:307-380` (remove `.sheet`, add derived-data properties + overlay)
- Modify: `Sources/Snippets/Views/SnippetGalleryView.swift:1358-1456` (replace `MoveToCollectionSheet` with `MoveToCollectionCard`)

**Interfaces:**
- Consumes: `CollectionMoveRow`, `MoveCollectionTree.rows(from:)`, `MoveCollectionTree.searchRows(from:matching:)` (Task 3); `SnippetCollection.displayColor`, `SnippetCollection.displayIconName` (existing, `Sources/Snippets/Views/Components/CollectionIconView.swift`); `liquidGlassSurface`, `DSGlassContainer`, `Theme` (existing).
- Produces: nothing consumed by later tasks (Task 5 and Task 6 don't depend on this).

- [ ] **Step 1: Add the overlay to the gallery's root ZStack**

In `Sources/Snippets/Views/SnippetGalleryView.swift`, find (inside `var body`, right after the `ScrollView` that has the `topBar` safe-area inset):

```swift
            fab
                .padding(.trailing, 32)
                .padding(.bottom, 24)

            #if canImport(AppKit)
            deletionDisintegrationLayer
                .allowsHitTesting(false)
                .zIndex(8)
            #endif
        }
```

Replace with:

```swift
            fab
                .padding(.trailing, 32)
                .padding(.bottom, 24)

            #if canImport(AppKit)
            deletionDisintegrationLayer
                .allowsHitTesting(false)
                .zIndex(8)
            #endif

            if showMoveSheet {
                moveToCollectionOverlay
                    .zIndex(9)
            }
        }
```

- [ ] **Step 2: Remove the `.sheet` modifier, add derived-data properties and the overlay**

Find (the tail end of `var body`'s modifier chain, right after `.onDisappear`):

```swift
        .onDisappear {
            #if canImport(AppKit)
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
            for task in deletionCleanupTasks.values {
                task.cancel()
            }
            deletionCleanupTasks.removeAll()
            #endif
            pressedResetTask?.cancel()
        }
        .sheet(isPresented: $showMoveSheet) {
            let selectedSnippets = viewModel.selectedSnippets(from: snippets)
            let selectedCollections = viewModel.selectedCollections(from: subcollections)
            
            let filteredCollections = availableCollections.filter { target in
                if selectedCollections.contains(where: { $0.persistentModelID == target.persistentModelID }) {
                    return false
                }
                
                let hasSnippetInTarget = selectedSnippets.contains(where: { snip in
                    snip.collections.contains(where: { $0.persistentModelID == target.persistentModelID })
                })
                if hasSnippetInTarget {
                    return false
                }
                
                let hasCollectionInTarget = selectedCollections.contains(where: { coll in
                    coll.parent?.persistentModelID == target.persistentModelID
                })
                if hasCollectionInTarget {
                    return false
                }
                
                return true
            }

            let allSnippetsInCollections = selectedSnippets.isEmpty ? true : selectedSnippets.allSatisfy { !$0.collections.isEmpty }
            let allCollectionsAreSubcollections = selectedCollections.isEmpty ? true : selectedCollections.allSatisfy { $0.parent != nil }
            let hasAnySelection = !selectedSnippets.isEmpty || !selectedCollections.isEmpty
            
            let showLibraryOption = hasAnySelection && allSnippetsInCollections && allCollectionsAreSubcollections

            MoveToCollectionSheet(
                collections: filteredCollections,
                showLibraryOption: showLibraryOption,
                onMove: { collection in
                    if let target = collection {
                        for snippet in selectedSnippets {
                            onMoveSnippetToCollection?(snippet, target)
                        }
                        for coll in selectedCollections {
                            onMoveCollectionToCollection?(coll, target)
                        }
                    } else {
                        for snippet in selectedSnippets {
                            onMoveSnippetToLibrary?(snippet)
                        }
                        for coll in selectedCollections {
                            onMoveCollectionToLibrary?(coll)
                        }
                    }
                    withAnimation {
                        viewModel.clearSelectionAndExitSelectMode()
                    }
                    showMoveSheet = false
                },
                onCancel: { showMoveSheet = false }
            )
        }
    }
```

Replace with:

```swift
        .onDisappear {
            #if canImport(AppKit)
            if let keyEventMonitor {
                NSEvent.removeMonitor(keyEventMonitor)
                self.keyEventMonitor = nil
            }
            for task in deletionCleanupTasks.values {
                task.cancel()
            }
            deletionCleanupTasks.removeAll()
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

    private var moveTargetCollections: [SnippetCollection] {
        let selectedSnippets = selectedSnippetsForMove
        let selectedCollections = selectedCollectionsForMove

        return availableCollections.filter { target in
            if selectedCollections.contains(where: { $0.persistentModelID == target.persistentModelID }) {
                return false
            }

            let hasSnippetInTarget = selectedSnippets.contains(where: { snip in
                snip.collections.contains(where: { $0.persistentModelID == target.persistentModelID })
            })
            if hasSnippetInTarget {
                return false
            }

            let hasCollectionInTarget = selectedCollections.contains(where: { coll in
                coll.parent?.persistentModelID == target.persistentModelID
            })
            if hasCollectionInTarget {
                return false
            }

            return true
        }
    }

    private var moveShowsLibraryOption: Bool {
        let selectedSnippets = selectedSnippetsForMove
        let selectedCollections = selectedCollectionsForMove
        let allSnippetsInCollections = selectedSnippets.isEmpty ? true : selectedSnippets.allSatisfy { !$0.collections.isEmpty }
        let allCollectionsAreSubcollections = selectedCollections.isEmpty ? true : selectedCollections.allSatisfy { $0.parent != nil }
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
                collections: moveTargetCollections,
                showLibraryOption: moveShowsLibraryOption,
                itemCount: selectedSnippets.count + selectedCollections.count,
                onMove: { collection in
                    if let target = collection {
                        for snippet in selectedSnippets {
                            onMoveSnippetToCollection?(snippet, target)
                        }
                        for coll in selectedCollections {
                            onMoveCollectionToCollection?(coll, target)
                        }
                    } else {
                        for snippet in selectedSnippets {
                            onMoveSnippetToLibrary?(snippet)
                        }
                        for coll in selectedCollections {
                            onMoveCollectionToLibrary?(coll)
                        }
                    }
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
```

- [ ] **Step 3: Replace `MoveToCollectionSheet` with `MoveToCollectionCard`**

Find the private struct at the end of the file:

```swift
private struct MoveToCollectionSheet: View {
    @Environment(\.colorScheme) private var colorScheme
    let collections: [SnippetCollection]
    let showLibraryOption: Bool
    let onMove: (SnippetCollection?) -> Void
    let onCancel: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                DSGlassContainer(spacing: 0) {
                    VStack(spacing: 0) {
                        if showLibraryOption {
                            Button(action: { onMove(nil) }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "square.grid.2x2")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 24, height: 24)

                                    Text("All Snippets")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if !collections.isEmpty {
                                Rectangle()
                                    .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.34))
                                    .frame(height: 1)
                            }
                        }

                        ForEach(Array(collections.enumerated()), id: \.element.persistentModelID) { index, collection in
                            Button(action: { onMove(collection) }) {
                                HStack(spacing: 12) {
                                    let color = Color(hex: collection.colorHex) ?? theme.accent
                                    Image(systemName: SnippetCollection.isValidSFSymbolName(collection.iconName) ? collection.iconName : SnippetCollection.defaultIconName)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(color)
                                        .frame(width: 24, height: 24)

                                    Text(collection.name)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.secondary.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < collections.count - 1 {
                                Rectangle()
                                    .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.34))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .padding(DSToken.Spacing.lg)
            }
            .background {
                ZStack {
                    Color.clear.ignoresSafeArea()
                    DotGridBackground(gradientPalette: [theme.accent], lightModeStrength: 0.5)
                        .opacity(colorScheme == .dark ? 0.12 : 0.10)
                        .ignoresSafeArea()
                }
            }
            .navigationTitle("Move to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .frame(width: 380)
        .frame(minHeight: 400)
    }
}
```

Replace with:

```swift
private struct MoveToCollectionCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let collections: [SnippetCollection]
    let showLibraryOption: Bool
    let itemCount: Int
    let onMove: (SnippetCollection?) -> Void
    let onCancel: () -> Void

    @State private var searchText: String = ""

    private var theme: Theme { Theme.current(colorScheme) }

    private var rows: [CollectionMoveRow] {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? MoveCollectionTree.rows(from: collections)
            : MoveCollectionTree.searchRows(from: collections, matching: searchText)
    }

    private var titleText: String {
        itemCount == 1 ? "Move 1 Item" : "Move \(itemCount) Items"
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            DSGlassContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(titleText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.text)

                    searchField

                    ScrollView {
                        VStack(spacing: 0) {
                            if showLibraryOption {
                                libraryRow
                                if !rows.isEmpty {
                                    divider
                                }
                            }

                            if rows.isEmpty {
                                Text("No matching collections")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
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
            .padding(.top, 14)
            .padding(.trailing, 14)
            .accessibilityLabel("Close")
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
            TextField("Search collections", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(colorScheme == .dark ? 0.08 : 0.2), lineWidth: 1)
                }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(colorScheme == .dark ? 0.12 : 0.34))
            .frame(height: 1)
    }

    private var libraryRow: some View {
        Button(action: { onMove(nil) }) {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 24, height: 24)

                Text("All Snippets")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func collectionRow(_ row: CollectionMoveRow) -> some View {
        let collection = row.collection
        return Button(action: { onMove(collection) }) {
            HStack(spacing: 12) {
                Image(systemName: collection.displayIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(collection.displayColor)
                    .frame(width: 24, height: 24)

                Text(collection.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
            .padding(.leading, 16 + CGFloat(row.depth) * 20)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: Build succeeds. If it fails on an unrelated `MoveToCollectionSheet` reference, search for it (`grep -rn "MoveToCollectionSheet" Sources`) — there should be none left outside this file, since it was `private` and only used within `SnippetGalleryView.swift`.

- [ ] **Step 5: Manual verification**

Run: `swift run Snippets`.

Checklist:
- Select multiple snippets/collections (select mode), tap "move (N)": a dimmed backdrop + centered glass card appears with a spring animation, titled "Move N Items".
- Card shows "All Snippets" pinned at top (when eligible), then collections with any subcollections visibly indented beneath their parent.
- Typing in the search field filters the list to name matches (flat, no indentation); clearing the search restores the hierarchy.
- Clicking a row actually moves the selected snippet(s)/collection(s) and dismisses the card.
- Clicking the "×" button, or clicking the dimmed backdrop, dismisses the card without moving anything.
- Try moving a single snippet via the sidebar/card-level "Move to" context menu (the plain system `Menu`, unaffected by this change) still works — confirms the two "move" affordances didn't get tangled.

- [ ] **Step 6: Commit**

```bash
git add Sources/Snippets/Views/SnippetGalleryView.swift
git commit -m "$(cat <<'EOF'
Replace Move-to sheet with in-window glass card

Matches the app's existing modal pattern (dimmed backdrop + floating
glass card, as used for snippet detail/edit) instead of a native
.sheet() with system NavigationStack/toolbar chrome. Adds a search
field and hierarchical (indented) subcollection display, backed by
the new CollectionMoveTree.
EOF
)"
```

---

## Task 5: De-chrome the Collection editor sheet

**Files:**
- Modify: `Sources/Snippets/Views/Sidebar/CollectionEditorSheet.swift:284-326`

**Interfaces:**
- Consumes: existing `title`, `previewIconName`, `canSave`, `activeColor`, `onCancel`, `onSave`, `theme` (all already defined earlier in the same file — unchanged by this task).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Replace `NavigationStack`/`.toolbar` with a custom glass header**

In `Sources/Snippets/Views/Sidebar/CollectionEditorSheet.swift`, find:

```swift
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    DSGlassContainer(spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        glassPreviewHeader
                        glassColorStrip

                        glassContrastWarning
                        
                        glassSubcollectionToggleSection
                        glassSnippetMembershipSection
                        glassSymbolBrowser
                    }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                }
            }
            .background {
                ZStack {
                    Color.clear.ignoresSafeArea()
                    DotGridBackground(gradientPalette: [activeColor], lightModeStrength: 0.5)
                        .opacity(colorScheme == .dark ? 0.12 : 0.10)
                        .ignoresSafeArea()
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
                        .tint(activeColor)
                }
            }
        }
        .frame(width: 480, height: 640)
    }
```

Replace with:

```swift
    var body: some View {
        VStack(spacing: 0) {
            editorHeader

            ScrollView {
                DSGlassContainer(spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        glassPreviewHeader
                        glassColorStrip

                        glassContrastWarning

                        glassSubcollectionToggleSection
                        glassSnippetMembershipSection
                        glassSymbolBrowser
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
            }
        }
        .background {
            ZStack {
                Color.clear.ignoresSafeArea()
                DotGridBackground(gradientPalette: [activeColor], lightModeStrength: 0.5)
                    .opacity(colorScheme == .dark ? 0.12 : 0.10)
                    .ignoresSafeArea()
            }
        }
        .frame(width: 480, height: 640)
    }

    // MARK: - Liquid Glass Header

    private var editorHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: previewIconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(activeColor)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.text)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                tint: activeColor.opacity(0.1),
                shadowRadius: 4,
                shadowY: 2
            )

            Spacer(minLength: 8)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                interactive: true,
                shadowRadius: 4,
                shadowY: 2
            )
            .keyboardShortcut(.cancelAction)

            Button(action: onSave) {
                Text("Save")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canSave ? .white : theme.textFaint)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(canSave ? activeColor : Color.clear)
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                tint: canSave ? activeColor.opacity(0.2) : nil,
                interactive: true,
                shadowRadius: 4,
                shadowY: 2
            )
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: Build succeeds.

- [ ] **Step 3: Manual verification**

Run: `swift run Snippets`.

Checklist:
- "New Collection" (⌘⇧N or sidebar toolbar button): sheet opens with a glass header (icon + "New Collection" badge, Cancel, Save) instead of the old native sheet toolbar. No visible native title bar strip above the badge/buttons.
- Save is visually dimmed and disabled until a name + valid icon are set; once valid, it's tinted with the selected collection color.
- Pressing Return/⌘Return triggers Save when enabled; pressing Escape triggers Cancel.
- Edit an existing collection: header shows "Edit Collection" and the collection's current icon/color; all five sections below (preview header, color strip, contrast warning if applicable, Sub-Collection toggle, Snippets membership, symbol browser) still work exactly as before.
- The Sub-Collection toggle still renders as a native switch and toggles correctly.

- [ ] **Step 4: Commit**

```bash
git add Sources/Snippets/Views/Sidebar/CollectionEditorSheet.swift
git commit -m "$(cat <<'EOF'
De-chrome Collection editor sheet with a custom glass header

Removes NavigationStack/.navigationTitle/.toolbar, which rendered the
OS's generic opaque sheet toolbar directly above already-glassy
content. Replaces it with a hand-built header (icon badge, Cancel,
Save) using the same liquidGlassSurface recipe as the snippet editor's
header. The five existing sections are unchanged.
EOF
)"
```

---

## Task 6: Final integration verification

**Files:** none (verification only).

**Interfaces:**
- Consumes: all previous tasks' output.
- Produces: nothing (terminal task).

- [ ] **Step 1: Full build and test suite**

Run: `swift build && swift test`
Expected: Build succeeds; all tests pass, including the 5 new `CollectionMoveTreeTests` and the pre-existing `SnippetEditorViewModelTests`/`SnippetGalleryViewModelTests`.

- [ ] **Step 2: Run the app and walk the full checklist in one session**

Run: `swift run Snippets`.

Checklist (combines all tasks' manual checks in a single pass, since they interact in the same window):
1. Toggle full screen on and off a few times — titlebar strip stays translucent in both states, traffic lights hide/show correctly.
2. Create a new collection with a subcollection parent set — confirm the new glass header, Save enabling/disabling, and the Sub-Collection toggle all work together.
3. From the gallery, select several snippets and a subcollection, click "move (N)" — confirm the glass card shows the right count, hierarchy, and search; move them; confirm they landed in the right place.
4. Repeat the move flow once with zero eligible collections (e.g. a brand-new library with only "All Snippets" available) — confirm the "No matching collections" / library-only states render sensibly, not blank or broken.
5. Confirm no build warnings reference `DSToggle` or `LiquidGlassToggleStyle`.

- [ ] **Step 3: Review the diff**

Run: `git log --oneline -6` and `git diff main...HEAD --stat` (or the appropriate base branch) to confirm only the expected files changed across the 5 commits.

- [ ] **Step 4: Report completion**

No commit for this task — it's a verification pass. If all checks pass, the plan is complete. If something fails, fix it as part of the task where it was introduced (amend that task's work, don't bolt a fix onto Task 6).

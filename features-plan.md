# Feature Implementation Plan — Snippets macOS App

## Quick Reference

| # | Feature | Files | Depends on |
|---|---------|-------|-----------|
| F1 | Favorites tab (sidebar + filter tag) | `Snippet.swift`, `ContentView.swift`, `SnippetGalleryView.swift`, `SnippetCard.swift`, `SnippetDetailView.swift` | — |
| F2 | Select-mode move + collection sort | `SnippetGalleryView.swift`, `ContentView.swift` | — |
| F3 | Cancel-with-data confirmation dialog | `SnippetEditorView.swift` | — |
| F4 | Click-outside dismisses creation sheet | `ContentView.swift`, `SnippetEditorView.swift` | F3 |
| F5 | Full-row tap to collapse sidebar sections | `ContentView.swift` | — |
| F6 | Auto-select collection on new snippet | `ContentView.swift`, `SnippetEditorView.swift` | — |

---

## Codebase Orientation (read before starting)

- **`Snippet.swift`** — `@Model` with `title`, `code`, `language`, `copyCount`, `collections: [SnippetCollection]`, `mediaItems`.
- **`ContentView.swift`** — Root view. Owns all `@State` including `selectedCollectionID`, `isPresentingNew`, `sidebarSelectionContext`. Sidebar branches on `#available(macOS 26.0, *)` → `ModernSidebar` or `legacySidebar`.
- **`SnippetGalleryView.swift`** — Receives `snippets`, `availableLanguages`, `selectedLanguage: Binding`, callbacks. Contains `FilterTag` (private struct at bottom of file), `filterBar` (horizontal scroll of `FilterTag`s), `topBar` (sticky header), `snippetGrid`.
- **`SnippetEditorView.swift`** — Sheet-presented via `ContentView.$isPresentingNew`. Has `mode: .create | .edit(Snippet)`, `@State selectedCollectionIDs`, `canSave` computed property. Cancel button calls `dismiss()` directly (no guard).
- **`legacySidebar`** uses manual `DisclosureGroup(isExpanded: $bool)` for each section. All sections are in `ContentView` as `private var` computed properties.

---

## F1 — Favorites Tab

### 1.1 · `Snippet.swift` — Add `isFavorite` property

Add after `var copyCount: Int = 0`:
```swift
var isFavorite: Bool = false
```
SwiftData will lightweight-migrate existing rows to `false`. No migration plan needed.

---

### 1.2 · `ContentView.swift` — Wire favorites through the whole view

#### A. Add state
```swift
@State private var isFavoritesSectionExpanded: Bool = true
@State private var showFavoritesOnly: Bool = false
```

#### B. Update `baseFilteredSnippets`
Current filtering checks `selectedLanguage` then `selectedCollectionID`. Add favorites filter after those:
```swift
private var baseFilteredSnippets: [Snippet] {
    snippets.filter { snippet in
        if let selectedLanguage, snippet.language != selectedLanguage.rawValue { return false }
        if let selectedCollectionID {
            return snippet.collections.contains(where: { $0.persistentModelID == selectedCollectionID })
        }
        if showFavoritesOnly { return snippet.isFavorite }
        return true
    }
}
```

#### C. Add `favoritesSection` computed var (mirrors pattern of `frequentlyUsedSection`)
```swift
private var favoritesSection: some View {
    let favorites = snippets.filter(\.isFavorite)
    return DisclosureGroup(isExpanded: $isFavoritesSectionExpanded) {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(favorites) { snippet in
                sidebarSnippetRow(for: snippet, context: .allSnippets)
            }
        }
        .padding(.top, 4)
    } label: {
        // Use same pattern as frequentlyUsedSection label
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.20))
            Text("favorites")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
        }
    }
}
```

#### D. Insert `favoritesSection` in `legacySidebar`

In `legacySidebar`, inside the `ScrollView > VStack`, add after `librarySection`:
```swift
if !snippets.filter(\.isFavorite).isEmpty {
    favoritesSection
}
```

#### E. Add `SidebarSelectionContext.favorites` case *(optional — only if the sidebar row should filter gallery)*

Current enum:
```swift
enum SidebarSelectionContext: Hashable {
    case frequentlyUsed
    case allSnippets
    case collection(PersistentIdentifier)
}
```
No change needed unless you want tapping a favorite row in the sidebar to filter the gallery to that snippet. The existing `.allSnippets` context works fine.

#### F. Pass `showFavoritesOnly` to `SnippetGalleryView`

Add to `SnippetGalleryView` call site (line ~156):
```swift
SnippetGalleryView(
    ...
    showFavoritesOnly: $showFavoritesOnly,       // NEW
    onToggleFavoritesFilter: {                    // NEW
        showFavoritesOnly.toggle()
    },
    ...
)
```

#### G. `ModernSidebar` (macOS 26+)

In `ModernSidebar.body`, after the "Frequently Used" `Section`, add:
```swift
if !snippets.filter(\.isFavorite).isEmpty {
    Section("Favorites") {
        ForEach(snippets.filter(\.isFavorite)) { snippet in
            let language = SupportedLanguage(rawValue: snippet.language) ?? .unknown
            let accent = Color(hex: language.accentHex) ?? .accentColor
            Label {
                Text(snippet.title.isEmpty ? "Untitled" : snippet.title).lineLimit(1)
            } icon: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.20))
            }
            .tag(Selection.snippet(snippet.persistentModelID, .allSnippets))
        }
    }
}
```

---

### 1.3 · `SnippetGalleryView.swift` — Add favorites filter tag + plumbing

#### A. New parameters
```swift
@Binding var showFavoritesOnly: Bool
let onToggleFavoritesFilter: () -> Void
```

#### B. Add favorites `FilterTag` in `filterBar`

The `filterBar` property currently shows `lang:all` then language tags. Insert the favorites tag **between** `lang:all` and the language loop:
```swift
private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
            // existing lang:all tag
            FilterTag(label: "lang:all", icon: "asterisk", accent: theme.accent, isSelected: selectedLanguage == nil) {
                selectedLanguage = nil
            }

            // NEW — favorites tag, same visual style as FilterTag
            FilterTag(
                label: "fav:starred",
                icon: "star.fill",
                accent: Color(red: 1.0, green: 0.80, blue: 0.20),
                isSelected: showFavoritesOnly
            ) {
                onToggleFavoritesFilter()
            }

            // existing language loop
            ForEach(availableLanguages) { language in ... }
        }
    }
}
```

`FilterTag` is a private struct in the same file — no changes to it needed.

---

### 1.4 · `SnippetCard.swift` — Favorite toggle button

In `SnippetCard.body`, inside the bottom `HStack` (after `copyButton`, before `Spacer`), add:
```swift
Button {
    snippet.isFavorite.toggle()
} label: {
    Image(systemName: snippet.isFavorite ? "star.fill" : "star")
        .font(Mono.font(size: 10, weight: .semibold))
        .foregroundStyle(
            snippet.isFavorite
                ? Color(red: 1.0, green: 0.80, blue: 0.20)
                : theme.textFaint
        )
}
.buttonStyle(.plain)
.help(snippet.isFavorite ? "Remove from favorites" : "Add to favorites")
```

---

### 1.5 · `SnippetDetailView.swift` — Favorite toggle in toolbar

Locate the detail view's action buttons row (near `onEdit` / `onDelete` buttons). Add a favorite toggle button in the same style, targeting `snippet.isFavorite`.

---

## F2 — Select Mode "Move" + Collection Sort

### 2.1 · `SnippetGalleryView.swift` — Select mode infrastructure

#### A. Add state
```swift
@State private var isSelectMode: Bool = false
@State private var selectedSnippetIDs: Set<PersistentIdentifier> = []
@State private var showMoveSheet: Bool = false
```

#### B. Add callback parameter
```swift
let onMoveSnippets: (Set<PersistentIdentifier>, SnippetCollection) -> Void
```

#### C. Select mode toggle button in `topBar` / `searchBar`

In the `searchBar` `HStack`, after the clear button add:
```swift
Button {
    withAnimation(.snappy(duration: 0.15)) {
        isSelectMode.toggle()
        if !isSelectMode { selectedSnippetIDs.removeAll() }
    }
} label: {
    Image(systemName: isSelectMode ? "checkmark.circle.fill" : "checkmark.circle")
        .font(Mono.font(size: 12, weight: .semibold))
        .foregroundStyle(isSelectMode ? theme.accent : theme.textFaint)
}
.buttonStyle(.plain)
.help(isSelectMode ? "Exit select mode" : "Select snippets")
```

#### D. Selection overlay per card in `snippetGrid`

In `snippetGrid`, after the existing `.overlay { GlassBreakOverlay ... }` block, add:
```swift
.overlay(alignment: .topLeading) {
    if isSelectMode {
        Image(systemName: selectedSnippetIDs.contains(snippet.persistentModelID)
              ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(selectedSnippetIDs.contains(snippet.persistentModelID)
                             ? theme.accent : theme.textFaint)
            .padding(10)
            .transition(.scale.combined(with: .opacity))
    }
}
.onTapGesture {
    if isSelectMode {
        if selectedSnippetIDs.contains(snippet.persistentModelID) {
            selectedSnippetIDs.remove(snippet.persistentModelID)
        } else {
            selectedSnippetIDs.insert(snippet.persistentModelID)
        }
        return      // don't call onSelect in select mode
    }
    onSelect(snippet)
}
```

**Important:** The existing `.simultaneousGesture(cardDragGesture(for: snippet))` must be disabled while `isSelectMode` is true to prevent accidental drag-to-trash. Wrap the gesture:
```swift
.simultaneousGesture(isSelectMode ? nil : cardDragGesture(for: snippet))
```
SwiftUI accepts `Optional<Gesture>` via `if let` in `.gesture`; use a conditional:
```swift
.gesture(isSelectMode ? AnyGesture(TapGesture().onEnded { _ in }) : AnyGesture(cardDragGesture(for: snippet)))
```
Or more simply, check `isSelectMode` inside `cardDragGesture.onChanged` and early-return.

#### E. Select mode action bar (shown at bottom when `isSelectMode && !selectedSnippetIDs.isEmpty`)

Add to the main `ZStack` in `SnippetGalleryView.body`, above `fab`:
```swift
if isSelectMode && !selectedSnippetIDs.isEmpty {
    VStack {
        Spacer()
        HStack(spacing: 14) {
            Text("\(selectedSnippetIDs.count) selected")
                .font(Mono.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Spacer()
            Button("Move to…") { showMoveSheet = true }
                .font(Mono.font(size: 12, weight: .semibold))
                .foregroundStyle(theme.accent)
                .buttonStyle(.plain)
            Button {
                // bulk delete: iterate selectedSnippetIDs and call onDelete
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.border).frame(height: 1)
        }
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
    .zIndex(10)
}
```

#### F. Move sheet

The move destination picker reuses the `CollectionEditorSheet` pattern but is read-only for collection picking. Add a simple sheet:

```swift
.sheet(isPresented: $showMoveSheet) {
    MoveToCollectionSheet(
        collections: availableCollections,      // pass as new parameter
        onMove: { collection in
            onMoveSnippets(selectedSnippetIDs, collection)
            selectedSnippetIDs.removeAll()
            isSelectMode = false
            showMoveSheet = false
        },
        onCancel: { showMoveSheet = false }
    )
}
```

**`MoveToCollectionSheet`** — new private struct in `SnippetGalleryView.swift`:
```swift
private struct MoveToCollectionSheet: View {
    let collections: [SnippetCollection]
    let onMove: (SnippetCollection) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List(collections) { collection in
                Button(collection.name) { onMove(collection) }
                    .buttonStyle(.plain)
            }
            .navigationTitle("Move to Collection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .frame(minWidth: 340, minHeight: 300)
    }
}
```

Add `let availableCollections: [SnippetCollection]` parameter to `SnippetGalleryView`.

#### G. `ContentView.swift` — Handle `onMoveSnippets` callback

Add parameter to `SnippetGalleryView` call site:
```swift
onMoveSnippets: { ids, collection in
    for snippet in snippets where ids.contains(snippet.persistentModelID) {
        moveSnippet(snippet, to: collection)
    }
},
availableCollections: collections,
```

---

### 2.2 · Collection sort order

The `@Query` on `ContentView.snippets` is already sorted by `updatedAt` descending:
```swift
@Query(sort: [SortDescriptor(\Snippet.updatedAt, order: .reverse)])
private var snippets: [Snippet]
```

`baseFilteredSnippets` filters this array, preserving order. Collection view (when `selectedCollectionID` is set) thus already shows latest first.

**If a sort-order toggle is desired** (latest ↔ oldest ↔ title), add to `ContentView`:
```swift
enum SnippetSortOrder: String, CaseIterable {
    case newestFirst = "Newest first"
    case oldestFirst = "Oldest first"
    case titleAZ     = "Title A–Z"
}
@State private var snippetSortOrder: SnippetSortOrder = .newestFirst
```

Then in `baseFilteredSnippets`, sort after filtering:
```swift
.sorted {
    switch snippetSortOrder {
    case .newestFirst: return $0.updatedAt > $1.updatedAt
    case .oldestFirst: return $0.updatedAt < $1.updatedAt
    case .titleAZ:     return $0.title.localizedCompare($1.title) == .orderedAscending
    }
}
```

Expose the sort picker in `SnippetGalleryView.topBar` as a `Menu` button next to the search field.

---

## F3 — Cancel With Data: Confirmation Dialog

### `SnippetEditorView.swift`

#### A. Add dirty-check computed property
```swift
private var hasUnsavedData: Bool {
    switch mode {
    case .create:
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !mediaItems.isEmpty
    case .edit(let original):
        return title != original.title
            || description != original.snippetDescription
            || code != original.code
    }
}
```

#### B. Add state
```swift
@State private var isPresentingCancelConfirm: Bool = false
```

#### C. Replace cancel button action

Current cancel button:
```swift
Button { dismiss() } label: { ... }
    .keyboardShortcut(.cancelAction)
```

Replace body of the button action:
```swift
Button {
    if hasUnsavedData {
        isPresentingCancelConfirm = true
    } else {
        dismiss()
    }
} label: { ... }
.keyboardShortcut(.cancelAction)
.confirmationDialog(
    "Discard changes?",
    isPresented: $isPresentingCancelConfirm,
    titleVisibility: .visible
) {
    Button("Discard", role: .destructive) { dismiss() }
    Button("Keep editing", role: .cancel) { }
} message: {
    Text("Your snippet has unsaved content. Discard it?")
}
```

**Note:** `.confirmationDialog` renders as a native macOS alert/action-sheet. Do not use `.alert` for this — `.confirmationDialog` gives the correct destructive-button styling.

---

## F4 — Click Outside to Dismiss Creation Sheet

### Strategy

The current creation flow uses `.sheet(isPresented: $isPresentingNew)`. macOS sheets do not expose a scrim tap callback. Replace the `.sheet` with an **overlay presentation matching the detail-view pattern** already in `ContentView` (lines 185–230).

### `ContentView.swift`

#### A. Remove `.sheet(isPresented: $isPresentingNew)`

Delete lines 234–243:
```swift
// DELETE THIS BLOCK:
.sheet(isPresented: $isPresentingNew) {
    SnippetEditorView(mode: .create, availableCollections: collections) { newSnippet in
        ...
    }
}
```

#### B. Add the editor as an overlay inside `detail`

In the `detail:` content `ZStack`, after the existing snippet-detail overlay (the block starting at `if let snippet = selectedSnippet`), add:

```swift
if isPresentingNew {
    // Scrim — tap to attempt dismiss (F3 guard fires inside SnippetEditorView)
    Color.black
        .opacity(colorScheme == .dark ? 0.34 : 0.22)
        .ignoresSafeArea()
        .onTapGesture { attemptDismissNewSnippet() }
        .transition(.opacity)
        .zIndex(3)

    GeometryReader { proxy in
        let w = min(max(proxy.size.width * 0.90, 820), 1200)
        let h = min(max(proxy.size.height * 0.92, 660), 960)
        SnippetEditorView(
            mode: .create,
            availableCollections: collections,
            onRequestDismiss: { attemptDismissNewSnippet() },   // NEW param — see below
            onSave: { newSnippet in
                modelContext.insert(newSnippet)
                try modelContext.save()
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
```

#### C. Add `attemptDismissNewSnippet()` to `ContentView`
```swift
private func attemptDismissNewSnippet() {
    // ContentView cannot check editor dirty state directly.
    // Solution: use a binding or callback; see SnippetEditorView changes below.
    withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
        isPresentingNew = false
    }
}
```

Because ContentView can't inspect the editor's dirty state, coordinate via a `Binding<Bool>` or a callback:

#### D. `SnippetEditorView.swift` — Add `onRequestDismiss` parameter

```swift
// New optional param (default nil for backward compat with .edit sheet)
var onRequestDismiss: (() -> Void)? = nil
```

Replace the cancel button logic (from F3) to also call `onRequestDismiss` when no unsaved data:
```swift
Button {
    if hasUnsavedData {
        isPresentingCancelConfirm = true
    } else {
        onRequestDismiss?()   // triggers ContentView scrim dismiss
        dismiss()             // also dismiss if still in sheet context
    }
} label: { ... }
```

In the `.confirmationDialog` Discard action:
```swift
Button("Discard", role: .destructive) {
    onRequestDismiss?()
    dismiss()
}
```

#### E. Keep `.sheet(item: $editingSnippet)` unchanged

Edit mode continues to use the sheet. Only the **create** mode moves to the overlay.

---

## F5 — Full-Row Tap to Expand/Collapse Sidebar Sections

### `ContentView.swift` — Replace DisclosureGroup labels with tappable rows

Every `DisclosureGroup` in `legacySidebar` uses `label:` content that SwiftUI only activates on the chevron triangle. The fix: add a `Button` wrapping the entire label content that toggles the binding.

**Pattern to apply to every section** (`librarySection`, `frequentlyUsedSection`, `languagesSection`, `favoritesSection` from F1):

Current pattern:
```swift
DisclosureGroup(isExpanded: $isSomeSectionExpanded) {
    // content
} label: {
    Text("section name")
        .font(Mono.font(size: 11, weight: .semibold))
        .foregroundStyle(theme.textMuted)
}
```

Replace `label:` content:
```swift
} label: {
    Button {
        withAnimation(.snappy(duration: 0.18)) {
            isSomeSectionExpanded.toggle()
        }
    } label: {
        HStack {
            Text("section name")
                .font(Mono.font(size: 11, weight: .semibold))
                .foregroundStyle(theme.textMuted)
            Spacer()
        }
        .contentShape(Rectangle())   // makes the full width tappable
    }
    .buttonStyle(.plain)
}
```

**Apply to all four sections** (`librarySection`, `frequentlyUsedSection`, `languagesSection`, `favoritesSection`).

**Note:** `DisclosureGroup`'s built-in chevron still works; the `Button` supplements it. The `withAnimation` call produces a smooth fold animation identical to the native behavior.

For `languagesSection`, the label also contains a count badge:
```swift
Button {
    withAnimation(.snappy(duration: 0.18)) {
        isLanguagesSectionExpanded.toggle()
    }
} label: {
    HStack(spacing: 8) {
        Text("languages")...
        Text("\(sidebarFilteredLanguages.count)")...
        Spacer()
    }
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

---

## F6 — Auto-Select Collection on "New Snippet" From Collection View

### `ContentView.swift`

#### A. Add state
```swift
@State private var newSnippetPreselectedCollectionID: PersistentIdentifier? = nil
```

#### B. Update `isPresentingNew` trigger sites

There are two paths that set `isPresentingNew = true`:

**Path 1** — FAB in `SnippetGalleryView` via `onNew` callback:

Change the `onNew` closure in `SnippetGalleryView`'s call site:
```swift
onNew: {
    newSnippetPreselectedCollectionID = selectedCollectionID  // capture current collection
    isPresentingNew = true
},
```

**Path 2** — `newSnippetButton` in `legacySidebar` calls `beginCreateCollection()`.
That button creates a **collection**, not a snippet. Confirm this is intentional; the FAB (`⌘N`) is the snippet-creation trigger.

If there's also a per-collection "new snippet" button anywhere in the sidebar, apply the same pattern there.

#### C. Pass `preselectedCollectionID` to `SnippetEditorView`

In the overlay block (from F4) or the `.sheet`:
```swift
SnippetEditorView(
    mode: .create,
    availableCollections: collections,
    preselectedCollectionID: newSnippetPreselectedCollectionID,   // NEW
    onRequestDismiss: { attemptDismissNewSnippet() },
    onSave: { ... }
)
```

#### D. `SnippetEditorView.swift` — Accept and apply `preselectedCollectionID`

Add parameter:
```swift
var preselectedCollectionID: PersistentIdentifier? = nil
```

In `load()`, inside the `case .create` branch (currently just calls `LanguageDetector`):
```swift
private func load() {
    if case .edit(let snippet) = mode {
        // ... existing edit load code ...
    } else {
        // create mode
        detectedLanguage = LanguageDetector.detect(code: code)
        if let preID = preselectedCollectionID {
            selectedCollectionIDs = [preID]   // pre-tick the collection chip
        }
    }
}
```

The collections section UI (`collectionsSection`) already renders checkmarks based on `selectedCollectionIDs`, so no further UI changes are needed — the chip will appear pre-selected.

---

## Implementation Notes for the Agent

1. **Order of implementation**: F5 → F3 → F4 → F1 → F6 → F2. F4 depends on F3 (the `onRequestDismiss` + dirty-check must exist before wiring the overlay scrim).

2. **SwiftData `isFavorite` migration**: The `= false` default at the property level (not only in `init`) is mandatory, identical to the `copyCount` fix. Do not declare `var isFavorite: Bool` without the default value or SwiftData migration will crash.

3. **`SnippetGalleryView` new parameters**: `showFavoritesOnly: Binding<Bool>`, `onToggleFavoritesFilter: () -> Void`, `onMoveSnippets: (Set<PersistentIdentifier>, SnippetCollection) -> Void`, `availableCollections: [SnippetCollection]` — add all as `let` constants, update every call site in `ContentView`.

4. **`F4` overlay vs sheet for edit mode**: Keep `editingSnippet` as a `.sheet`. Only the create flow uses the overlay. Do not consolidate them.

5. **`F5` animation**: Use `.snappy(duration: 0.18)` not `.spring(...)` for the disclosure toggle — it matches the system DisclosureGroup feel.

6. **`F2` drag-to-trash guard**: When `isSelectMode == true`, the `cardDragGesture` must not activate. The simplest guard is to add `if isSelectMode { return }` at the top of `cardDragGesture.onChanged`.

7. **`FilterTag` in F1**: `FilterTag` is `private struct` at the bottom of `SnippetGalleryView.swift`. It already handles `isSelected` state with a full accent fill. The favorites tag uses it unchanged — just pass a yellow accent color `Color(red: 1.0, green: 0.80, blue: 0.20)`.

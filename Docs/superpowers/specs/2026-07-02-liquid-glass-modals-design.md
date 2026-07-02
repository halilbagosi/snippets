# Liquid Glass modals & full-screen titlebar — Design

## Context

Three surfaces in the app don't match its established Liquid Glass design language:

1. **Move-to popup** (`MoveToCollectionSheet`, private struct in [SnippetGalleryView.swift](../../../Sources/Snippets/Views/SnippetGalleryView.swift)) — presented via native `.sheet()`, wrapped in `NavigationStack` with a system toolbar.
2. **New/Edit Collection** (`CollectionEditorSheet.swift`) — also a native `.sheet()` with `NavigationStack` + `.toolbar`, even though its internal sections already use the app's real glass components well.
3. **Full-screen window titlebar** — opaque, unlike windowed mode.

Elsewhere in the app (snippet detail, snippet editor), modals are custom in-window overlays: a dimmed `DotGridBackground` backdrop behind a floating glass card, built entirely from the app's own components (`liquidGlassSurface`, `DSGlassContainer`) with zero system chrome (no `NavigationStack`, no `.toolbar`, no `.navigationTitle`). The `.sheet()`-based surfaces are the odd ones out: their `NavigationStack`/`.toolbar` combination renders the OS's generic opaque sheet toolbar bar directly above already-glassy content, which is the visible seam.

The app already implements real Liquid Glass via `DSGlassModifier`/`liquidGlassSurface` (using the actual macOS 26 `glassEffect` API where available, falling back to `.ultraThinMaterial` otherwise) — this design reuses that vocabulary throughout rather than introducing new visual primitives.

## Goals

- Move-to popup and Collection editor both read as part of the same modal family as snippet detail/edit.
- Full-screen mode's titlebar is transparent, matching windowed mode.
- Toggle switches use the native, automatically-Liquid-Glass system control rather than hand-rolled fakes.

## Non-goals

- Restructuring the Collection editor's section layout (stays: preview header, color strip, contrast warning, subcollection toggle, snippet membership, symbol browser).
- Changing Move-to row visuals (icon, color, chevron, dividers) — only the container and list structure change.
- Touching `AppearanceView`'s toggles (already plain native `Toggle`, no styling conflict).
- Wiring up the currently-unused design system components (`DSButton`, `DSBadge`, `DSTag`, etc.) — out of scope; this pass only touches the three surfaces above plus toggle cleanup.

## 1. Full-screen titlebar transparency

**Root cause:** `WindowChromeConfigurator.applyChrome()` ([SnippetsApp.swift](../../../Sources/Snippets/SnippetsApp.swift)) hides the title and traffic lights but never sets `titlebarAppearsTransparent` or adds `.fullSizeContentView` to the window's style mask. Windowed mode looks translucent only because `.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` hides the SwiftUI toolbar background so the app's own glass bar shows through underneath. Full screen's auto-hiding titlebar/menu-bar strip is a separate AppKit-drawn surface unaffected by that SwiftUI modifier, so it falls back to the OS default opaque material.

**Change:** in `applyChrome()`, set:
```swift
window.titlebarAppearsTransparent = true
window.styleMask.insert(.fullSizeContentView)
```
This runs on the same notifications already observed (`didBecomeKey`, `didEnterFullScreen`, `didExitFullScreen`), so it's idempotent and self-healing across transitions. No change to the existing traffic-light alpha logic.

**Risk:** `.fullSizeContentView` affects content layout under the titlebar in windowed mode too. Since the app already treats the toolbar area as transparent/overlaid content in windowed mode, this should be a no-op there — but needs visual confirmation after implementation (see Testing).

## 2. Move-to popup → in-window glass card

Replace the `.sheet(isPresented: $showMoveSheet)` presentation with an in-window overlay, added to `SnippetGalleryView`'s own view tree (not lifted to `ContentView`), so the sidebar stays visible/interactive underneath — consistent with how `SnippetDetailView`/`SnippetEditorView` only cover the detail pane today.

**Structure**, mirroring `SnippetDetailView`'s overlay recipe exactly:
- Dimmed backdrop: `Color.black.opacity(colorScheme == .dark ? 0.34 : 0.22)`, `ignoresSafeArea()`, tap-to-dismiss, `.transition(.opacity)`.
- Card: `GeometryReader`-sized, roughly 420pt wide, height clamped to a fraction of the pane (e.g. `clamp(proxy.size.height * 0.6, 420, 640)`), `RoundedRectangle(cornerRadius: 16)` filled with `theme.surface`, `theme.borderStrong` stroke, drop shadow, asymmetric scale+opacity spring transition.
- Floating circular "×" close button, top-trailing, `liquidGlassSurface(in: Circle())` — same as `SnippetDetailView`'s close button. No separate footer/Cancel button needed; dismissal is via "×", backdrop tap, or Esc.

**List changes** (per your answer: add hierarchy + search):
- New search field pinned above the list, same visual recipe as the symbol-search field already in `CollectionEditorSheet` (`.ultraThinMaterial` rounded rect, leading magnifying-glass icon, trailing clear button when non-empty).
- "All Snippets" stays pinned at the top, unaffected by search (it's a global action, not a named item).
- Below it, collections render as a real hierarchy: top-level collections first, each followed by its subcollections indented beneath (single level of indentation, since collections can currently nest one level deep in the existing filter logic — verify actual max depth during implementation).
- When the search field is non-empty, the list flattens to name-matches only (case-insensitive substring), dropping indentation — simplest correct behavior, avoids reconstructing partial ancestor chains for a filtered subset.
- Empty search results: "No matching collections" placeholder text, same tone as the existing "No matching symbols" state in `CollectionEditorSheet`.
- Existing target-filtering logic (excluding the moved items themselves, their current parent/collection, and would-be cycles) is unchanged — only presentation and list structure change.

## 3. Collection editor — remove sheet chrome, keep sections

`CollectionEditorSheet` stays behind `.sheet(isPresented: $isPresentingCollectionEditor)` at the `ContentView` call site (unchanged). Internally, drop `NavigationStack`, `.navigationTitle`, and `.toolbar` — replace with a custom header row at the top of the existing `VStack`, above the `ScrollView`, built the same way `SnippetEditorView`'s `editorChrome` already does it:

- **Leading:** small glass badge (`liquidGlassSurface(in: RoundedRectangle(cornerRadius: 8), tint: activeColor.opacity(0.1))`) containing the collection's icon + "New Collection" / "Edit Collection" text.
- **Trailing:** "Cancel" — glass pill button (`liquidGlassSurface(interactive: true)`), `.keyboardShortcut(.cancelAction)`, wired to the existing `onCancel` closure. "Save" — glass pill, tinted with `activeColor` and full opacity when `canSave`, dimmed/disabled otherwise, `.keyboardShortcut(.defaultAction)`, wired to the existing `onSave` closure — same enabled/disabled/tint logic as today's toolbar Save button, just restyled.

All five existing sections (`glassPreviewHeader`, `glassColorStrip`, `glassContrastWarning`, `glassSubcollectionToggleSection`, `glassSnippetMembershipSection`, `glassSymbolBrowser`) are unchanged in structure and behavior. Since removing `NavigationStack`/`.toolbar` also removes the sheet's default top inset, the new header needs enough top padding that content doesn't crowd the sheet's rounded top corners.

## 4. Toggle consolidation

The Sub-Collection toggle already uses `Toggle().toggleStyle(.switch)` — this is the correct pattern, since native controls automatically pick up real Liquid Glass rendering on macOS 26 (the same reasoning already documented in `ContentView.swift` for the sidebar's toggle button). Two unused, hand-rolled "glass" toggle styles exist in the codebase and should be deleted as part of this pass:

- `Sources/Snippets/DesignSystem/Components/DSToggle.swift` (`DSToggle` / `DSLiquidGlassToggleStyle`)
- `Sources/Snippets/Views/Components/LiquidGlassToggleStyle.swift` (`LiquidGlassToggleStyle`)

Neither is referenced anywhere outside its own `#Preview`. Both draw a flat capsule pretending to be glass, which is strictly worse than the real system control and contradicts the "native liquid glass toggle" requirement. No functional change to the Sub-Collection toggle itself — it's already correct.

## Files touched

| File | Change |
|---|---|
| `Sources/Snippets/SnippetsApp.swift` | `WindowChromeConfigurator`: transparent titlebar + full-size content view |
| `Sources/Snippets/Views/SnippetGalleryView.swift` | Replace `.sheet` with in-tree overlay card; rework `MoveToCollectionSheet` → hierarchical, searchable glass card |
| `Sources/Snippets/Views/Sidebar/CollectionEditorSheet.swift` | Remove `NavigationStack`/`.toolbar`; add custom glass header |
| `Sources/Snippets/DesignSystem/Components/DSToggle.swift` | Delete (unused, superseded by native `.switch`) |
| `Sources/Snippets/Views/Components/LiquidGlassToggleStyle.swift` | Delete (unused, superseded by native `.switch`) |

## Testing / verification

This is a native macOS SwiftUI app with no headless UI test harness in this repo. Verification is:
1. `xcodebuild`/`swift build` (or opening in Xcode) to confirm the project compiles after `NavigationStack`/toolbar removal and file deletions.
2. Manual run on macOS to visually confirm: full-screen titlebar transparency (and that windowed mode is unaffected by `.fullSizeContentView`), the Move-to card's hierarchy/search behavior, and the Collection editor's new header against its existing sections.
3. No existing automated test coverage targets these views (none found in the codebase) — this design doesn't add any, consistent with current project conventions.

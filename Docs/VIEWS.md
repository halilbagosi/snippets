# View Reference

This file explains every screen-level view and private helper view under `Sources/Snippets/Views`.

## `ContentView`

Path: `Sources/Snippets/Views/ContentView.swift`

What it does:

- Owns the main `NavigationSplitView`.
- Queries active snippets, all snippets, and collections with SwiftData.
- Coordinates sidebar selection, language filters, collection filters, search text, selected snippet detail, editor sheets, collection editor sheets, soft delete, undo delete, and trash cleanup.
- Chooses between `TrashView` and the normal gallery/detail experience.

Customize it:

- Change sidebar sections in `legacySidebar` or `ModernSidebar`.
- Change gallery filtering in `baseFilteredSnippets`, `searchFilteredSnippets`, `searchResultCollections`, and `searchResultSnippets`.
- Change detail modal sizing in the `GeometryReader` around `SnippetDetailView`.
- Change status bar content in `detailStatusSegments()`.
- Change trash retention in `performTrashCleanup()`.

Watch out:

- `selectedCollectionID`, `selectedSnippetID`, and `sidebarSelectionContext` are intentionally separate. Keep them in sync when adding navigation paths.
- Deletion is soft-delete first: `delete(_ snippet:)` sets `deletedAt` instead of removing the model.

## `ModernSidebar`

Path: `Sources/Snippets/Views/ContentView.swift`

What it does:

- Native macOS 26 sidebar implementation using `List(selection:)`.
- Shows all snippets, nested collections, frequently used snippets, language filters, and Trash.
- Handles context menus and drag/drop move/copy behavior through callbacks supplied by `ContentView`.

Customize it:

- Change section names and row labels in `body`.
- Change nested collection behavior in `modernCollectionTree(for:)`.
- Add new sidebar destinations by extending the `Selection` enum and matching `ContentView.SidebarSelectionContext`.

## `LiquidGlassToggle`

Path: `Sources/Snippets/Views/ContentView.swift`

What it does:

- Small reusable toggle row used by collection editor controls.
- Uses the app's glass styling and switches a `Binding<Bool>`.

Customize it:

- Change its icon/text layout in `body`.
- Change active/inactive colors through `Theme` or the local `tint` values.

## `CollectionEditorSheet`

Path: `Sources/Snippets/Views/ContentView.swift`

What it does:

- Modal sheet for creating and editing collections.
- Lets users set collection name, icon, color, parent collection, and included snippets.

Customize it:

- Add more icon options in the icon picker area.
- Change allowed nesting rules where `availableParents` is computed.
- Change default colors in the color selection UI or `SnippetCollection.defaultColorHex`.

## `SnippetGalleryView`

Path: `Sources/Snippets/Views/SnippetGalleryView.swift`

What it does:

- Renders the searchable, filterable gallery.
- Shows collection results and snippet results as collapsible sections.
- Supports select mode, bulk delete/restore, sort order, collection filter popover, keyboard shortcuts, drag-to-trash, and undo-delete reassembly animation.

Customize it:

- Change grid sizing in `columns` and `subcollectionColumns`.
- Change top toolbar controls in `topBar`.
- Change language filter tags in `filterBar`.
- Change empty state copy and styling in `emptyState`.
- Change drag-to-trash physics in `cardDragGesture(for:)`, `minimize(_:from:)`, and `dragTrashTarget`.

Watch out:

- `SnippetGalleryViewModel` owns sort/select calculations. Keep selection logic there when possible.
- `GallerySection` now owns the repeated collapsible section shell.
- The Metal animation uses `MetalGenieOverlay` when supported and falls back to `GenieOverlay`/`ReverseGenieOverlay`.

## `SnippetCollectionCard`

Path: `Sources/Snippets/Views/SnippetGalleryView.swift`

What it does:

- Card used in the gallery for collection/subcollection tiles.
- Counts active snippets recursively through child collections.
- Adds hover tilt, glass styling, context menu actions, and accessibility actions.

Customize it:

- Change card height and spacing in the main `HStack`.
- Change collection count wording through `snippetSummary`.
- Change hover intensity in the `rotation3DEffect`, `offset`, and shadow modifiers.

## `GenieOverlay`, `ReverseGenieOverlay`, `GlassShardFragmentView`

Path: `Sources/Snippets/Views/SnippetGalleryView.swift`

What they do:

- SwiftUI fallback for the delete and undo-delete shatter/reassemble animation.
- Split a card into static shard shapes and animate them toward or away from a bottom-center sink point.

Customize them:

- Change shard geometry in the `shards` arrays.
- Change animation timing in each `onAppear`.
- Change opacity, outline, and glow in `GlassShardFragmentView`.

## `FilterTag`

Path: `Sources/Snippets/Views/SnippetGalleryView.swift`

What it does:

- Glass-styled pill button for filters, sort controls, select mode, and bulk actions.
- Resolves selected/unselected foreground and fill colors based on light/dark mode.

Customize it:

- Change pill dimensions in padding and corner radius.
- Change selected contrast in `resolvedForeground` and `resolvedFill`.
- Reuse it for new toolbar controls by passing a label, SF Symbol, accent color, selected state, and action.

## `SnippetDetailView`

Path: `Sources/Snippets/Views/SnippetDetailView.swift`

What it does:

- Shows full snippet title, language, updated date, copy/edit/delete actions, description, attachments, highlighted source, and metadata.
- Opens attachments in a lightbox sheet.

Customize it:

- Change action buttons in `actionBar`.
- Change code display in `codeBlock` and `HighlightedCodeView`.
- Change metadata chips in `metadata` and `metaPill(label:value:)`.
- Change attachment strip sizing in `AttachmentStripLayout`.

Watch out:

- Copying increments `snippet.copyCount`.
- Delete button calls a confirmation dialog, then delegates actual deletion to `ContentView`.

## Detail Attachment Views

Path: `Sources/Snippets/Views/SnippetDetailView.swift`

Views:

- `MediaPreview`: framed image/video preview in the horizontal attachment strip.
- `MediaAttachmentLightbox`: modal shell for large attachment previews.
- `LightboxImageView`: full-size image display.
- `LightboxVideoView`: full-size looping video display.
- `ImageMediaView`: inline image preview.
- `VideoMediaView`: inline video preview.
- `HighlightedCodeView`: AppKit-backed highlighted code view on macOS, with a SwiftUI fallback elsewhere.

Customize them:

- Change preview dimensions in `AttachmentStripLayout`.
- Change video behavior in shared `LoopingVideoPlayerView`.
- Change syntax highlighting through `SyntaxHighlighter.applyAttributes(...)`.

## `SnippetEditorView`

Path: `Sources/Snippets/Views/SnippetEditorView.swift`

What it does:

- Modal create/edit form for snippets.
- Edits title, description, language, collections, code, and media attachments.
- Uses `SnippetEditorViewModel` for draft state, auto-detected language, validation, media selection, and save logic.

Customize it:

- Change field order in the main `ScrollView` VStack.
- Change save/cancel chrome in `editorChrome`.
- Change editor field styling in `fieldBackground(focused:)`.
- Change status bar segments in `editorStatusBar`.
- Change attachment controls in `mediaSection`.

Watch out:

- `mode` determines whether save creates a new `Snippet` or mutates an existing one.
- `mediaManager` is injectable for tests.

## `MediaThumbnail`

Path: `Sources/Snippets/Views/SnippetEditorView.swift`

What it does:

- Small thumbnail for media attached inside the editor.
- Loads images from `MediaManager.resolvedURL(for:)`.
- Shows a remove button.

Customize it:

- Change tile height in `.frame(height: 96)`.
- Change remove button style in the top-trailing `Button`.
- Add video thumbnails by extending `loadThumbnail()`.

## `TrashView`

Path: `Sources/Snippets/Views/TrashView.swift`

What it does:

- Shows snippets with `deletedAt != nil`.
- Reuses `SnippetGalleryView` in trash mode.
- Supports search, restore, permanent delete, and a trash-specific status bar.

Customize it:

- Change red background palette in `DotGridBackground(...)`.
- Change trash status content in `statusSegments`.
- Change permanent-delete media cleanup in `permanentlyDelete(_:)`.

Watch out:

- `restore(_:)` clears `deletedAt`; it does not create a new snippet.
- `permanentlyDelete(_:)` deletes attached files through `appEnvironment.mediaManager`.

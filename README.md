# Snippets

Snippets is a macOS SwiftUI app for saving code snippets, grouping them into collections, attaching media, searching/filtering by language, and recovering soft-deleted snippets from Trash.

## Project Map

- `Sources/Snippets/SnippetsApp.swift` starts the app, configures SwiftData, and injects `AppEnvironment`.
- `Sources/Snippets/Models` contains SwiftData models for snippets, collections, and media.
- `Sources/Snippets/Views` contains the main screens and modal flows.
- `Sources/Snippets/Views/Components` contains reusable UI, rendering helpers, and shared media playback.
- `Sources/Snippets/Features` contains view models for editor and gallery behavior.
- `Sources/Snippets/Services` contains app services such as clipboard, media storage, theme colors, language detection, and syntax highlighting.
- `Tests/SnippetsTests` contains view model tests.

## Main Views

Read [Docs/VIEWS.md](Docs/VIEWS.md) for what every view does, what state it owns, and where to customize behavior.

The main flow is:

1. `ContentView` owns navigation, SwiftData queries, sidebar state, collection editing, snippet deletion, and detail presentation.
2. `SnippetGalleryView` renders the searchable grid of snippets and collections.
3. `SnippetDetailView` shows a selected snippet with code, metadata, and media attachments.
4. `SnippetEditorView` creates and edits snippets.
5. `TrashView` shows soft-deleted snippets and handles restore/permanent delete.

## Components

Read [Docs/COMPONENTS.md](Docs/COMPONENTS.md) for every shared component and major private helper component.

The main shared components are:

- `SnippetCard` for snippet tiles.
- `GallerySection` for collapsible gallery sections.
- `LoopingVideoPlayerView` for muted looping attachment previews.
- `LanguageBadge`, `SectionHeader`, `StatusBar`, and `CollectionIconView` for repeated UI vocabulary.
- `GlassCard`, `DotGridBackground`, `MetalGenieOverlay`, and `GenieShaders.metal` for the visual system.

## Customization Starting Points

- App colors and fonts: `Sources/Snippets/Services/Theme.swift`.
- Supported language names, symbols, and accent colors: `Sources/Snippets/Services/LanguageDetector.swift`.
- Gallery card layout and hover effects: `Sources/Snippets/Views/Components/SnippetCard.swift`.
- Gallery search/filter/sort controls: `Sources/Snippets/Views/SnippetGalleryView.swift`.
- Collapsible gallery section styling: `Sources/Snippets/Views/Components/GallerySection.swift`.
- Editor fields and save workflow: `Sources/Snippets/Views/SnippetEditorView.swift` and `Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift`.
- Trash timing: `Snippet.daysUntilPermanentDeletion` and `ContentView.performTrashCleanup()`.

## Build And Test

```sh
swift build
swift test
```

To keep generated build output outside the repository while experimenting:

```sh
swift build --build-path /tmp/snippets-build
swift test --build-path /tmp/snippets-test-build
```

## Cleanup Notes

Generated build products, local SwiftPM/Xcode state, `.DS_Store`, and temporary patch/view scripts are intentionally not part of the source tree. The `.gitignore` keeps those files from coming back after local builds or editor sessions.

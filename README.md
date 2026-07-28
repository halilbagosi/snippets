# Snippets

Snippets is a native macOS app built with SwiftUI and SwiftData for organizing, searching, and browsing code snippets. It supports collections, media attachments, language-aware filtering, and soft-delete recovery from Trash.

## Features

- Create and edit snippets with title, description, language, code, and attachments
- Organize snippets into nested collections
- Search and filter by text, language, and collection
- Attach images and videos to snippets
- Browse snippets in a polished gallery interface built on a Liquid Glass design system
- Drive the app from Shortcuts and Siri via App Intents (create, find, copy, open, and favorite snippets)
- Recover deleted snippets from Trash before permanent cleanup
- Persist data locally using SwiftData

## Project Structure

- Sources/Snippets/SnippetsApp.swift: app entry point, SwiftData setup, and app environment configuration
- Sources/Snippets/App: shared app environment and appearance settings
- Sources/Snippets/Models: SwiftData models for snippets, collections, and media
- Sources/Snippets/Views: main app screens and modal flows
- Sources/Snippets/Views/Components: reusable UI components and rendering helpers
- Sources/Snippets/DesignSystem: design tokens, modifiers, and glass-style components
- Sources/Snippets/Features: view models for gallery and editor behavior
- Sources/Snippets/Intents: App Intents, entities, and App Shortcuts for Shortcuts/Siri
- Sources/Snippets/Services: theme, language detection, media handling, and other shared services
- Sources/Snippets/Core/Services: service protocols shared across the app
- Tests/SnippetsTests: unit tests for view models and app behavior

## Requirements

- macOS 26+ (the app links against the macOS 26 SDK for the Liquid Glass design system)
- Xcode (beta) with Swift 6.2 tools; SwiftData macros require the full Xcode toolchain, not the Command Line Tools alone

## Build and Run

`Snippets.xcodeproj` is the only build system — it is what produces the signed
`.app` with its icon, entitlements and App Intents. From the project root:

> SwiftData macros require the full Xcode (beta) toolchain. Point `DEVELOPER_DIR` at it before building or testing:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```

To run the app, open the project and launch the Snippets scheme.

### Adding files

The project lists source files explicitly (it does not use synchronized
folders), so a new file under `Sources/` has to be added to the `Snippets`
target, and a new file under `Tests/SnippetsTests/` to the `SnippetsTests`
target. Adding it in Xcode does both; adding it on disk alone leaves it
uncompiled.

## Testing

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```

The `SnippetsTests` target is hosted by the app, so a test run launches
`Snippets.app` — expect the app to appear briefly.

## Notes

Generated build products, local Xcode state, and temporary editor files are intentionally excluded from source control. The repository ignores these files so local development stays clean.

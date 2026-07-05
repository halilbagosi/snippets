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

- macOS 15+
- Xcode (beta) with Swift 6.2 tools; SwiftData macros require the full Xcode toolchain, not the Command Line Tools alone
- Swift Package Manager

## Build and Run

From the project root:

```sh
swift build
```

To run the app from Xcode, open the project and launch the Snippets scheme.

## Testing

```sh
swift test
```

To keep build artifacts outside the repository during local development:

```sh
swift build --build-path /tmp/snippets-build
swift test --build-path /tmp/snippets-test-build
```

## Notes

Generated build products, local Xcode/SwiftPM state, and temporary editor files are intentionally excluded from source control. The repository ignores these files so local development stays clean.

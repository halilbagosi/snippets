# Snippets — build and test invariants

Native macOS app (SwiftUI + SwiftData). Platform: **macOS 26+** (Liquid Glass APIs / modern SDK stamp).

`Snippets.xcodeproj` is the **only** build system. There is no `Package.swift` —
`swift build` / `swift test` do not work here, and adding a package manifest
back would re-create two diverging file lists.

## Toolchain

SwiftData macros require the full Xcode (beta) toolchain — the Command Line Tools alone will not build this project:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

## Build

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```

## Test

305 XCTest cases in the `SnippetsTests` target, hosted by the app (so a run launches `Snippets.app` briefly):

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```

## Registering files

The project enumerates its files explicitly — it does not use synchronized
folders. Any new/removed/moved file must be registered in
`Snippets.xcodeproj/project.pbxproj`: under `Sources/` in the `Snippets`
target, under `Tests/SnippetsTests/` in the `SnippetsTests` target. A file
that only exists on disk is silently not compiled.

## Layout

See the README "Project Structure" section for the source layout.

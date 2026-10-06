# Snippets — build and test invariants

Native macOS app (SwiftUI + SwiftData). Platform: **macOS 26+** (Liquid Glass APIs / modern SDK stamp).

`Snippets.xcodeproj` is the **only** build system. There is no `Package.swift` —
`swift build` / `swift test` do not work here, and adding a package manifest
back would re-create two diverging file lists.

## Toolchain

SwiftData macros require the full Xcode toolchain — the Command Line Tools alone will not build this project. `xcode-select -p` should print `/Applications/Xcode.app/Contents/Developer`; if it points at `/Library/Developer/CommandLineTools`, prefix commands with:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Build

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```

## Test

432 XCTest cases in the `SnippetsTests` target, hosted by the app (so a run launches `Snippets.app` briefly):

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```

## App Store build

The `AppStore` configuration (used by Archive) is sandboxed via
`Snippets-AppStore.entitlements` and defines `APP_STORE`, which compiles out
the Swift preview engine. Code that touches Swift previews must keep both
builds compiling. Test it too (403 tests — the Swift-preview suites drop out);
testability is a command-line override, never a setting of that configuration:

```sh
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' -configuration AppStore ENABLE_TESTABILITY=YES test
```

## Registering files

The project enumerates its files explicitly — it does not use synchronized
folders. Any new/removed/moved file must be registered in
`Snippets.xcodeproj/project.pbxproj`: under `Sources/` in the `Snippets`
target, under `Tests/SnippetsTests/` in the `SnippetsTests` target. A file
that only exists on disk is silently not compiled.

## Layout

See the README "Project Structure" section for the source layout.

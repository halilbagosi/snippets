# Snippets — build and test invariants

Native macOS app (SwiftUI + SwiftData). Platform: **macOS 26+** (`Package.swift` declares `.macOS(.v26)` — Liquid Glass APIs / modern SDK stamp).

## Toolchain

SwiftData macros require the full Xcode (beta) toolchain — the Command Line Tools alone will not build this project:

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
```

## Build

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build
```

Keep build artifacts out of the repo: use `--build-path /tmp/snippets-build` (build) and `/tmp/snippets-test-build` (test).

## Test

Tests run only via `swift test` (SPM), not the Xcode scheme:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build
```

## Dual build system

SwiftPM (`Package.swift`) auto-discovers sources; `Snippets.xcodeproj` enumerates them manually. Any new/removed/moved file under `Sources/` must also be registered in `Snippets.xcodeproj/project.pbxproj`. (Test files under `Tests/` need no registration.)

## Layout

See the README "Project Structure" section for the source layout.

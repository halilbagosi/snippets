---
name: verify
description: Build, launch, and drive the Snippets macOS app to verify changes at runtime.
---

# Verifying Snippets changes

## Build & launch
```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # CLT lacks SwiftData macros
swift build
.build/debug/Snippets > /tmp/snippets-app.log 2>&1 &   # plain executable launch works
```
Tests: `swift test` only (never xcodebuild test).

## Driving the UI
- No Screen Recording permission for `screencapture` — pixels are unavailable. Use
  AX via System Events (`osascript`); Terminal already has Accessibility permission.
- Reference the app by process: `first process whose name is "Snippets"` — but window
  lookups fail transiently; `set frontmost … delay 0.5` first, and retry once.
- Structure: `window 1 > group 1 > splitter group 1 > group 1 (sidebar) / group 2 (content)`.
  Scroll-area indices RENUMBER as panes open/close — always find containers by content,
  never by cached index. Sidebar collapse removes group 2 entirely.
- Search field: focus with `keystroke "f" using command down`, then `keystroke`; verify by
  reading `value of text field 1`. Typing without frontmost goes to another app.
- Snippet detail pane = scroll area whose `static text 2` is "snippet"; title is `static text 3`.
  The code|preview toggle is the button on the same row (±12pt y) as the "source"/"preview" text.
- Gallery cards mostly do NOT respond to AXPress (SwiftUI tap gestures) and are often
  scrolled off-window (click-at lands outside). Filter via search first; even then card
  clicks are unreliable — prefer verifying engines out-of-process (below).
- WKWebView previews DO expose their DOM via AX (`static text "Count: 0"`,
  `button "Increment"` under the detail scroll area) — strong evidence source.
- `entire contents of window 1` dumps element specifiers including static-text values;
  pipe to a file and grep. Individual `every static text of entire contents of X` fails.

## Verifying preview engines without the UI
Production preview logic compiles standalone (no design-system deps):
```bash
xcrun swiftc harness/main.swift \
  Sources/Snippets/Features/Preview/{ShaderPipeline,MetalShaderSource,SwiftPreviewBuilder,SwiftPreviewHarness}.swift -o run
```
- Harnesses with `await MainActor.run` must end with `RunLoop.main.run()` + `exit(0)`
  in the Task — a blocked main thread deadlocks MainActor.
- Web-engine documents: generate with WebPreviewHTMLBuilder + the vendored runtime in
  `Sources/Snippets/Resources/WebPreview/`, serve over `python3 -m http.server` (the
  Browser pane refuses file:// URLs), and drive in the Browser pane.

## Data seeding — CAUTION
`URL.applicationSupportDirectory` IGNORES a `$HOME` override: any seeding hits the REAL
store at `~/Library/Application Support/Snippets.store`. Quit the app first, seed by
compiling a script against `Sources/Snippets/Models/*.swift`, tag rows with known titles,
and delete them afterwards by title + createdAt window.

---
name: verify
description: Build, launch, and drive the Snippets macOS app to verify changes at runtime.
---

# Verifying Snippets changes

## One build system — every new file must be registered
`Snippets.xcodeproj` is the only build system (no `Package.swift`; `swift
build`/`swift test` do not work here). It uses explicit per-file references,
NOT filesystem-synchronized groups, so a new `.swift` file on disk is silently
not compiled until it is added to a target: `Sources/` → `Snippets`,
`Tests/SnippetsTests/` → `SnippetsTests`. To register files (no Ruby xcodeproj
gem on system Ruby; use Python `mod-pbxproj`):
```bash
python3 -m pip install --user pbxproj
# XcodeProject.load(...); get_or_create_group('Preview', path='Preview', parent=<group>)
# add_file('Name.swift', parent=grp, tree=TreeType.GROUP, target_name='Snippets',
#          force=False, file_options=FileOptions(create_build_files=True)); p.save()
# TreeType/FileOptions import from pbxproj.pbxextensions.ProjectFiles
```
mod-pbxproj's save() sets the file executable; restore with
`git update-index --chmod=-x Snippets.xcodeproj/project.pbxproj`.

## Build & test gate
```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer   # CLT lacks SwiftData macros
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build \
  2>&1 | grep -iE "error:|BUILD SUCCEEDED|BUILD FAILED|cannot be found"
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test \
  2>&1 | tail -5    # 305 tests; hosted by the app, so Snippets.app launches during the run
```

## Launch
```bash
open -a "$(xcodebuild -project Snippets.xcodeproj -scheme Snippets -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/{d=$3} /  FULL_PRODUCT_NAME/{n=$3} END{print d"/"n}')"
```
Launch the built `.app` (not a bare binary) — the bundle is what gives the app
its icon, Info.plist and App Intents.

**Two instances ruin AX measurements.** `tell process "Snippets"` picks the
first match, so if Xcode is also running the app you may be measuring the other
build. Check with `pgrep -lf Snippets` and address a specific one by pid:
`repeat with p in (every process whose name is "Snippets") ... if (unix id of p) is <pid>`.

## Driving the UI
- `screencapture -x -R x,y,w,h out.png` works (Screen Recording is granted as of
  2026-07-28) — but it captures the SCREEN, so raise the target window first
  (`perform action "AXRaise"`), or you photograph whatever is on top of it.
  For pixel measurements without PIL: `sips -s format bmp`, then parse the BMP
  (24-bit, bottom-up rows) in plain Python.
- AX via System Events (`osascript`) for structure; Terminal has Accessibility.
  Gotcha: `(item 2 of (size of w)) as text` inside a `&` concatenation throws
  -1700 unpredictably. Return raw lists (`return {title of w, size of w}`) and
  parse in the shell instead.
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

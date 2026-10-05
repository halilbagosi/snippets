# Plan 015: Document the menu bar, clipboard capture and live previews in the README

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 08bb49c3..HEAD -- README.md`
> If `README.md` changed since this plan was written, compare the "Current
> state" excerpts against the live file before proceeding; on a mismatch,
> treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: NONE
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `08bb49c3`, 2026-07-31

## Why this matters

`README.md` describes a version of this app that no longer exists. Four
user-facing capabilities are absent from it entirely, and two of them are the
whole reason the app behaves the way it does now: it lives in the menu bar after
its last window closes, and — if you switch one setting on — it reads your
clipboard every second.

`grep -in "menu bar\|clipboard\|quick copy\|capture" README.md` returns **zero**
matches. So does every term for the preview engines. Someone reading this repo's
front door learns that Snippets stores and searches snippets; they do not learn
that it *executes* them in a `WKWebView`, on the GPU, and — for Swift — as a
dylib `dlopen`ed into the app's own unsandboxed process.

For the clipboard feature the gap is not just staleness, it is disclosure. Today
the only place the app tells anyone it can read the pasteboard is a one-line
caption inside a Settings toggle
(`Sources/Snippets/Views/Settings/AppearanceView.swift:229`), and the comment
above it says as much: "The caption is the user's only notice that the app reads
the clipboard". A README that documents the opt-in, the exclusions it honours,
and the fact that a candidate never touches disk turns that from a hidden
behaviour into a stated one.

The "Project Structure" list has drifted the same way: nine real directories are
missing from it, and its description of `Sources/Snippets/Features` ("view models
for gallery and editor behavior") now covers two of that directory's five
children. A structure list that is wrong is worse than one that is short,
because the reader trusts it.

## Current state

### The file

- `README.md` — the only file this plan modifies. 69 lines at commit `08bb49c3`.

### The Features list as it exists today (`README.md:5-14`)

```markdown
## Features

- Create and edit snippets with title, description, language, code, and attachments
- Organize snippets into nested collections
- Search and filter by text, language, and collection
- Attach images and videos to snippets
- Browse snippets in a polished gallery interface built on a Liquid Glass design system
- Drive the app from Shortcuts and Siri via App Intents (create, find, copy, open, and favorite snippets)
- Recover deleted snippets from Trash before permanent cleanup
- Persist data locally using SwiftData
```

**This is the style exemplar. Match it.** Three properties to copy:

1. Present tense, imperative-ish verb first — "Create and edit snippets…",
   "Organize snippets into…", "Recover deleted snippets from Trash…".
2. One line per bullet, no sub-bullets, no bold, no trailing period.
3. Plain and factual. The strongest adjective in the whole list is "polished".
   Do not write "powerful", "seamless", "blazing", "beautiful", or "simply".

### The Project Structure list as it exists today (`README.md:16-28`)

```markdown
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
```

Format is `- <path>: <lowercase description>` — a flat list of full paths, not an
indented tree. Child directories get their own top-level bullet
(`Views/Components` sits flat beside `Views`). Keep that.

### What the app actually does now — verified facts to write from

You do not need to read the source to execute this plan; everything below was
verified against it. Paths are given so you can confirm if you want to.

**1. Menu bar quick copy** (landed 2026-07-28, commits `9a53d2dd`..`97b958f5`)

- A scissors status item opens a searchable panel that copies a snippet without
  leaving the app the user is in.
- Four scopes, in this on-screen order:
  **Favorites, Frequent, Recent, All** (`Sources/Snippets/Features/QuickCopy/QuickCopyScope.swift:7-11`).
  `⌘1`–`⌘4` select them (`shortcutIndex` at `:33-36`,
  `.keyboardShortcut(...)` at `Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift:148-151`).
- Keys, all verified in `QuickCopyPanel.swift`:
  - `↑` / `↓` move the selection, clamped at both ends (`:114-115`)
  - `⏎` copies (`:237-257`)
  - `⌘⏎` reveals the snippet in the main window instead (`:236`, `:246-250`)
  - `Esc` clears a typed query first and dismisses only when there is nothing
    left to clear (`:116-119`, logic in
    `Sources/Snippets/Features/QuickCopy/QuickCopySelection.swift:28-33`)
- The app **keeps running after its last window closes**.
  `Sources/Snippets/SnippetsApp.swift:105`:
  ```swift
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  ```
  Its doc comment (`:101-104`) explains why the panel footer carries Quit: "with
  no window and another app frontmost the menu bar is not ours". The footer
  buttons are "Open Snippets" and "Quit Snippets" (`QuickCopyPanel.swift:211-223`).

**2. Clipboard capture** (same feature set)

- **Off by default and opt-in.** `Sources/Snippets/Services/ClipboardMonitor.swift:23-25`:
  ```swift
  /// Opt-in, and off by default: the app should not start reading the
  /// clipboard because it was launched.
  static let enabledDefaultsKey = "quickCapture.enabled"
  ```
- The toggle is **Settings → Preferences → "Offer to Save Copied Code"**, caption
  "Watch the clipboard and offer to save code you copy elsewhere"
  (`Sources/Snippets/Views/Settings/AppearanceView.swift:226-231`).
- Polling interval is **1.0 s** (`ClipboardMonitor.swift:27`) — macOS has no
  clipboard-change notification, so polling `changeCount` is the only mechanism.
- Three privacy properties, all verified:
  - Pasteboard items marked `org.nspasteboard.ConcealedType`,
    `TransientType` or `AutoGeneratedType` are never captured
    (`Sources/Snippets/Features/QuickCapture/ClipboardCapture.swift:17-26`). The
    comment names the reason: "Honouring all three is what keeps a password out
    of a capture prompt."
  - The app's own copies are suppressed via
    `Clipboard.lastLocalChangeCount` (`ClipboardMonitor.swift:71`,
    `Sources/Snippets/Services/Clipboard.swift:14`).
  - A candidate **lives in memory only** until the user accepts it —
    `ClipboardMonitor.swift:16-17`: "Clipboard content is never written to disk
    here — a candidate lives in memory until the user accepts it in the panel."
- Content that is not recognised as code, or whose language detects as
  `.unknown`, is dropped (`ClipboardCapture.swift:27-31`).

**3. Live previews** — the app's headline capability, and entirely undocumented

- Three engines (`Docs/security-overview.md` §1, and
  `Sources/Snippets/Features/Preview/PreviewKind.swift`):
  - **Web** — `WKWebView`. Flavors: HTML, CSS, JavaScript, TypeScript, React,
    GLSL (`PreviewKind.swift:11-18`, mapped at `:20-35`).
  - **Metal** — `MTKView`, shader source on the GPU.
  - **Swift** — compiled to a dylib and `dlopen`ed **in-process**.
- The consent model lives in `Sources/Snippets/Features/Preview/PreviewTrust.swift`.
  Its type-level doc comment (`:5-21`) is the best available source for this
  text; the substance, verified:
  - **Auto-run** is global, set from a first-launch prompt, changeable in
    Settings, and **defaults to off** (`PreviewTrust.swift:31-37`,
    `AppearanceView.swift:215-220` — "Run Previews Automatically", caption "Off,
    a preview waits for Run instead of executing when you open a snippet").
  - With auto-run off, a web or Metal preview waits behind a Run button;
    approval is **per snippet, per launch**, held in memory only
    (`PreviewTrust.swift:54-57`: "approving a run is a decision about *this* look
    at the snippet, and it should not silently become permanent").
  - The **Swift engine keeps an unconditional Run gate** regardless of the
    setting (`Sources/Snippets/Views/Components/Preview/SnippetPreviewView.swift:33`
    — "The Swift flavor keeps its own Run gate unconditionally").
  - **npm modules from esm.sh** are a separate **per-snippet, persisted** grant,
    surfaced as a banner naming the packages. `PreviewTrust.swift:18-21`: it "is
    the only way a preview can reach the network at all", and "stays granular
    because it is the one capability that leaves the machine".

**4. Snippet connections** — also entirely undocumented; confirmed real and
user-facing

- `Snippet` has a self-referential SwiftData relationship
  (`Sources/Snippets/Models/Snippet.swift:31-32`: `dependencies` / `dependents`).
- The editor has a Connections section
  (`Sources/Snippets/Views/SnippetEditorView.swift:73`, `:523`) whose own hint
  text is the clearest one-line description available (`:451`):
  "connections run before this snippet in one shared preview".
- `Sources/Snippets/Features/Preview/SnippetLinker.swift:20-24` flattens the
  dependency graph into ordered preview sources: "helpers first (post-order),
  entry last, each snippet at most once, cycles broken by the visited set."
  Dependencies whose language cannot contribute to the entry's engine are dropped
  and reported by title.
- Gallery cards mark connected snippets with a badge, accessibility label
  "Connected snippet" (`Sources/Snippets/Views/Components/SnippetCard.swift:167`).

### Directories missing from Project Structure — verified with `find`

Run at commit `08bb49c3`; the count is files found recursively under each path.

| Path | Files | Status in README |
|------|-------|------------------|
| `Sources/Snippets/Views/Components/Preview` | 5 | missing |
| `Sources/Snippets/Views/QuickCopy` | 3 | missing |
| `Sources/Snippets/Views/Settings` | 3 | missing |
| `Sources/Snippets/Views/Sidebar` | 2 | missing |
| `Sources/Snippets/Features/Editor` | 1 | missing |
| `Sources/Snippets/Features/Gallery` | 2 | missing |
| `Sources/Snippets/Features/Preview` | 12 | missing |
| `Sources/Snippets/Features/QuickCapture` | 2 | missing |
| `Sources/Snippets/Features/QuickCopy` | 4 | missing |
| `Sources/Snippets/Resources` | 26 | missing |
| `Sources/Snippets/Models` | 3 | **present and correct** |

Two traps, both verified:

- **`Sources/Snippets/Persistence` exists on disk and is EMPTY** — zero files, at
  any depth. Do **not** add it to the list. A `test -d` check would pass and the
  entry would still be a lie. (It is referenced in `project.pbxproj` as a group
  with no members.)
- `Sources/Snippets/Views/ext` (1 file), `Sources/Snippets/Core/Services/Protocols`
  (1 file), and the `DesignSystem/{Components,Modifiers,Tokens}` subdirectories
  are real but deliberately **out of scope** — the existing list stops at that
  level of granularity for `DesignSystem` already, and adding them buys nothing.

### What is already correct — do not touch

The README's "Requirements", "Build and Run", "Adding files", "Testing" and
"Notes" sections (`README.md:30-69`) are current and accurate. They already
document the macOS 26 SDK requirement, the `DEVELOPER_DIR` pointing at
Xcode-beta, the xcodeproj-only rule, and the explicit file-registration
requirement. Leave every one of those lines byte-identical.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | exit 0, `** BUILD SUCCEEDED **` |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | exit 0, `** TEST SUCCEEDED **`, **389 tests, 0 failures** |

There is **no** `Package.swift` in this repo. `swift build` and `swift test` do
not work here — `Snippets.xcodeproj` is the only build system. (Note: the
round-1 plan files, `plans/001`–`plans/010`, still quote the old `swift build`
commands in their own Commands tables. They are all DONE and are kept as an
archive; ignore them and do not fix them in this plan. `plans/README.md` itself
carries the correct commands.)

This is a documentation-only change, so the build and test runs are not proving
the change works — they are the "nothing was accidentally touched" gate. Run
them anyway, at the end.

## Scope

**In scope** (the only file you should modify):
- `README.md`
- `plans/README.md` — status row only, per the executor instructions.

**Out of scope** (do NOT touch):
- **Any file under `Sources/` or `Tests/`.** This plan changes documentation to
  match the code; it does not change the code to match the documentation. If you
  find something the code does that contradicts this plan, that is a STOP
  condition, not a licence to edit Swift.
- `README.md:30-69` — Requirements, Build and Run, Adding files, Testing, Notes.
  Verified current. Rewording them is pure churn and will show up as noise in
  review.
- `Docs/security-overview.md` — read it if you like, but it is untracked
  (`Docs/` is gitignored) and it is **not** the model for the new README text.
  Specifically: **do not copy its §4 "Residual risk" list into the README.** The
  README describes the feature and the consent model a user is offered. It is
  not the place to publish a threat model, and several of those items concern
  unshipped work.
- `CLAUDE.md` — separate document, currently accurate.
- Screenshots, badges, a table of contents, or any other new README furniture.
  Add the sections this plan names and nothing else.

## Git workflow

- Branch: `advisor/015-readme-feature-coverage`
- One commit is fine for the whole plan. Message style, matching `git log`: short
  sentence-case imperative subject, blank line, body. Example subject from this
  repo:
  `Tie panel timers to view lifetime, and retire only the banner`
  A suitable subject here: `Document quick copy, clipboard capture and previews in the README`
- Do NOT push or open a PR.

## Steps

### Step 0: Confirm the gap before writing anything

```sh
grep -in "menu bar\|clipboard\|quick copy\|capture\|preview\|connection" README.md
```

**Expected**: no output, exit status 1. (At `08bb49c3` the only line containing
any of these substrings is line 32's "the app **links** against the macOS 26
SDK", which this pattern does not match.)

If any of these terms already appears, the README has been updated since this
plan was written — STOP and report which sections already exist.

Capture the "before" state of the structure list too:

```sh
sed -n '/^## Project Structure$/,/^## Requirements$/p' README.md \
  | grep -o '^- [A-Za-z][^:]*:' | sed 's/^- //; s/:$//' | wc -l
```

**Expected**: `11`.

### Step 1: Widen the opening paragraph

`README.md:3` currently reads:

```markdown
Snippets is a native macOS app built with SwiftUI and SwiftData for organizing, searching, and browsing code snippets. It supports collections, media attachments, language-aware filtering, and soft-delete recovery from Trash.
```

Replace it with (verbatim, single line, no hard wrap — the file does not wrap
this paragraph):

```markdown
Snippets is a native macOS app built with SwiftUI and SwiftData for organizing, searching, and previewing code snippets. It supports collections, media attachments, language-aware filtering, live previews, a menu bar quick-copy panel, and soft-delete recovery from Trash.
```

**Verify**:
```sh
grep -c "menu bar quick-copy panel" README.md
```
→ `1`

### Step 2: Add four bullets to Features

Append these four bullets to the end of the existing list at `README.md:14`,
after `- Persist data locally using SwiftData`, in this order. Use the wording
verbatim — it was written to match the existing bullets' voice:

```markdown
- Preview a snippet live: HTML, CSS, JavaScript, TypeScript, React, and GLSL in a web view, Metal shaders on the GPU, and Swift compiled and run in the app
- Connect snippets so a helper runs before the snippet that uses it, in one shared preview
- Copy any snippet from the menu bar without leaving the app you are working in
- Optionally watch the clipboard and offer to save code you copy elsewhere as a snippet
```

Do not reorder or reword the eight existing bullets.

**Verify**:
```sh
sed -n '/^## Features$/,/^## /p' README.md | grep -c '^- '
```
→ `12`

```sh
grep -c "^- Optionally watch the clipboard" README.md
```
→ `1`

### Step 3: Add a "Menu bar quick copy" section

Insert this section **after** the Features list and **before**
`## Project Structure`. Verbatim:

```markdown
## Menu bar quick copy

A scissors icon in the menu bar opens a searchable panel for copying a snippet
without leaving the app you are working in. The panel is driven from the
keyboard:

- Type to filter the current scope
- `↑` / `↓` move the selection
- `⏎` copies the selected snippet
- `⌘⏎` reveals the selected snippet in the main window instead
- `⌘1`–`⌘4` switch scope: Favorites, Frequent, Recent, All
- `Esc` clears a typed search, and dismisses the panel once there is nothing to clear

Closing the last window no longer quits the app — it keeps running in the menu
bar so the panel stays reachable while you work elsewhere. The panel footer
carries Quit, because with no window open and another app frontmost the menu bar
is not ours.
```

**Verify**:
```sh
grep -n "^## Menu bar quick copy" README.md
```
→ exactly 1 match, at a line number **greater** than the `## Features` line and
**less** than the `## Project Structure` line. Confirm with:
```sh
grep -n "^## Features\|^## Menu bar quick copy\|^## Project Structure" README.md
```
→ three matches, in that order.

### Step 4: Add a "Previews and privacy" section

Insert this immediately after the section from step 3, still before
`## Project Structure`. Verbatim:

```markdown
## Previews and privacy

### Running previews

Previewing a snippet runs it. Three engines do that: a `WKWebView` for HTML,
CSS, JavaScript, TypeScript, React, and GLSL; an `MTKView` for Metal shaders;
and, for Swift, a compile to a dynamic library that is loaded into the app's own
process. That is the feature working as intended for code you wrote yourself,
which is where snippets come from today — so execution is something you turn on
rather than something that happens.

- **Run Previews Automatically** is a global setting, off by default. It is
  chosen from a first-launch prompt and changeable in Settings → Preferences.
- With it off, a web or Metal preview waits behind a Run button. Approval is per
  snippet and lasts for that launch only.
- Swift previews always wait for an explicit Run, whatever the setting says, so
  running native code in the app's process is never automatic.
- Loading npm modules from esm.sh is a separate grant, per snippet, shown as a
  banner naming the packages. It is the only way a preview reaches the network.

### Clipboard capture

**Offer to Save Copied Code** (Settings → Preferences) is off by default. Turn
it on and the app checks the clipboard once a second — macOS offers no
change notification, so polling is the only mechanism — and when what you copied
looks like code in a language it recognizes, offers to save it as a snippet.

- Content marked concealed, transient, or auto-generated by the app that
  produced it is never captured. Password managers set these markers.
- Copies the app makes itself are ignored.
- A candidate is held in memory only. Nothing is written to the store until you
  choose to save it.
```

**Verify**:
```sh
grep -n "^## Previews and privacy\|^### Running previews\|^### Clipboard capture" README.md
```
→ three matches, in that order.

```sh
grep -c "off by default" README.md
```
→ `2` (one for auto-run, one for clipboard capture — both defaults are the point
of these sections).

### Step 5: Fill in the Project Structure list

Two edits in this section.

**5a — reword two existing descriptions** that no longer describe their
directories. Change only the text after the colon:

```markdown
- Sources/Snippets/Features: view models and pure logic for gallery, editor, preview, and quick copy behavior
- Sources/Snippets/Services: theme, language detection, media handling, the menu bar controller, the clipboard monitor, and other shared services
```

**5b — add ten bullets**, each placed directly beneath its parent so the flat
list still reads in tree order. The complete section, after both edits, must be
exactly this:

```markdown
## Project Structure

- Sources/Snippets/SnippetsApp.swift: app entry point, SwiftData setup, and app environment configuration
- Sources/Snippets/App: shared app environment and appearance settings
- Sources/Snippets/Models: SwiftData models for snippets, collections, and media
- Sources/Snippets/Views: main app screens and modal flows
- Sources/Snippets/Views/Components: reusable UI components and rendering helpers
- Sources/Snippets/Views/Components/Preview: the web, Metal, and Swift preview views
- Sources/Snippets/Views/QuickCopy: the menu bar panel, its result rows, and the capture banner
- Sources/Snippets/Views/Settings: the Settings window — appearance, preferences, and About
- Sources/Snippets/Views/Sidebar: the collection sidebar and its editor sheet
- Sources/Snippets/DesignSystem: design tokens, modifiers, and glass-style components
- Sources/Snippets/Features: view models and pure logic for gallery, editor, preview, and quick copy behavior
- Sources/Snippets/Features/Editor: the snippet editor view model
- Sources/Snippets/Features/Gallery: the gallery view model and collection move tree
- Sources/Snippets/Features/Preview: preview engines, snippet linking, preview parameters, and the preview trust model
- Sources/Snippets/Features/QuickCapture: clipboard capture policy and the code-shape heuristics behind it
- Sources/Snippets/Features/QuickCopy: quick-copy scopes, results, selection arithmetic, and view model
- Sources/Snippets/Intents: App Intents, entities, and App Shortcuts for Shortcuts/Siri
- Sources/Snippets/Services: theme, language detection, media handling, the menu bar controller, the clipboard monitor, and other shared services
- Sources/Snippets/Core/Services: service protocols shared across the app
- Sources/Snippets/Resources: app icon assets and the vendored web-preview runtimes
- Tests/SnippetsTests: unit tests for view models and app behavior
```

That is 21 bullets. Do **not** add `Sources/Snippets/Persistence` — it exists on
disk but contains no files.

**Verify** — this is the important one. Every path named must exist *and* be
non-empty:

```sh
sed -n '/^## Project Structure$/,/^## Requirements$/p' README.md \
  | grep -o '^- [A-Za-z][^:]*:' \
  | sed 's/^- //; s/:$//' \
  | while read -r p; do
      if [ -d "$p" ]; then
        n=$(find "$p" -type f | wc -l | tr -d ' ')
        if [ "$n" -gt 0 ]; then echo "OK    $p ($n files)"; else echo "EMPTY $p"; fi
      elif [ -f "$p" ]; then echo "OK    $p"
      else echo "MISS  $p"; fi
    done
```

→ **21 lines, every one starting with `OK`**. Any `MISS` or `EMPTY` line means
the list is lying; fix the list, not the filesystem.

### Step 6: Run the build and test gate

Nothing under `Sources/` or `Tests/` should have changed. Prove it:

```sh
git status --porcelain
```
→ only `README.md` (and `plans/README.md` once you update the status row).

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```
→ exit 0, `** TEST SUCCEEDED **`, **389 tests, 0 failures**. The test target is
hosted by the app, so `Snippets.app` will launch briefly — that is expected.

### Step 7: Read the finished README end to end

The one judgment call in this plan. Read `README.md` top to bottom and confirm:

- The new sections read in the same register as the old ones: plain, factual,
  present tense, no marketing adjectives.
- No duplicated statement — e.g. the clipboard opt-in is stated once in the
  Features bullet (one line) and once in "Previews and privacy" (in detail).
  That is intended. Three times is not.
- The document still flows: what it is → what it does → how the two newest
  features behave → where the code lives → how to build and test it.

## Test plan

**No new tests, and do not add any.** Nothing executable changes. The
verification for this plan is the grep set in "Done criteria", of which the
structure-list loop in step 5 is the substantive one — it is the only check that
can catch the specific way this section has failed before (naming a path that
does not exist, or one that is empty).

The existing 389 tests must still pass, unchanged, as the untouched-code gate.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -ci "menu bar" README.md` returns ≥ 1
- [ ] `grep -ci "clipboard" README.md` returns ≥ 3
- [ ] `grep -c "QuickCopy" README.md` returns ≥ 1
- [ ] `grep -c "QuickCapture" README.md` returns ≥ 1
- [ ] `grep -ci "preview" README.md` returns ≥ 8
- [ ] `grep -c "esm.sh" README.md` returns ≥ 1
- [ ] `grep -c "off by default" README.md` returns 2
- [ ] `grep -ci "connect" README.md` returns ≥ 1
- [ ] `grep -c "^## " README.md` returns 8 (Features, Menu bar quick copy, Previews and privacy, Project Structure, Requirements, Build and Run, Testing, Notes)
- [ ] `sed -n '/^## Features$/,/^## /p' README.md | grep -c '^- '` returns 12
- [ ] The step 5 structure loop prints **21 lines, all `OK`** — no `MISS`, no `EMPTY`
- [ ] `grep -c "Sources/Snippets/Persistence" README.md` returns 0
- [ ] `git diff README.md` shows **no change** to any line in Requirements, Build and Run, Adding files, Testing, or Notes
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` exits 0
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` exits 0 with **389 tests, 0 failures**
- [ ] `git status --porcelain` shows only `README.md` and `plans/README.md` as modified
- [ ] `plans/README.md` status row for 015 updated

## STOP conditions

Stop and report back (do not improvise) if:

- Step 0's grep returns matches — the README already covers some of this, and
  this plan's edits would duplicate rather than add.
- The Features or Project Structure lists do not match the excerpts in "Current
  state" (`README.md` has drifted since commit `08bb49c3`).
- The step 5 loop reports `MISS` or `EMPTY` for a path you were told to add, and
  the cause is not a typo in your edit — that means a directory was removed or
  emptied since this plan was written, and the plan's facts are stale.
- The test count comes back as anything other than 389, or the build fails.
  Neither should be possible from a docs-only change; if it happens you have
  edited something outside `README.md`. Check `git status` before doing anything
  else.
- You find that the app's behaviour contradicts what you were asked to write —
  e.g. auto-run is not off by default, or the clipboard toggle is on by default.
  Report the contradiction. **Do not "fix" the code to match the README**, and do
  not quietly soften the README to fit. Source of truth is
  `PreviewTrust.swift:31-37` and `ClipboardMonitor.swift:23-25`.
- You feel the need to add a Security or Threat Model section. That is a
  different document with a different audience; report the suggestion instead.

## Maintenance notes

For whoever owns this file next:

- **This README now makes two privacy claims that are code-enforced, not
  aspirational**: that clipboard capture is off until enabled, and that a
  candidate never reaches the store without an explicit save. Both are load-bearing
  sentences. If `ClipboardMonitor.enabledDefaultsKey` ever gains a non-false
  default, or `ClipboardCapture.excludedTypes` shrinks, the README is wrong the
  same day — treat those two symbols as documentation-coupled.
- **Likewise for the preview consent model**: `PreviewTrust.autoRunPreviews`
  defaulting to false, session-only run approval, the unconditional Swift gate,
  and esm.sh being per snippet. `plans/README.md` records export/import as a
  direction option; `Docs/security-overview.md` §4.1 is explicit that Swift
  preview containment must be resolved before any import feature ships. Whichever
  of those lands will change this section.
- **The Project Structure list is now 21 entries and will drift again.** The loop
  in step 5 is the cheap defence — it belongs in CI eventually (there is a
  workflow from `plans/007`). That is deliberately not part of this plan, which is
  a content fix, not a tooling one.
- **Reviewers should scrutinise**: that no line between `## Requirements` and the
  end of the file changed, and that the new prose does not overstate the
  isolation of the Swift preview engine. It runs in-process, unsandboxed. The
  wording in step 4 ("loaded into the app's own process") says so without
  editorialising; do not let a later edit soften it to "runs locally".
- **Deferred out of this plan**: the round-1 plan files (`plans/001`–`plans/010`)
  still quote `swift build` / `swift test` in their own Commands tables, which do
  not work in this repo. They are all DONE and kept as an archive, and
  `plans/README.md` now carries the correct commands plus an explicit warning to
  prefer them over any old plan's table. Not worth rewriting ten finished files.
</content>
</invoke>

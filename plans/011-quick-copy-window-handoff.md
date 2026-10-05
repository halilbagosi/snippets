# Plan 011: Deliver quick-copy handoffs when the main window is closed

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 08bb49c3..HEAD -- Sources/Snippets/Views/ContentView.swift Sources/Snippets/Services/MenuBarController.swift`
> If either file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch,
> treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `08bb49c3`, 2026-07-31

## Why this matters

Since commit `9a53d2dd` the app deliberately survives closing its last window —
that is the whole point of a menu bar quick-copy panel, which must be usable
while the user is working in another app. But two of the three ways the panel
hands work back to the main UI only work when a main window already exists.

Both "Save as snippet" (accepting a clipboard capture) and "⌘⏎ reveal this
snippet in the app" write a flag and then rely on `ContentView` observing the
change. With no window open, `ContentView` does not exist yet: the window is
created asynchronously, the flag is written before the view starts observing,
and `onChange` never fires for a value that was already set when the view
appeared. The user watches the app come forward, sees an empty gallery, and
their captured code is gone.

Worse, the flags are only cleared *inside* the handler that never ran, so they
stay set. The next attempt writes the same value, `onChange` sees no change,
and nothing happens again. The failure is sticky until the app restarts.

`ContentView` already solves this exact problem for a third flag and says so in
a comment. This plan applies the same treatment to the other two.

## Current state

### The files

- `Sources/Snippets/Views/ContentView.swift` — the main UI. Observes three
  "pending work" flags. Drains one of them on appear; the other two are
  `onChange`-only.
- `Sources/Snippets/Services/MenuBarController.swift` — owns the menu bar
  status item and the quick-copy panel. Writes all three flags. Also defines
  `MainWindowOpener`, which restores a window when none is left.

### ContentView drains ONE flag on appear (`ContentView.swift:753-760`)

```swift
        .task {
            performTrashCleanup()
            debouncedSearchText = searchText
            rebuildDerivedCaches()
            // Cold launch: an intent that launched the app may have set the flag
            // before this view began observing, so onChange never fires for it.
            if navigator.pendingNewSnippet { presentNewSnippetFromIntent() }
        }
```

That comment states the bug this plan fixes. It is applied to
`pendingNewSnippet` only.

### The two flags with no drain (`ContentView.swift:784-803`)

```swift
        .onChange(of: navigator.pendingOpenSnippetUUID) { _, newValue in
            guard let uuid = newValue else { return }
            if let match = snippets.first(where: { $0.uuid == uuid }) {
                withAnimation(DSToken.Motion.overlay) {
                    searchText = ""
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                    selectedSnippetID = match.persistentModelID
                }
            }
            navigator.pendingOpenSnippetUUID = nil
        }
        .onChange(of: navigator.pendingNewSnippet) { _, isPending in
            guard isPending else { return }
            presentNewSnippetFromIntent()
        }
        .onChange(of: CaptureDraft.shared.pending) { _, candidate in
            guard let candidate else { return }
            presentCapturedDraft(candidate)
        }
```

Note that `navigator.pendingOpenSnippetUUID = nil` on the last line of the
first handler is *inside* the handler — so when the handler never runs, the
flag is never cleared.

### The handler bodies (`ContentView.swift:974-995`)

```swift
    /// Presents the blank new-snippet editor in response to `NewSnippetIntent`,
    /// clearing any open detail and the pending flag.
    private func presentNewSnippetFromIntent() {
        newSnippetPreselectedCollectionID = nil
        withAnimation(DSToken.Motion.overlay) {
            selectedSnippetID = nil
            isPresentingNew = true
        }
        navigator.pendingNewSnippet = false
    }

    /// Opens the new-snippet editor seeded with captured clipboard code.
    /// Nothing is written to the store — the user still has to save.
    private func presentCapturedDraft(_ candidate: ClipboardCapture.Candidate) {
        newSnippetPreselectedCollectionID = nil
        newSnippetDraftCode = candidate.code
        withAnimation(DSToken.Motion.overlay) {
            selectedSnippetID = nil
            isPresentingNew = true
        }
        CaptureDraft.shared.pending = nil
    }
```

`presentCapturedDraft` is already shaped correctly for reuse — it takes the
candidate and clears the flag itself. The open-snippet logic is *not* factored
out; it lives inline in the `onChange` closure and must be extracted.

### Who writes the flags (`MenuBarController.swift:172-195`)

```swift
    private func makeRoot(model: QuickCopyViewModel, panel: NSPanel) -> some View {
        QuickCopyPanel(
            model: model,
            scaleAnchor: scaleAnchor(for: panel),
            onDismiss: { [weak self] in self?.hidePanel() },
            onOpenMainWindow: { [weak self] snippet in
                self?.hidePanel()
                MainWindowOpener.activate()
                // ContentView observes this and opens the snippet, then clears
                // it — see its `.onChange(of: navigator.pendingOpenSnippetUUID)`.
                if let snippet, let uuid = snippet.uuid {
                    AppIntentNavigator.shared.pendingOpenSnippetUUID = uuid
                }
            },
            onQuit: { NSApp.terminate(nil) },
            onSaveCapture: { candidate in
                MainWindowOpener.activate()
                CaptureDraft.shared.pending = candidate
            }
        )
        // The panel lives outside the scene graph, so it inherits nothing from
        // the WindowGroup's `.modelContainer`.
        .modelContainer(SnippetsData.sharedModelContainer)
    }
```

Both call `MainWindowOpener.activate()` and then set the flag on the very next
line — same run-loop turn, before any newly created `ContentView` has run its
body.

### The window restorer (`MenuBarController.swift:14-27`)

```swift
@MainActor
enum MainWindowOpener {
    static var open: (() -> Void)?

    /// Bring the app forward, restoring a window if none is left.
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
        let restorable = NSApp.windows.filter(\.canBecomeMain)
        if restorable.isEmpty {
            open?()
        } else {
            for window in restorable { window.makeKeyAndOrderFront(nil) }
        }
    }
}
```

`NSApp.windows` includes the Settings window, which is an ordinary
`NSWindow` and therefore also satisfies `canBecomeMain`. With the gallery
closed and Settings open, this raises Settings and never restores the gallery.
Step 4 addresses that; it is gated on a runtime probe because the exact
identifier SwiftUI assigns must be observed, not guessed.

### Repo conventions to match

- Comments explain *why*, not what, and name the failure mode they prevent.
  The `ContentView.swift:757-758` comment quoted above is the exemplar for the
  style this plan's new comments should match.
- Private helpers on the view are `private func`, placed near related helpers
  (see `presentNewSnippetFromIntent` / `presentCapturedDraft`, which sit
  together at `ContentView.swift:974-995`). Put the new helper beside them.
- `AppIntentNavigator` (`Sources/Snippets/Intents/AppIntentNavigator.swift`) is
  documented as "One-way bridge from the app's intents into the running UI…
  `ContentView` observes both, acts, and clears them." Keep that contract:
  whoever acts is also responsible for clearing.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | exit 0, `** BUILD SUCCEEDED **` |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures |

There is **no** `Package.swift` in this repo. `swift build` and `swift test` do
not work here — `Snippets.xcodeproj` is the only build system. The test target
is hosted by the app, so a test run briefly launches `Snippets.app`; that is
expected.

## Suggested executor toolkit

- The repo ships a `verify` skill at `.claude/skills/verify` for building,
  launching and driving the app at runtime. Steps 1 and 5 require runtime
  verification; invoke it if it is available in your environment.
- A caution recorded in `Docs/security-overview.md` and worth repeating: `open`
  on an already-running build reuses the live process, so you can easily
  screenshot a stale binary. Compare `ps -o lstart` against the built binary's
  mtime before trusting any runtime observation.

## Scope

**In scope** (the only files you should modify):
- `Sources/Snippets/Views/ContentView.swift`
- `Sources/Snippets/Services/MenuBarController.swift`

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift` and
  `CaptureBanner.swift` — the panel's own dismissal behaviour is plan 012.
  Changing it here will collide with that plan.
- `Sources/Snippets/Intents/AppIntentNavigator.swift` — the flag bridge itself
  is correct; only its consumers are wrong. Do not add drain logic to the
  navigator.
- `Sources/Snippets/SnippetsApp.swift` — the scene graph and window group are
  correct as they stand.
- Do **not** change `applicationShouldTerminateAfterLastWindowClosed` back to
  `true`. Surviving the last window is the feature, not the bug.

## Git workflow

- Branch: `advisor/011-quick-copy-window-handoff`
- Commit per logical unit. Message style, matching `git log`: short sentence-case
  imperative subject, blank line, body explaining the failure mode. Example
  from this repo:
  `Tie panel timers to view lifetime, and retire only the banner`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 0: Reproduce the failure before changing anything

Do not skip this. The whole plan rests on the claim that closing the last
window makes these handoffs fail; confirm it, and record what you saw.

1. Build and launch the app:
   ```sh
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
   ```
   then launch the built `Snippets.app` from `DerivedData` (the build output
   path is printed by `xcodebuild`).
2. Create at least one snippet so the panel has something to list.
3. Close the main window with ⌘W. The app must stay running (menu bar scissors
   icon still present). If the app quits here, STOP — the drift is larger than
   this plan assumes.
4. Click the scissors status item, select a snippet, press **⌘⏎** (reveal).

**Expected failure**: the app comes forward and a window opens, but the
selected snippet is *not* opened — you get the default gallery.

5. Without restarting, repeat step 4 on the **same** snippet with the window
   now open.

**Expected failure**: still nothing happens, because
`navigator.pendingOpenSnippetUUID` still holds that UUID and `onChange` sees no
change. This second observation is the "sticky" half of the bug and is the more
diagnostic of the two.

**Verify**: you have observed both failures. Write down what happened — you
will re-run this exact sequence in step 5.

**If the reveal works correctly in step 4**, STOP and report. Either the window
is not actually being torn down on ⌘W, or SwiftUI's scene timing differs from
what this plan assumes, and the fix in steps 2–3 may be unnecessary or wrong.

### Step 1: Extract the open-snippet logic out of its `onChange` closure

In `Sources/Snippets/Views/ContentView.swift`, add a private helper next to
`presentNewSnippetFromIntent` and `presentCapturedDraft` (around `:974-995`),
carrying the body currently inlined in the `onChange` at `:784-795`:

```swift
    /// Opens the snippet `OpenSnippetIntent` or the quick-copy panel asked for,
    /// clearing the request either way — an unclearable request would make every
    /// later request for the same snippet a no-op, because `onChange` fires on
    /// change and not on value.
    private func openPendingSnippet(_ uuid: UUID) {
        if let match = snippets.first(where: { $0.uuid == uuid }) {
            withAnimation(DSToken.Motion.overlay) {
                searchText = ""
                selectedCollectionID = nil
                sidebarSelectionContext = .allSnippets
                selectedSnippetID = match.persistentModelID
            }
        }
        navigator.pendingOpenSnippetUUID = nil
    }
```

Then replace the `onChange` at `:784-795` with a call to it:

```swift
        .onChange(of: navigator.pendingOpenSnippetUUID) { _, newValue in
            guard let uuid = newValue else { return }
            openPendingSnippet(uuid)
        }
```

Note the clear happens unconditionally, exactly as it does today — including
when no snippet matches the UUID. That is deliberate: a request for a snippet
that no longer exists must not wedge the flag.

**Verify**: build succeeds and behaviour is unchanged so far.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

### Step 2: Drain all three flags on appear, not one

Replace the `.task` block at `ContentView.swift:753-760` with:

```swift
        .task {
            performTrashCleanup()
            debouncedSearchText = searchText
            rebuildDerivedCaches()
            drainPendingWork()
        }
```

and add, next to the helpers from step 1:

```swift
    /// Acts on work that was requested before this view existed.
    ///
    /// Two ways in: an App Intent that launched the app cold, and the menu bar
    /// panel handing off after `MainWindowOpener` had to build a fresh window.
    /// Both set their flag and return immediately, so the value is already in
    /// place by the time this view first runs its body — and `onChange` fires on
    /// a change, never on the value it started with. Without this drain the
    /// request is dropped, and because each handler is also what clears its own
    /// flag, it stays dropped: every later request for the same snippet writes
    /// the same value and changes nothing.
    private func drainPendingWork() {
        if navigator.pendingNewSnippet { presentNewSnippetFromIntent() }
        if let uuid = navigator.pendingOpenSnippetUUID { openPendingSnippet(uuid) }
        if let candidate = CaptureDraft.shared.pending { presentCapturedDraft(candidate) }
    }
```

Order matters and is not arbitrary: all three set `isPresentingNew` or
`selectedSnippetID`, so if more than one were somehow pending, the last one
wins. Capture goes last because it is the only one carrying user content that
would otherwise be lost — a dropped "open snippet" costs a click, a dropped
capture costs the copied code.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
grep -n "drainPendingWork\|openPendingSnippet" Sources/Snippets/Views/ContentView.swift
```
→ exactly 5 matching lines: the two definitions, `drainPendingWork()` in the
`.task`, `openPendingSnippet(uuid)` in the `onChange`, and
`openPendingSnippet(uuid)` inside `drainPendingWork`.

### Step 3: Confirm nothing regressed

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```
→ exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures.

The count must be **389**, unchanged — steps 1 and 2 add no tests (see "Test
plan" for why) and must break none.

### Step 4: Stop `MainWindowOpener` raising the Settings window

This step is **gated on a runtime probe**. Do not guess at window identifiers.

First, add a temporary probe at the top of `MainWindowOpener.activate()` in
`Sources/Snippets/Services/MenuBarController.swift`:

```swift
        for window in NSApp.windows {
            print("[probe] id=\(window.identifier?.rawValue ?? "nil") canBecomeMain=\(window.canBecomeMain) class=\(type(of: window))")
        }
```

Build, launch, open **Settings** (⌘,), close the main gallery window with ⌘W,
then click the scissors status item and press "Open Snippets" in the panel
footer. Read the probe output from Console.app or the launched process's stdout.

- **If the Settings window appears in the probe with `canBecomeMain=true`**, the
  bug is confirmed. Proceed: replace the filter in `activate()` so it only
  considers windows belonging to the main `WindowGroup`, using whatever
  identifier prefix the probe actually printed for the gallery window (SwiftUI
  derives it from `SnippetsApp.mainWindowID`, which is `"main"`):

  ```swift
    /// Bring the app forward, restoring a window if none is left.
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
        // `canBecomeMain` alone also matches the Settings window, which would
        // then be raised instead of the gallery — and the gallery would never
        // be restored at all, because a non-empty match skips `open?()`.
        let restorable = NSApp.windows.filter { window in
            window.canBecomeMain
                && window.identifier?.rawValue.hasPrefix(SnippetsApp.mainWindowID) == true
        }
        if restorable.isEmpty {
            open?()
        } else {
            for window in restorable { window.makeKeyAndOrderFront(nil) }
        }
    }
  ```

- **If the probe shows the Settings window with `canBecomeMain=false`**, or shows
  no identifier prefix matching `main` on the gallery window, STOP and report
  what the probe printed. Do not invent a different discriminator — the
  identifier scheme is the thing being verified, and a wrong guess here breaks
  window restoration entirely, which is worse than the bug being fixed.

**Remove the probe** before finishing, whichever branch you took.

**Verify**:
```sh
grep -n "\[probe\]" Sources/Snippets/Services/MenuBarController.swift
```
→ no matches.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

### Step 5: Re-run the step 0 repro against the fix

Rebuild, relaunch, and repeat step 0 exactly.

**Expected now**:
- ⌘W closes the window; app survives in the menu bar.
- Panel → select snippet → ⌘⏎ → the app comes forward **with that snippet
  open**.
- Repeating on the same snippet with a window already open still works (the
  flag was cleared).
- Panel → copy some code in another app → "Save as snippet" with no window
  open → the app comes forward with the new-snippet editor open and the
  captured code already in the code field.

Before trusting any of this, confirm you are looking at the new binary:
```sh
ps -o lstart,comm -p "$(pgrep -n Snippets)"
```
→ start time must be later than the mtime of the `Snippets.app` binary you
just built.

**Verify**: all four behaviours above observed. If the capture path still
fails while the reveal path works, STOP and report — that would mean
`CaptureDraft.shared.pending` is being cleared by something other than
`presentCapturedDraft`, which this plan does not account for.

## Test plan

**No new unit tests.** This is deliberate and you should not add any:

- Every affected symbol (`drainPendingWork`, `openPendingSnippet`, the `.task`
  and `onChange` modifiers) lives inside a SwiftUI `View` body or is a private
  method on a `View` struct. The `SnippetsTests` target has no SwiftUI view
  harness, and nothing in `Tests/SnippetsTests/` instantiates a view — the
  suite tests pure types and view models only. Adding a view-hosting harness is
  a much larger change than this fix and is out of scope.
- The pure logic that *could* be tested here (which flag wins, the ordering) is
  three `if` statements over three optionals; a test would restate the code.

The verification for this plan is the runtime repro in steps 0 and 5, which is
why step 0 requires you to record the failure before fixing it.

Existing tests must all still pass: `Tests/SnippetsTests/SnippetIntentLogicTests.swift`
covers the intent-side logic that writes these flags and is the suite most
likely to catch an accidental change to the navigator contract.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` exits 0
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` exits 0 with **389 tests, 0 failures**
- [ ] `grep -c "drainPendingWork" Sources/Snippets/Views/ContentView.swift` returns 2
- [ ] `grep -n "if navigator.pendingNewSnippet { presentNewSnippetFromIntent() }" Sources/Snippets/Views/ContentView.swift` returns no match inside the `.task` block (it moved into `drainPendingWork`)
- [ ] `grep -n "\[probe\]" Sources/Snippets/Services/MenuBarController.swift` returns no match
- [ ] `git status --porcelain` shows only `Sources/Snippets/Views/ContentView.swift`, `Sources/Snippets/Services/MenuBarController.swift`, and `plans/README.md` as modified
- [ ] Step 0's two failures were observed before the fix, and step 5's four behaviours after it
- [ ] `plans/README.md` status row for 011 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `ContentView.swift:753-760`, `:784-803`, or `:974-995`, or at
  `MenuBarController.swift:14-27` or `:172-195`, does not match the excerpts in
  "Current state".
- Step 0's reveal works correctly on the first try — the premise of this plan is
  wrong and steps 1–3 may be unnecessary.
- The app quits when you press ⌘W in step 0.
- The step 4 probe does not show the Settings window as `canBecomeMain=true`, or
  does not show a `main`-prefixed identifier on the gallery window.
- The test count comes back as anything other than 389, in either direction.
- The fix appears to require touching `QuickCopyPanel.swift`, `SnippetsApp.swift`,
  or `AppIntentNavigator.swift`.
- Step 5's capture path still fails after the reveal path is fixed.

## Maintenance notes

For whoever owns this code next:

- **`drainPendingWork` and the `onChange` handlers must stay in sync.** Any
  fourth "pending work" flag added to `AppIntentNavigator` or to a
  `*Draft.shared` singleton needs a line in *both* places. The two-places
  requirement is the sharp edge here; if a fourth flag arrives, consider making
  the navigator expose a single `drain()` that the view calls, rather than
  growing the pair.
- **Every handler must clear its own flag on all paths**, including the
  not-found path. `openPendingSnippet` clears unconditionally for this reason.
  A future edit that moves the clear inside the `if let match` block
  reintroduces the sticky half of this bug.
- **Reviewers should scrutinise**: the ordering inside `drainPendingWork` (last
  writer wins on `isPresentingNew`), and whether the step 4 identifier check
  survives an Xcode/SwiftUI upgrade — the identifier format is Apple's, not
  ours, and is the one part of this change that could silently stop matching.
  If it does stop matching, the symptom is "Open Snippets" doing nothing rather
  than opening the wrong window, because an empty `restorable` falls through to
  `open?()`.
- **Deferred out of this plan**: the panel's own auto-dismiss behaviour for
  clipboard-triggered opens (plan 012). It touches
  `MenuBarController.showPanel` and `hidePanel`, not the two functions changed
  here, but both plans edit `MenuBarController.swift` — land 011 first.

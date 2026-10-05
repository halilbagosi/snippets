# Plan 012: Auto-dismiss the quick-copy panel when the clipboard opened it

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 08bb49c3..HEAD -- Sources/Snippets/Services/MenuBarController.swift Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift`
> If either file changed since this plan was written, compare the "Current
> state" excerpts against the live code before proceeding; on a mismatch,
> treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: plans/011-quick-copy-window-handoff.md (same file — land 011 first)
- **Category**: bug
- **Planned at**: commit `08bb49c3`, 2026-07-31

## Why this matters

When the clipboard monitor catches copied code it opens the quick-copy panel
to offer "Save as snippet". That panel has no way to close itself, and it is a
borderless, non-movable window at `.statusBar` level with
`hidesOnDeactivate = false` — so it sits on top of every other application,
indefinitely, after any code you copy anywhere on the machine.

The mechanism is a gap between two individually-correct decisions.
`showPanel(capture:)` deliberately skips `NSApp.activate` and
`makeKeyAndOrderFront` for captures, so the panel cannot steal keystrokes from
whatever the user is typing in — right. Dismissal is handled by
`windowDidResignKey`, the way every menu bar panel behaves — also right. But a
window that was never key cannot resign key, so for the capture path the only
dismissal path is dead. The 6-second timer retires the banner and deliberately
leaves the panel up (commit `97b958f5`), on the reasoning that yanking the
surface would interrupt someone who ignored the capture and started searching —
which cannot happen on this path, because the panel does not have keyboard
focus and the user is typing somewhere else entirely.

There is a privacy edge too. For those first 6 seconds the banner renders up to
six lines of whatever was copied, and `CodeShapeHeuristics` classifies plenty
of things as "code" that you would not want left on screen — a `.env` line, a
private key, a token pasted out of a terminal. A panel that closes itself keeps
that exposure bounded to the moment it was meant to last.

An unrequested window pinned above every app is also just the wrong thing for a
menu bar utility to do. This is the single most visible defect in the
quick-copy feature.

## Current state

### The files

- `Sources/Snippets/Services/MenuBarController.swift` — owns the status item,
  the panel window, and every show/hide path.
- `Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift` — the panel's SwiftUI
  content, including the two `.task(id:)` timers.

### The panel is a floating, always-on-top window (`MenuBarController.swift:145-170`)

```swift
    private func existingOrNewPanel() -> NSPanel {
        if let panel { return panel }

        let created = QuickCopyPanelWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: QuickCopyPanel.panelWidth,
                height: QuickCopyPanel.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.level = .statusBar
        created.hidesOnDeactivate = false
        created.isMovable = false
        created.delegate = self
        // A borderless panel refuses key by default; the search field needs it.
        created.becomesKeyOnlyIfNeeded = false

        panel = created
        return created
    }
```

`.statusBar` level + `hidesOnDeactivate = false` + `isMovable = false` is what
makes a stuck panel so intrusive: it floats above other apps, does not hide
when Snippets deactivates, and cannot be dragged out of the way.

### The capture path never takes key (`MenuBarController.swift:87-127`)

```swift
    /// Present the panel. A non-nil `capture` means this was triggered by the
    /// clipboard monitor rather than a click, so the panel must NOT take key
    /// focus — it would swallow keystrokes meant for the app the user is in.
    func showPanel(capture: ClipboardCapture.Candidate?) {
        let model = existingOrNewModel()
        model.reload()
        model.pendingCapture = capture

        let panel = existingOrNewPanel()
        position(panel)
        // `hidePanel` fades the window itself out; the entrance is SwiftUI's,
        // so the window must be fully opaque again before it is shown.
        panel.alphaValue = 1

        // Rebuild the hosted view on every open. SwiftUI keeps the view tree
        // alive across order-out/order-front, so without this neither the
        // entrance animation nor the search-field focus would fire a second
        // time — the panel would open dead on its second use.
        panel.contentView = NSHostingView(rootView: makeRoot(model: model, panel: panel))

        panel.orderFront(nil)
        if capture == nil {
            // Clicking a status item does not activate the app, and a panel
            // that is key inside an inactive app still receives no keystrokes —
            // the search field would be dead. Activation is deliberately
            // skipped for captures, which must not steal focus from whatever
            // the user is typing in.
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13   // matches DSToken.Motion.popoverOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }
```

### The only automatic dismissal (`MenuBarController.swift:129-134`)

```swift
    // MARK: Window delegate

    /// Clicking away dismisses, the way every other menu bar panel behaves.
    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }
```

This is the dead path for captures: no key, so no resign.

### The 6-second timer retires only the banner (`QuickCopyPanel.swift:76-96`)

```swift
        .task(id: model.pendingCapture) {
            // A capture is a moment, not an inbox: if it is not acted on it
            // goes, so opening the panel later never shows a stale banner.
            //
            // Only the banner retires — not the panel. Dismissing the whole
            // surface here would yank it away mid-keystroke from someone who
            // ignored the capture and started searching.
            guard model.pendingCapture != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            model.pendingCapture = nil
        }
        .task(id: confirmingID) {
            // The confirmation is visible before the surface leaves. Tied to
            // the view's lifetime, so a reopened panel cancels a stale hold.
            guard confirmingID != nil else { return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            confirmingID = nil
            onDismiss()
        }
```

The `.task(id: confirmingID)` block immediately below is the **exemplar to
follow**: a timed hold that ends in `onDismiss()`, tied to the view's lifetime
so a reopened panel cancels a stale one. Match that shape.

### What must not break

`togglePanel` (`MenuBarController.swift:83-85`) is the status-item click path:

```swift
    func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel(capture: nil) }
    }
```

A stuck panel makes this misbehave too — the user clicks the scissors expecting
the panel to open and it closes instead. Fixing dismissal fixes that for free;
do not add special-casing here.

### Repo conventions to match

- Timers that affect the panel live in the SwiftUI layer as `.task(id:)`, not
  as detached `Task`s in the controller. Commit `97b958f5` moved them there
  precisely because a detached task outlived the view and dismissed a panel the
  user had already reopened. **Do not reintroduce a `DispatchQueue.main.asyncAfter`
  or a bare `Task { }` in `MenuBarController` for this.**
- Comments name the failure mode they prevent. See every excerpt above.
- Motion durations come from `DSToken.Motion` (`Sources/Snippets/DesignSystem/Tokens/DSMotion.swift`).
  `hidePanel`'s 0.13 is annotated as matching `DSToken.Motion.popoverOut`.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | exit 0, `** BUILD SUCCEEDED **` |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures |

There is **no** `Package.swift` in this repo. `swift build` and `swift test` do
not work here — `Snippets.xcodeproj` is the only build system.

## Suggested executor toolkit

- The repo ships a `verify` skill at `.claude/skills/verify` for building,
  launching and driving the app at runtime. Steps 0 and 4 require runtime
  observation; invoke it if available.
- `open` on an already-running build reuses the live process, so you can
  screenshot a stale binary. Check `ps -o lstart` against the built binary's
  mtime before trusting a runtime observation.

## Scope

**In scope** (the only files you should modify):
- `Sources/Snippets/Services/MenuBarController.swift`
- `Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift`

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Snippets/Services/ClipboardMonitor.swift` — the polling and the
  decision to show a panel are correct; only what happens to the panel
  afterwards is wrong. Whether the pasteboard *read* itself is acceptable on
  macOS 26 is plan 013's question, not this one.
- `Sources/Snippets/Features/QuickCapture/ClipboardCapture.swift` and
  `CodeShapeHeuristics.swift` — what counts as a capture is a separate concern
  and is well covered by tests.
- `Sources/Snippets/Views/QuickCopy/CaptureBanner.swift` — the banner's content
  and its Save/Dismiss buttons are correct.
- Do **not** make the capture path activate the app or take key focus. The
  comment at `MenuBarController.swift:109-113` explains why, and it is right:
  a panel that steals focus while someone is typing in another app is a worse
  bug than the one being fixed.
- Do **not** change the 6-second banner retirement to also close the panel
  unconditionally — that breaks the click path, where the user may well be
  mid-search. The fix must distinguish the two paths.

## Git workflow

- Branch: `advisor/012-capture-panel-auto-dismiss`
- Commit per logical unit. Message style, matching `git log`: short sentence-case
  imperative subject, blank line, body explaining the failure mode. Example
  from this repo:
  `Tie panel timers to view lifetime, and retire only the banner`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 0: Reproduce the stuck panel before changing anything

1. Build and launch the app.
2. Turn the feature on: **Settings (⌘,) → Preferences → "Offer to Save Copied
   Code"**. It is off by default.
3. Switch to another app (TextEdit is fine). Type and copy something the
   heuristics will accept as code — this works:
   ```
   func greet(name: String) -> String {
       return "hello \(name)"
   }
   ```
4. Observe the panel appear over the other app, with the capture banner.
5. **Do nothing.** Wait 15 seconds.

**Expected failure**: after ~6 seconds the banner disappears and the rest of
the panel stays — a search field, scope picker and snippet list floating above
your other app, with no visible way to close it. It stays through app switches
(because `hidesOnDeactivate = false`) and cannot be dragged aside (because
`isMovable = false`).

6. Click the scissors status item once.

**Expected failure**: the panel *closes* rather than opening, because
`togglePanel` saw it as already visible.

**Verify**: you have observed both. If the panel closes on its own within 15
seconds, STOP and report — the premise of this plan is wrong.

### Step 1: Tell the panel which path opened it

`QuickCopyPanel` currently cannot distinguish a click-opened panel from a
capture-opened one. It needs to, because the two want different timeout
behaviour. Add a stored property to `QuickCopyPanel` in
`Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift`, next to the existing
`scaleAnchor` / callback properties (around `:22-29`):

```swift
    /// True when the clipboard monitor opened this panel rather than a click.
    ///
    /// The two paths need different exits. A clicked panel is key, so clicking
    /// away resigns key and `windowDidResignKey` closes it. A capture-opened
    /// panel is deliberately never key — it must not take keystrokes from the
    /// app the user is typing in — so that path is dead for it and nothing
    /// would ever close it.
    let openedByCapture: Bool
```

Then pass it from `MenuBarController.makeRoot`. `makeRoot` currently takes
`(model:panel:)`; add the flag as a third parameter and thread it from
`showPanel`, which already knows (`capture != nil`):

```swift
        panel.contentView = NSHostingView(
            rootView: makeRoot(model: model, panel: panel, openedByCapture: capture != nil)
        )
```

```swift
    private func makeRoot(
        model: QuickCopyViewModel,
        panel: NSPanel,
        openedByCapture: Bool
    ) -> some View {
        QuickCopyPanel(
            model: model,
            scaleAnchor: scaleAnchor(for: panel),
            openedByCapture: openedByCapture,
            ...
```

Keep the remaining arguments exactly as they are. Note `QuickCopyPanel`'s
memberwise initializer is synthesised, so the property's position in the struct
determines the argument's position at the call site — put `openedByCapture`
after `scaleAnchor` and before `onDismiss` in both places, or the build will
tell you.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

### Step 2: Close a capture-opened panel when its banner retires

Modify the `.task(id: model.pendingCapture)` block at `QuickCopyPanel.swift:76-87`
so that on the capture path the whole panel goes, not just the banner:

```swift
        .task(id: model.pendingCapture) {
            // A capture is a moment, not an inbox: if it is not acted on it
            // goes, so opening the panel later never shows a stale banner.
            guard model.pendingCapture != nil else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            model.pendingCapture = nil

            // A clicked panel keeps standing: the user asked for it, is looking
            // at it, and may be mid-search — retiring an ignored banner is no
            // reason to take the surface away.
            //
            // A capture-opened panel has to go. It was never key, so
            // `windowDidResignKey` can never fire for it, and nothing else
            // closes it: it would float at `.statusBar` level over every other
            // app until the user found the status item. Nobody asked for this
            // window, so its welcome expires with the offer that raised it.
            if openedByCapture { onDismiss() }
        }
```

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
grep -n "openedByCapture" Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift Sources/Snippets/Services/MenuBarController.swift
```
→ 5 matching lines total: 2 in `QuickCopyPanel.swift` (the property declaration
and the use in step 2's `.task`) and 3 in `MenuBarController.swift` (the
`makeRoot` parameter, the `QuickCopyPanel(...)` argument, and the `showPanel`
call site).

### Step 3: Keep the timer alive when the user engages with the panel

A capture-opened panel the user *does* click becomes key. From that moment
`windowDidResignKey` works and the normal rules apply — the 6-second dismissal
would now yank the surface out from under someone who is actually using it,
which is exactly the regression commit `97b958f5` fixed for the click path.

Cancel the auto-dismissal once the panel takes key. In `MenuBarController`, add
the counterpart to the existing `windowDidResignKey`:

```swift
    /// A capture-opened panel that the user clicks into is no longer an
    /// unrequested window — it is one they are using, and it now has a working
    /// resign-key exit. Clearing the pending capture ends the 6-second hold in
    /// `QuickCopyPanel`, so engaging with the panel keeps it.
    func windowDidBecomeKey(_ notification: Notification) {
        model?.pendingCapture = nil
    }
```

`model` is already a stored property on the controller
(`MenuBarController.swift:63`), and `MenuBarController` is already the panel's
`delegate` (`:164`) and conforms to `NSWindowDelegate` (`:58`), so no new wiring
is needed.

Clearing `pendingCapture` changes the `.task(id:)` identity, which cancels the
sleeping task — the same cancellation mechanism the confirmation hold relies
on. It also retires the banner immediately on click, which is the right
behaviour: the user has seen it and chosen to do something else.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```
→ exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures.

### Step 4: Verify all four panel behaviours at runtime

Rebuild, relaunch, confirm you are on the new binary:
```sh
ps -o lstart,comm -p "$(pgrep -n Snippets)"
```
→ start time later than the built binary's mtime.

With "Offer to Save Copied Code" enabled, check each:

1. **Ignored capture closes itself.** Copy code in another app, do nothing. The
   banner goes at ~6s and the panel goes with it. Nothing is left on screen.
2. **Engaged capture stays.** Copy code in another app, then click into the
   panel's search field within 6 seconds and type. The panel stays; the banner
   goes. Typing is not interrupted. Clicking away closes it.
3. **Saved capture still works.** Copy code, click "Save as snippet". The main
   window comes forward with the new-snippet editor holding the captured code,
   and the panel closes. (If this fails and plan 011 is not yet landed, that is
   011's bug, not this one — note it and continue.)
4. **Click path unchanged.** Click the scissors status item. The panel opens,
   the search field has focus, and it stays open indefinitely while you search.
   It closes on Escape, on clicking away, and on clicking the status item again.

**Verify**: all four observed. Behaviour 4 is the regression check — if a
clicked panel now closes itself after 6 seconds, `openedByCapture` is being
passed as `true` on the click path; recheck the `capture != nil` argument in
step 1.

## Test plan

**No new unit tests.** Deliberately, and you should not add any:

- Everything changed here is either an `NSWindowDelegate` callback on a
  `@MainActor` AppKit controller driven by real window key-state transitions, or
  a `.task(id:)` inside a SwiftUI view body. `Tests/SnippetsTests/` contains no
  AppKit window harness and no SwiftUI view harness — the suite covers pure
  types and view models only, which is why `ClipboardCapture`, `QuickCopyResults`
  and `QuickCopySelection` were extracted as pure types in the first place.
- The one testable thing this touches, `QuickCopyViewModel.pendingCapture`, is a
  plain stored property; a test would assert that assignment assigns.

The verification for this plan is the step 4 runtime matrix, which is why it
enumerates four cases including an explicit regression check on the path that
already worked.

Existing tests must all still pass, in particular
`Tests/SnippetsTests/QuickCopyViewModelTests.swift` and
`Tests/SnippetsTests/ClipboardCaptureTests.swift`.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` exits 0
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` exits 0 with **389 tests, 0 failures**
- [ ] `grep -c "openedByCapture" Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift` returns 2 (the property declaration and the `if` in the `.task`)
- [ ] `grep -c "openedByCapture" Sources/Snippets/Services/MenuBarController.swift` returns 3 (the `makeRoot` parameter, the `QuickCopyPanel(...)` argument, and the `showPanel` call site)
- [ ] `grep -n "windowDidBecomeKey" Sources/Snippets/Services/MenuBarController.swift` returns exactly 1 match
- [ ] `grep -n "asyncAfter\|Task {" Sources/Snippets/Services/MenuBarController.swift` returns no match (no detached timers reintroduced)
- [ ] Step 0's two failures observed before the fix; step 4's four behaviours after it
- [ ] `git status --porcelain` shows only `Sources/Snippets/Services/MenuBarController.swift`, `Sources/Snippets/Views/QuickCopy/QuickCopyPanel.swift`, and `plans/README.md` as modified
- [ ] `plans/README.md` status row for 012 updated

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `MenuBarController.swift:87-134` or `:145-170`, or at
  `QuickCopyPanel.swift:76-96`, does not match the excerpts in "Current state".
- In step 0 the panel closes itself within 15 seconds — the premise is wrong.
- After step 3, a *clicked* panel closes itself after 6 seconds. Do not paper
  over it with a longer timeout; find why `openedByCapture` is true on that path.
- `windowDidBecomeKey` fires for the click path in a way that breaks
  search-field focus (symptom: the search field stops accepting keystrokes on a
  clicked panel).
- The test count comes back as anything other than 389.
- You find yourself wanting to activate the app or make the panel key on the
  capture path to get dismissal working. That is explicitly out of scope —
  report instead.

## Maintenance notes

For whoever owns this code next:

- **The panel now has two lifecycles, and the distinguishing flag is passed at
  construction.** Any future third way of opening the panel (a global hotkey is
  the obvious candidate — see the direction notes in `plans/README.md`) must
  decide which lifecycle it wants. A hotkey-opened panel should behave like the
  click path: `openedByCapture: false`, key focus, no timeout.
- **`windowDidBecomeKey` clearing `pendingCapture` is load-bearing in two ways**
  — it cancels the dismissal *and* retires the banner. If someone later wants
  the banner to survive a click, they need a separate flag for "user engaged"
  rather than reusing `pendingCapture`, or the auto-dismissal comes back.
- **Reviewers should scrutinise**: that the capture path still never calls
  `NSApp.activate` or `makeKeyAndOrderFront` (grep `showPanel`), and that no
  detached `Task`/`asyncAfter` timer crept back into `MenuBarController` — that
  regression cost a fix once already (`97b958f5`).
- **Deferred out of this plan**: whether 6 seconds is the right window at all,
  and whether an ignored capture should be recoverable afterwards (today it is
  simply gone). A short capture history is recorded as a direction option in
  `plans/README.md`; it would change this timer's meaning, so revisit this file
  if that is ever built.

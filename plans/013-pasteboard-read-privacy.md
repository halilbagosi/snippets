# Plan 013: Determine whether macOS gates ClipboardMonitor's pasteboard reads

> **Executor instructions**: This is an **investigation plan**. Its deliverable
> is a measured answer written down, and a code change only if the measurement
> says one is needed. Do not skip to implementing a fix. Run every verification
> command and confirm the expected result before moving to the next step. If
> anything in the "STOP conditions" section occurs, stop and report. When done,
> update the status row for this plan in `plans/README.md` — unless a reviewer
> dispatched you and told you they maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 08bb49c3..HEAD -- Sources/Snippets/Services/ClipboardMonitor.swift`
> If the file changed since this plan was written, compare the "Current state"
> excerpt against the live code before proceeding; on a mismatch, treat it as a
> STOP condition.

## Status

- **Priority**: P1
- **Effort**: M (the measurement is most of the work)
- **Risk**: LOW (investigation) / MED (if it leads to a redesign)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `08bb49c3`, 2026-07-31

## Why this matters

`ClipboardMonitor` polls the general pasteboard once a second and, on every
change, reads the pasteboard's **contents** — not just its metadata — outside
of any user paste action. macOS 15 introduced a system alert for exactly that
pattern: an app that reads pasteboard data the user did not explicitly paste
gets a "…would like to paste from…" prompt. This app targets macOS 26.

If that gating applies here, the feature is not merely imperfect — it is
unusable in the shape it currently has. Every time the user copies code
anywhere on the machine they would get a system modal, which is worse than not
having the feature. If it does not apply (the app is unsandboxed with no
hardened runtime, and the gating rules have exceptions), then there is nothing
to fix and the finding should be closed so nobody re-audits it.

Nobody has measured this. The feature's own security notes
(`Docs/security-overview.md`) do not mention it, and the runtime verification
recorded there predates the clipboard monitor. The honest state is "unknown",
and the cost of the two possible answers is very different, which is why this
gets its own plan instead of a speculative fix.

## Current state

### The file

- `Sources/Snippets/Services/ClipboardMonitor.swift` — 78 lines, the only code
  that reads the pasteboard. Every accept/reject decision lives in
  `ClipboardCapture`; this type is purely mechanism.

### The read (`ClipboardMonitor.swift:61-76`)

```swift
    private func poll() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let candidate = ClipboardCapture.candidate(
            text: pasteboard.string(forType: .string),
            types: types,
            isOwnWrite: current == Clipboard.lastLocalChangeCount
        )

        guard let candidate else { return }
        MenuBarController.shared.showPanel(capture: candidate)
    }
```

Three distinct pasteboard accesses per change, and they are **not** equivalent
for privacy purposes — this distinction is the crux of the investigation:

- `pasteboard.changeCount` — a counter, not content. Polled every second
  regardless.
- `pasteboard.types` — metadata: which representations exist. Read once per
  change.
- `pasteboard.string(forType: .string)` — **the actual clipboard contents**.
  Read once per change. This is the call the macOS gating targets.

### The polling loop (`ClipboardMonitor.swift:44-59`)

```swift
    /// Begin polling if enabled. Safe to call repeatedly.
    func start() {
        guard isEnabled, timer == nil else { return }
        lastSeenChangeCount = NSPasteboard.general.changeCount

        let created = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in ClipboardMonitor.shared.poll() }
        }
        created.tolerance = Self.interval / 2
        timer = created
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
```

`Self.interval` is `1.0` (`:27`).

### The feature is opt-in and off by default (`ClipboardMonitor.swift:23-35`)

```swift
    /// Opt-in, and off by default: the app should not start reading the
    /// clipboard because it was launched.
    static let enabledDefaultsKey = "quickCapture.enabled"

    private static let interval: TimeInterval = 1.0

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            isEnabled ? start() : stop()
        }
    }
```

The toggle is at **Settings → Preferences → "Offer to Save Copied Code"**
(`Sources/Snippets/Views/Settings/AppearanceView.swift:226-229`). You must turn
it on to measure anything.

### App configuration relevant to the question

From `Docs/security-overview.md` §1: the app is unsandboxed
(`ENABLE_APP_SANDBOX = NO` in all four build configs), has no entitlements
file, and the hardened runtime is unset. Whether any of that changes the
pasteboard gating is part of what you are measuring — do not assume it does.

### Repo conventions to match

- Findings and decisions about security/privacy posture are written up in
  `Docs/security-overview.md`, which is a working document (untracked —
  `Docs/` is in `.gitignore`). It is organised as: what was fixed, what was
  reported but wrong, residual risk, and what was verified. Match that voice —
  plain, specific, willing to say "this was reported and it is false".
- Comments in `ClipboardMonitor.swift` explain *why* a mechanism was chosen:
  "macOS has no clipboard-change notification, so polling `changeCount` is the
  only mechanism available." Any new comment should meet that bar.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | exit 0, `** BUILD SUCCEEDED **` |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures |
| OS version | `sw_vers` | records the exact OS the measurement was taken on |

There is **no** `Package.swift` in this repo. `swift build` and `swift test` do
not work here — `Snippets.xcodeproj` is the only build system.

## Suggested executor toolkit

- The repo ships a `verify` skill at `.claude/skills/verify` for building,
  launching and driving the app at runtime. This entire plan is runtime work;
  invoke it if available.
- `open` on an already-running build reuses the live process — you can easily
  measure a stale binary. Check `ps -o lstart` against the built binary's mtime
  before trusting any observation. This exact mistake is recorded in
  `Docs/security-overview.md` §5.

## Scope

**In scope**:
- `Docs/security-overview.md` (append a section — this is the primary deliverable)
- `Sources/Snippets/Services/ClipboardMonitor.swift` (**only if** step 2 finds
  gating; otherwise a comment recording the measurement)

**Out of scope** (do NOT touch):
- `Sources/Snippets/Features/QuickCapture/ClipboardCapture.swift` and
  `CodeShapeHeuristics.swift` — the accept/reject policy is not what is being
  measured, and it is well covered by tests.
- `Sources/Snippets/Services/MenuBarController.swift` and
  `Sources/Snippets/Views/QuickCopy/*` — panel behaviour is plans 011 and 012.
- Build settings, entitlements, sandbox or hardened-runtime configuration. If
  the measurement suggests changing any of them, that is a finding to report,
  **not** a change to make: `Docs/security-overview.md` §4 item 2 records that
  the sandbox and hardened runtime are deliberately coupled to the Swift
  preview design (`plans/005-design-output.md`), and flipping them here would
  break the Swift preview outright.
- Do **not** remove or disable the clipboard feature as a "fix". If it turns out
  to be gated, the deliverable is a written recommendation, not a deletion.

## Git workflow

- Branch: `advisor/013-pasteboard-read-privacy`
- Commit the write-up separately from any code change, so the measurement
  survives even if the code change is later reverted.
- Message style, matching `git log`: short sentence-case imperative subject,
  blank line, body. Example from this repo: `Add clipboard capture primitives and self-write suppression`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Record the environment

```sh
sw_vers
```

Write down `ProductVersion` and `BuildVersion`. Every conclusion in this plan is
only valid for that OS build, and the write-up must say so — this behaviour is
Apple's and can change between releases.

**Verify**: you have the exact version string recorded.

### Step 2: Measure whether a system alert appears

1. Build and launch the app. Confirm you are on the new binary:
   ```sh
   ps -o lstart,comm -p "$(pgrep -n Snippets)"
   ```
   → start time later than the built binary's mtime.
2. Enable **Settings (⌘,) → Preferences → "Offer to Save Copied Code"**.
3. Switch to another app (TextEdit works). Copy something the heuristics accept
   as code:
   ```
   func greet(name: String) -> String {
       return "hello \(name)"
   }
   ```
4. Observe carefully, in this order:
   - Does a **system alert** appear naming Snippets and the source app
     ("…would like to paste from…")? Note its exact wording.
   - Does the quick-copy panel appear with the capture banner?
5. Copy a **second, different** code block from the same app. Note whether the
   alert appears again, or only once.
6. Copy a code block from a **third, different** app. Note whether the alert
   appears again.
7. Quit and relaunch Snippets, copy again. Note whether the alert returns after
   a restart.

Record all four observations. The per-source and per-launch behaviour matters:
an alert once per app per launch is a very different product problem from an
alert on every copy.

**Verify**: you can state, in one sentence each, what happens on first copy,
repeat copy from the same app, copy from a new app, and after relaunch.

**Branch here:**

- **No alert in any of the four cases** → go to step 3A.
- **An alert in any case** → go to step 3B.

### Step 3A: Record that the read is not gated, and close the finding

No code change is needed. Add a short comment above `poll()` in
`Sources/Snippets/Services/ClipboardMonitor.swift` recording the measurement,
in the file's existing voice:

```swift
    /// Reads the pasteboard's contents, not just its metadata.
    ///
    /// Measured on macOS <version> (build <build>): this does not trigger the
    /// system paste-permission alert for this app. Re-measure on a major OS
    /// update — the gating is Apple's and the feature stops being viable if it
    /// ever starts applying here. See `Docs/security-overview.md`.
    private func poll() {
```

Then append a section to `Docs/security-overview.md` under §5 "Verified",
stating: what was measured, the exact OS version and build, the four
observations from step 2, and the conclusion. Keep it to a short paragraph plus
the four observations — that document is dense on purpose.

**Verify**:
```sh
grep -n "paste-permission alert" Sources/Snippets/Services/ClipboardMonitor.swift
```
→ 1 match.

```sh
grep -c "macOS" Docs/security-overview.md
```
→ increased by at least 1 versus before your edit.

Then go to step 4.

### Step 3B: Write up the gating and recommend, do not redesign

Do **not** implement a redesign in this plan. The right answer depends on
product judgment about a feature the operator owns, and the options have very
different costs. Append a section to `Docs/security-overview.md` covering:

- **What was measured**: the four observations, verbatim, with OS version and
  build.
- **What it costs**: how many alerts a normal day of copying produces.
- **The options**, with the trade-off stated for each. At minimum these three:
  1. **Read contents only when the panel is already open.** `changeCount` and
     `types` are metadata and are very unlikely to be gated; the monitor could
     track that a change happened and read the string only when the user opens
     the panel themselves. Cost: no proactive banner — the feature becomes
     "the panel offers to save what you last copied" rather than "a prompt
     appears when you copy". That is a real product change.
  2. **`NSPasteboard.detectPatterns(for:)`** (macOS 13+) reports which patterns
     a pasteboard item matches without handing over contents, and is designed
     for exactly this gating. Verify whether any available pattern is a useful
     proxy for "this is code" — `NSPasteboard.DetectionPattern` is a fixed
     Apple-defined set, so the honest answer may be "none of them are", in
     which case say so.
  3. **Accept the alert** and make the settings caption say so plainly, so the
     user opts in knowing what they are opting into. The existing caption is at
     `Sources/Snippets/Views/Settings/AppearanceView.swift:229`.
- **Your recommendation**, with reasoning, in two or three sentences.

Add the same measurement comment above `poll()` as in step 3A, with the
opposite conclusion.

**Verify**:
```sh
grep -n "detectPatterns" Docs/security-overview.md
```
→ at least 1 match (option 2 is discussed).

Then go to step 4.

### Step 4: Confirm nothing regressed

You should have changed no behaviour in either branch.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```
→ exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures.

```sh
git diff --stat
```
→ `Sources/Snippets/Services/ClipboardMonitor.swift` shows comment-only changes
(no changed line contains a statement), and no source file other than that one
is modified. `Docs/` is gitignored and will not appear — that is expected;
confirm the file changed with `ls -l Docs/security-overview.md`.

## Test plan

**No new unit tests.** The thing under investigation is an OS permission
behaviour observed at runtime; there is nothing to assert in a unit test, and
`ClipboardCapture`'s decision logic — the part that *is* testable — is already
covered by the nine cases in `Tests/SnippetsTests/ClipboardCaptureTests.swift`.

If step 3B leads to a future redesign (option 1 in particular changes when the
read happens), that follow-up work should add tests for the new sequencing. It
is out of scope here.

Existing tests must all still pass, unchanged at 389.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] The OS version and build from step 1 are recorded in `Docs/security-overview.md`
- [ ] All four step-2 observations are recorded in `Docs/security-overview.md`
- [ ] `grep -n "paste-permission alert" Sources/Snippets/Services/ClipboardMonitor.swift` returns 1 match
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` exits 0 with **389 tests, 0 failures**
- [ ] `git diff -- Sources/` shows comment-only changes
- [ ] `git status --porcelain` shows only `Sources/Snippets/Services/ClipboardMonitor.swift` and `plans/README.md` as modified
- [ ] If step 3B was taken: a recommendation with reasoning is written, and **no**
      redesign has been implemented
- [ ] `plans/README.md` status row for 013 updated, including which branch (3A or
      3B) was taken

## STOP conditions

Stop and report back (do not improvise) if:

- The code at `ClipboardMonitor.swift:44-76` does not match the excerpts in
  "Current state".
- You cannot get the capture to fire at all (no panel, no alert) — that is a
  different bug and this measurement cannot be taken until it is fixed. Check
  first that the Settings toggle is on and that you are not copying *from*
  Snippets (self-writes are suppressed by design, see
  `Clipboard.lastLocalChangeCount`).
- The alert appears but dismissing it crashes or hangs the app.
- You find yourself changing `poll()`'s logic, the polling interval, or any
  build setting. This plan produces a measurement and a comment; anything more
  is a separate decision.
- Step 2's observations are inconsistent between runs — report the inconsistency
  rather than picking whichever run suits a conclusion.

## Maintenance notes

For whoever owns this code next:

- **This conclusion has an expiry date.** Pasteboard privacy gating is Apple's
  and has changed at least once (macOS 15 introduced it). Re-measure on every
  major macOS release; the comment added above `poll()` names the version it
  was measured on so a reader knows when it went stale.
- **The three pasteboard accesses in `poll()` are not equivalent** and should
  stay distinguishable in the code. If someone consolidates them into a single
  helper, the distinction between "read the counter", "read the metadata" and
  "read the contents" is lost, and it is exactly that distinction that any
  future mitigation depends on.
- **Reviewers should scrutinise**: that this plan's diff really is comment-only
  in `Sources/`. An executor that quietly implemented option 1 or 2 has made a
  product decision that was not theirs to make.
- **Deferred out of this plan**: implementing any mitigation. If step 3B fired,
  the operator should decide between the three options before a follow-up plan
  is written.

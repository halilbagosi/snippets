# Plan 014: Funnel every copy path through `SnippetStore.recordCopy`

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**:
> `git diff --stat 08bb49c3..HEAD -- Sources/Snippets/Views/Components/SnippetCard.swift Sources/Snippets/Views/SnippetDetailView.swift Sources/Snippets/Intents/SnippetStore.swift`
> If any of these three files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: tech-debt
- **Planned at**: commit `08bb49c3`, 2026-07-31

## Why this matters

`SnippetStore.recordCopy` calls itself "the single definition of copy
bookkeeping" and states, in its own doc comment, that "every copy path in the
app must come through here or that scope drifts away from real use". That
invariant is false today. The app has four copy paths; two of them
(`SnippetCard`, `SnippetDetailView`) duplicate `snippet.copyCount += 1` inline
and never call `recordCopy`, so the doc comment documents an intention rather
than a fact — and those are the two paths the user hits most, since they are
the gallery card's copy chip and the detail view's copy chip.

Be precise about the cost, because it is smaller than it looks. The SwiftData
`mainContext` handed to the view tree by `.modelContainer(...)`
(`Sources/Snippets/SnippetsApp.swift:173`) autosaves, so the inline increments
do reach disk in practice; the explicit `try? context.save()` inside
`recordCopy` is a durability *narrowing* (the write happens now rather than at
the next autosave), not the difference between counted and lost. **This is a
consistency and drift problem, not a confirmed data-loss bug — do not write the
commit message as if counts are being lost.** The concrete exposure is a crash
or force-quit between an inline increment and the next autosave, which loses at
most that one increment.

What actually improves is that the invariant becomes true and stays true. Right
now the bookkeeping rule is enforced only by a comment, and the comment is
already wrong — so the next person adding a copy affordance has a 50/50 chance
of copying the wrong pattern. `copyCount` has two live consumers today, both
silently downstream of this: the quick-copy panel's "Frequent" scope
(`Sources/Snippets/Features/QuickCopy/QuickCopyResults.swift:50` and `:89`) and
the main window's "Frequently used" sidebar section
(`Sources/Snippets/Views/ContentView.swift:375-421`). Any future change to what
"a copy" means — a timestamp, a decay window, a `lastCopiedAt`, a cap — has to
land in one function, and after this plan it can.

## Current state

### The files

- `Sources/Snippets/Intents/SnippetStore.swift` — `@MainActor enum` holding the
  shared, uuid-keyed lookups for intents, and `recordCopy` (`:26-38`). Not
  modified by this plan; it is the destination.
- `Sources/Snippets/Views/Components/SnippetCard.swift` — the gallery card.
  `performCopy()` at `:58-73` is bypass site #1.
- `Sources/Snippets/Views/SnippetDetailView.swift` — the detail pane. The copy
  `FilterTag` action inside `actionBar` at `:197-211` is bypass site #2.
- `Sources/Snippets/Services/Clipboard.swift` — the pasteboard write. **Not in
  scope, and not broken** (see "What must not break").

### The definition being bypassed (`SnippetStore.swift:26-38`)

```swift
    /// Record that a snippet's code was copied.
    ///
    /// The single definition of copy bookkeeping, shared by the App Intent
    /// (which looks the snippet up by uuid first) and the menu bar panel
    /// (which already holds the model). `updatedAt` is deliberately untouched:
    /// the gallery orders by it, and copying should not reshuffle the grid.
    ///
    /// `copyCount` feeds the panel's "Frequent" scope, so every copy path in
    /// the app must come through here or that scope drifts away from real use.
    static func recordCopy(_ snippet: Snippet, in context: ModelContext) {
        snippet.copyCount += 1
        try? context.save()
    }
```

`SnippetStore` is declared `@MainActor` (`SnippetStore.swift:17-18`), so
`recordCopy` is main-actor isolated. Both new call sites are already on the main
actor (a SwiftUI `View` conformance carries `@MainActor` onto the whole type,
and both already call the `@MainActor` `Clipboard.copy`), so **no `await`, no
`Task`, and no isolation annotation is needed anywhere in this plan.** If the
compiler asks for one, something else is wrong — see STOP conditions.

### Bypass site #1 — `SnippetCard.swift:58-73`

```swift
    private func performCopy() {
        Clipboard.copy(snippet.code)
        snippet.copyCount += 1
        withAnimation(DSToken.Motion.toggle) {
            didCopy = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled {
                withAnimation(DSToken.Motion.toggle) {
                    didCopy = false
                }
            }
        }
    }
```

`SnippetCard` is declared at `SnippetCard.swift:8`. Its environment properties
are at `:9-11` and **do not include a model context**:

```swift
struct SnippetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppearanceSettings.self) private var appearanceSettings
```

It already has `import SwiftData` at `:6`, so no new import is required — only
the environment property.

The card's single call site is `Sources/Snippets/Views/SnippetGalleryView.swift:638`,
reached from `ContentView.swift:519` and `TrashView.swift:59`, both inside the
window whose root applies `.modelContainer(SnippetsData.sharedModelContainer)`
(`SnippetsApp.swift:173`). So `\.modelContext` resolves to the shared
`mainContext` — the same context every other copy path already writes through.
There are no `#Preview` blocks in `SnippetCard.swift`, so nothing renders this
view outside that container.

### Bypass site #2 — `SnippetDetailView.swift:196-212`

```swift
    private var actionBar: some View {
        HStack(spacing: 8) {
            FilterTag(
                label: didCopy ? "copied" : "copy",
                icon: didCopy ? "checkmark" : "doc.on.doc",
                accent: didCopy ? .blue : theme.textMuted,
                isSelected: didCopy
            ) {
                Clipboard.copy(snippet.code)
                snippet.copyCount += 1
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    didCopy = false
                }
            }
```

`SnippetDetailView` **already declares** the environment property, at
`SnippetDetailView.swift:10`:

```swift
    @Environment(\.modelContext) private var modelContext
```

At the time of writing that property is declared and never read anywhere in the
file — this plan gives it its first use. Do **not** add a second one, and do not
"clean up" the existing declaration.

### The two correct callers — copy this shape

`Sources/Snippets/Features/QuickCopy/QuickCopyViewModel.swift:76-83`:

```swift
    /// Copy the highlighted snippet's code and record it. Returns the snippet
    /// so the view can show its confirmation, or nil when nothing is selected.
    func copySelected() -> Snippet? {
        guard let snippet = selectedSnippet else { return nil }
        Clipboard.copy(snippet.code)
        SnippetStore.recordCopy(snippet, in: context)
        return snippet
    }
```

`Sources/Snippets/Intents/Actions/CopySnippetIntent.swift:26-35`:

```swift
    /// Lookup + bookkeeping, context-injected for tests. The clipboard write
    /// stays in `perform()`.
    @MainActor
    static func execute(snippetID: UUID, in context: ModelContext) throws -> Snippet {
        guard let model = try SnippetStore.snippet(uuid: snippetID, in: context) else {
            throw SnippetIntentError.snippetNotFound
        }
        SnippetStore.recordCopy(model, in: context)
        return model
    }
```

Note the ordering both of them use: **pasteboard write first, then
`recordCopy`.** Preserve that order at both new call sites — it matches the two
existing correct paths and keeps the clipboard write off the critical path of a
`save()` that could throw internally.

### What must not break

**`Clipboard.copy` is not broken and must not be touched.**
`Sources/Snippets/Services/Clipboard.swift:6-24`:

```swift
@MainActor
enum Clipboard {
    /// `changeCount` produced by our own most recent write.
    ///
    /// The capture monitor compares against this so copying *from* Snippets
    /// never prompts the user to save a snippet they already have. Every copy
    /// path in the app funnels through `copy(_:)`, so recording it here covers
    /// all of them from one place.
    private(set) static var lastLocalChangeCount: Int = -1
```

All four copy paths already funnel through it correctly — that comment *is*
true. `lastLocalChangeCount` is what stops the clipboard monitor from offering
to save code the user copied out of Snippets itself. Every step below keeps
`Clipboard.copy(snippet.code)` exactly where it is, on the line it is on.

**The `didCopy` feedback state must not change.** The card's
`copyResetTask` / `withAnimation(DSToken.Motion.toggle)` dance and the detail
view's `DispatchQueue.main.asyncAfter(deadline: .now() + 1.5)` are both
untouched by this plan, including the 1.4s vs 1.5s difference between them.
That inconsistency is real and is explicitly deferred (see "Maintenance
notes") — fixing it here would make the diff about two things.

**`updatedAt` must stay untouched.** `recordCopy` deliberately does not bump it,
because the gallery orders by it (`SnippetStore.swift:30-31`) and copying must
not reshuffle the grid. The inline sites don't bump it either, so this is a
no-change — just do not "improve" `recordCopy` while you are in there.

### Repo conventions to match

- **Comments name the failure mode they prevent**, not what the line does. See
  every excerpt above, especially `Clipboard.swift:8-13`.
- **Shared bookkeeping lives in `SnippetStore`**, and views/view models call it
  with their own context; the context is always passed in, never fetched from a
  global inside the helper. That is why `recordCopy` takes `in context:`.
- **File registration**: the Xcode project enumerates files explicitly (see
  `CLAUDE.md`). This plan adds **no** new files. If you find yourself creating
  one anyway, it must be registered in `Snippets.xcodeproj/project.pbxproj` —
  under `Sources/` for the `Snippets` target, under `Tests/SnippetsTests/` for
  the `SnippetsTests` target — or it will exist on disk and never be compiled,
  and your "passing" test run will be meaningless.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | exit 0, `** BUILD SUCCEEDED **` |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | exit 0, `** TEST SUCCEEDED **`, 389 tests, 0 failures |
| Invariant | `grep -rn "copyCount += 1" Sources` | exactly 1 line, in `SnippetStore.swift` |

There is **no** `Package.swift` in this repo. `swift build` and `swift test` do
not work here — `Snippets.xcodeproj` is the only build system. The full Xcode
(beta) toolchain is required because SwiftData macros do not expand under the
Command Line Tools alone, which is why every command carries `DEVELOPER_DIR`.

## Suggested executor toolkit

- The repo ships a `verify` skill at `.claude/skills/verify` for building,
  launching and driving the app at runtime. Step 4 is a runtime regression
  check; invoke it if available.
- `open` on an already-running build reuses the live process, so you can
  screenshot a stale binary. Check `ps -o lstart` against the built binary's
  mtime before trusting a runtime observation.

## Scope

**In scope** (the only files you should modify):
- `Sources/Snippets/Views/Components/SnippetCard.swift`
- `Sources/Snippets/Views/SnippetDetailView.swift`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Snippets/Intents/SnippetStore.swift` — `recordCopy` is the
  destination, not the subject. Its body, its signature and its doc comment all
  stay byte-for-byte as they are. The doc comment becomes true as a result of
  this plan; that is the point.
- `Sources/Snippets/Services/Clipboard.swift` — correct today (see "What must
  not break"). Do not move the pasteboard write into `recordCopy`, do not add a
  `Clipboard.copy` call inside `recordCopy`, and do not merge the two into one
  helper. The App Intent deliberately splits them (`CopySnippetIntent.swift:26-27`:
  the clipboard write stays in `perform()` so `execute` stays testable), and
  merging them would break that test seam.
- `Sources/Snippets/Features/QuickCopy/QuickCopyViewModel.swift` and
  `Sources/Snippets/Intents/Actions/CopySnippetIntent.swift` — already correct;
  they are the exemplars.
- The `didCopy` reset timings (1.4s in the card, 1.5s in the detail view), the
  `DispatchQueue.main.asyncAfter` in `SnippetDetailView`, and the
  `copyResetTask` in `SnippetCard`. All deferred.
- `Sources/Snippets/Views/SnippetGalleryView.swift` — had uncommitted working-tree
  changes at planning time and hosts the card, but needs no change here:
  `SnippetCard`'s initializer is not touched, only its private environment.

## Git workflow

- Branch: `advisor/014-record-copy-funnel`
- One commit is right for this change. Message style, matching `git log`: short
  sentence-case imperative subject, blank line, body explaining the failure
  mode. Example subjects from this repo:
  `Tie panel timers to view lifetime, and retire only the banner`,
  `Fix three defects found in runtime verification`.
  A fitting subject here: `Route the card and detail copy chips through recordCopy`.
  In the body, describe the drift risk honestly (a documented invariant that two
  of four call sites violated), not a data-loss claim the autosave contradicts.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 0: Confirm both bypasses exist before changing anything

```sh
grep -rn "copyCount += 1" Sources
```

→ **exactly 3 lines**:
```
Sources/Snippets/Views/SnippetDetailView.swift:206:                snippet.copyCount += 1
Sources/Snippets/Views/Components/SnippetCard.swift:60:        snippet.copyCount += 1
Sources/Snippets/Intents/SnippetStore.swift:36:        snippet.copyCount += 1
```

```sh
grep -rn "SnippetStore.recordCopy(" Sources
```

→ **exactly 2 lines**, in `QuickCopyViewModel.swift` and `CopySnippetIntent.swift`.

**Verify**: both counts match. If `grep -rn "copyCount += 1" Sources` already
returns 1, this plan has already been executed (or the code drifted) — STOP and
report rather than editing anything.

### Step 1: Give `SnippetCard` a model context

In `Sources/Snippets/Views/Components/SnippetCard.swift`, add the environment
property to the block at `:9-11`, immediately after `appearanceSettings`:

```swift
struct SnippetCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.modelContext) private var modelContext
```

`import SwiftData` is already present at `:6`; do not add it again. Do not
change any of the `let`/`var` initializer properties below it (`snippet`,
`isSelected`, `inTrashView`, …) — `SnippetCard` uses the synthesised memberwise
initializer at `SnippetGalleryView.swift:638`, and reordering or adding a
stored property there would change that call site. `@Environment` properties are
not part of the memberwise initializer, so adding this one is call-site safe.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

(An unused `@Environment` property produces no warning, so a clean build here
confirms the property compiles and `SnippetGalleryView` still constructs the
card.)

### Step 2: Route the card's copy chip through `recordCopy`

Replace the inline increment at `SnippetCard.swift:60`. The only line that
changes is the increment — `Clipboard.copy(snippet.code)` stays first, and the
entire `didCopy` / `copyResetTask` block below stays exactly as it is:

```swift
    private func performCopy() {
        Clipboard.copy(snippet.code)
        // Bookkeeping goes through SnippetStore, not inline: `copyCount` feeds
        // the panel's "Frequent" scope and the sidebar's "Frequently used"
        // section, and a second definition of "a copy happened" is how those
        // drift apart from each other.
        SnippetStore.recordCopy(snippet, in: modelContext)
        withAnimation(DSToken.Motion.toggle) {
            didCopy = true
        }
        copyResetTask?.cancel()
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if !Task.isCancelled {
                withAnimation(DSToken.Motion.toggle) {
                    didCopy = false
                }
            }
        }
    }
```

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
grep -n "copyCount += 1\|SnippetStore.recordCopy\|Clipboard.copy" Sources/Snippets/Views/Components/SnippetCard.swift
```
→ exactly 2 matches: `Clipboard.copy` and `SnippetStore.recordCopy`, in that
order, with **no** `copyCount += 1`.

### Step 3: Route the detail view's copy chip through `recordCopy`

In `Sources/Snippets/Views/SnippetDetailView.swift`, replace the inline
increment at `:206` inside the copy `FilterTag`'s action closure. Use the
`modelContext` already declared at `:10`; do not add a second declaration. The
`didCopy = true` line and the 1.5s `asyncAfter` reset stay untouched:

```swift
            ) {
                Clipboard.copy(snippet.code)
                // Bookkeeping goes through SnippetStore, not inline — see
                // `recordCopy`: it is the single definition of what a copy
                // records, and `updatedAt` is deliberately left alone so
                // copying never reshuffles the gallery.
                SnippetStore.recordCopy(snippet, in: modelContext)
                didCopy = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    didCopy = false
                }
            }
```

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
grep -rn "copyCount += 1" Sources
```
→ **exactly 1 line**: `Sources/Snippets/Intents/SnippetStore.swift:36`.

```sh
grep -rn "SnippetStore.recordCopy(" Sources | wc -l
```
→ `4`

```sh
grep -rn "Clipboard.copy" Sources | wc -l
```
→ `4` (unchanged from step 0 — the four copy paths still all write the
pasteboard through `Clipboard`).

### Step 4: Full test run and runtime regression check

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```
→ exit 0, `** TEST SUCCEEDED **`, **389 tests, 0 failures**. The count must stay
389: this plan adds no tests (see "Test plan").

Then confirm the user-visible behaviour is genuinely unchanged. Launch the app,
confirm you are on the new binary:
```sh
ps -o lstart,comm -p "$(pgrep -n Snippets)"
```
→ start time later than the built binary's mtime.

1. **Gallery card copy.** Click a card's `copy` chip. The chip flips to
   `copied` with a checkmark and returns to `copy` after ~1.4s. Then:
   ```sh
   pbpaste
   ```
   → the snippet's code, byte-for-byte.
2. **Detail view copy.** Open that snippet, click the `copy` chip in the action
   bar. It flips to `copied` and returns after ~1.5s. `pbpaste` again → the
   snippet's code.
3. **No capture prompt fired.** If "Offer to Save Copied Code" is enabled
   (**Settings ⌘, → Preferences**), neither copy above may raise the quick-copy
   panel offering to save the snippet — that would mean `Clipboard.copy` was
   moved or bypassed and `lastLocalChangeCount` is no longer suppressing the
   app's own write. This is the regression check for the one thing that was
   already correct.

**Verify**: all three observed.

## Test plan

**No new unit tests.** Deliberately, and you should not add any:

- The behaviour this plan funnels is already covered.
  `Tests/SnippetsTests/SnippetIntentLogicTests.swift:165-207` holds three tests
  against `recordCopy` itself — `test_recordCopy_bumpsCountAndLeavesUpdatedAtAlone`
  (count bumps, `updatedAt` pinned), `test_recordCopy_worksOnSnippetWithNilUUID`
  (works on a snippet the panel holds directly, whose uuid may still be nil —
  which is exactly the shape both new call sites pass), and
  `test_copyIntent_stillBumpsCountThroughRecordCopy`. After this plan those
  tests cover all four copy paths' bookkeeping instead of two.
- The two changed call sites are **not unit-testable in this repo**.
  `SnippetCard` and `SnippetDetailView` are SwiftUI views, and the
  `SnippetsTests` target has no SwiftUI view harness — it tests pure types and
  view models only. That is precisely why `QuickCopyResults`,
  `QuickCopySelection` and `ClipboardCapture` were extracted as pure types.
  A test for "the card's private `performCopy` calls `recordCopy`" cannot be
  written without either making the method non-private and static (changing
  production shape to suit a test) or introducing a view-testing dependency —
  both are out of scope and out of proportion for a two-line change.
- Writing a test that inserts a `Snippet`, calls `recordCopy` twice and asserts
  `copyCount == 2` would test the function this plan does not modify. Don't.

The verification for this plan is therefore the grep invariant in step 3 plus
the unchanged 389, backed by the step 4 runtime check that the two chips still
behave identically.

Existing tests that must all still pass, in particular:
`Tests/SnippetsTests/SnippetIntentLogicTests.swift` and
`Tests/SnippetsTests/QuickCopyViewModelTests.swift` (whose
`test_copySelected_bumpsCopyCountOfTheSelectedSnippet` covers the panel path).

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `grep -rn "copyCount += 1" Sources` returns **exactly one** match, and it
      is `Sources/Snippets/Intents/SnippetStore.swift:36`
- [ ] `grep -rn "SnippetStore.recordCopy(" Sources | wc -l` returns `4`
- [ ] `grep -rn "Clipboard.copy" Sources | wc -l` returns `4` (unchanged)
- [ ] `grep -c "modelContext" Sources/Snippets/Views/Components/SnippetCard.swift`
      returns `2` (the declaration and the one use)
- [ ] `grep -c "modelContext" Sources/Snippets/Views/SnippetDetailView.swift`
      returns `2` (the pre-existing declaration at `:10` and the one use — **not** 3;
      a 3 means you added a duplicate declaration)
- [ ] `git diff 08bb49c3..HEAD -- Sources/Snippets/Intents/SnippetStore.swift`
      is empty (`recordCopy` untouched)
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` exits 0 with `** BUILD SUCCEEDED **`
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` exits 0 with `** TEST SUCCEEDED **` and **389 tests, 0 failures**
- [ ] Step 4's three runtime behaviours observed
- [ ] `git status --porcelain` shows only
      `Sources/Snippets/Views/Components/SnippetCard.swift`,
      `Sources/Snippets/Views/SnippetDetailView.swift` and `plans/README.md`
      as modified by you (the tree may already carry unrelated uncommitted
      changes to `GallerySection.swift` / `SnippetGalleryView.swift` from before
      you started — leave them alone and say so in your report)
- [ ] `plans/README.md`'s round-2 status row for 014 is updated. The row already
      exists — change only its Status cell, and touch no other row.

## STOP conditions

Stop and report back (do not improvise) if:

- Step 0's grep returns anything other than 3 matches, or the code at
  `SnippetCard.swift:8-11` / `:58-73` or `SnippetDetailView.swift:10` / `:196-212`
  does not match the "Current state" excerpts — the codebase has drifted.
- `SnippetDetailView.swift:10` does **not** already declare
  `@Environment(\.modelContext) private var modelContext`. The plan assumes it
  does; if it was removed, report rather than guessing where to put it back.
- The compiler asks for `await`, `Task { }`, `@MainActor`, or any other
  concurrency annotation at either new call site. Both sites are already
  main-actor isolated and already call the `@MainActor` `Clipboard.copy`; a
  demand for isolation means an assumption in "Current state" is wrong. Do not
  wrap the call in a `Task` to silence it.
- The test count comes back as anything other than 389, in either direction.
- A copy now raises the quick-copy "Save as snippet" capture panel for code
  copied *out of* Snippets. That means `Clipboard.copy` was moved or bypassed
  and `lastLocalChangeCount` no longer suppresses the app's own write — revert
  and re-read "What must not break".
- You conclude the fix needs a change to `SnippetStore.swift`,
  `Clipboard.swift`, or the `didCopy` timing. All three are out of scope.
- You find a **fifth** copy path that neither this plan nor step 0's grep
  accounts for (something that writes the pasteboard without
  `Clipboard.copy`, or increments `copyCount` by another expression). Report it;
  do not silently fold it in.

## Maintenance notes

For whoever owns this code next:

- **The invariant is now enforced by grep, not by prose.** `grep -rn "copyCount += 1" Sources`
  returning exactly one line is the whole contract. If CI ever grows a lint
  step (plan 007 owns the workflow), that grep is a one-line guard worth adding
  there so the fifth copy path cannot reintroduce the drift.
- **Any new copy affordance must call `SnippetStore.recordCopy`**, and a view
  needs `@Environment(\.modelContext)` to do it. The quick-copy panel is hosted
  in an `NSHostingView` rather than the main window tree, so a future panel-side
  copy affordance must confirm the container reaches it, or pass the context
  explicitly the way `QuickCopyViewModel` does.
- **Reviewers should scrutinise**: that `Clipboard.copy(snippet.code)` is still
  the first statement at both call sites; that `recordCopy` itself is unchanged
  in the diff; and that no second `@Environment(\.modelContext)` was added to
  `SnippetDetailView`.
- **Deferred out of this plan, deliberately**:
  - The `didCopy` reset is 1.4s in the card (`Task` + `Task.sleep`, cancellable)
    and 1.5s in the detail view (`DispatchQueue.main.asyncAfter`, not
    cancellable). Two timings and two mechanisms for the same affordance. The
    `asyncAfter` one also outlives the view — the same class of bug commit
    `97b958f5` fixed for the quick-copy panel — though here it only writes a
    `@State` bool on a torn-down view, which is harmless. Worth one small
    follow-up that unifies both on a cancellable `.task(id:)` with a shared
    `DSToken` duration.
  - Whether `copyCount` should record *when* as well as *how many* — a
    `lastCopiedAt`, or a decayed score — so "Frequent" reflects recent use
    rather than lifetime totals. That change now has exactly one place to land,
    which is the point of this plan.

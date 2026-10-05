# Plan 016: Drop a snippet's preview grants when the snippet is permanently deleted

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index. (The table there currently stops at 010; add a row.)
>
> **Drift check (run first)**:
> `git diff --stat 08bb49c3..HEAD -- Sources/Snippets/Features/Preview/PreviewTrust.swift Sources/Snippets/Views/TrashView.swift Sources/Snippets/Views/ContentView.swift`
> If any of those files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `08bb49c3`, 2026-07-31

## Why this matters

`PreviewTrust.forget(_:)` is the function that stops a deleted snippet's preview
approvals from outliving it. It is written, documented, and unit-tested — and
**nothing calls it**. Verified at `08bb49c3`:

```sh
$ grep -rn "\.forget(" Sources --include='*.swift'
$            # (no output — only the definition itself exists, without a leading dot)
```

The grant it is supposed to drop is the CDN-modules grant: the one capability in
this app that lets previewed snippet code reach the network at all (npm imports
from esm.sh). It is persisted to `UserDefaults`, so today the grant list is
**append-only for the lifetime of the install**. Deleting the snippet removes the
snippet; the approval stays behind, keyed to a uuid that no longer refers to
anything.

**Be honest about the severity: this is hygiene, not a live vulnerability.**
Turning a stale grant into an actual capability requires a *new* snippet to
appear holding the *same* uuid, and there is no path today that does that by
accident — `Snippet.uuid` defaults to a fresh `UUID()`
(`Sources/Snippets/Models/Snippet.swift:46-47`), and the app has no import, sync
or sharing feature. Nobody is going to be attacked through this next week.

Two real reasons to fix it anyway:

1. **It becomes load-bearing the moment snippets arrive from elsewhere.** The
   whole trust layer exists for that future — see `plans/005-design-output.md`,
   which gates any import/sharing feature. An importer that preserves uuids (the
   obvious design, since `SnippetLinker` dependencies are uuid-keyed) would make
   "an imported snippet silently inherits network egress" a real sentence. The
   time to close it is while it costs an afternoon.
2. **A permission list that only ever grows is one nobody can audit.** There is
   no UI for reviewing grants. If the set is also never pruned, then even in
   principle no one — user or developer — can answer "what is currently allowed
   to hit the network?" without reading raw `UserDefaults`.

The project's own security write-up already records this as an open item, in
`Docs/security-overview.md` section 4 ("Residual risk"), item 6 — quoted here in
full because `Docs/` is gitignored and may not exist in your checkout:

> **Run approval is per launch, CDN grants are permanent.** Deliberate. If
> grants should expire or be reviewable, there is no UI for auditing them yet —
> `PreviewTrust.forget` exists but nothing calls it on snippet deletion.

This plan closes the second half of that sentence. Grant auditing UI is *not* in
scope.

## Design decisions (already made — do not re-litigate)

### Decision 1: closure injection, not a `PreviewTrust` singleton

Two of the three hard-delete paths live in `TrashLifecycle`, a non-view
`@MainActor enum` with no SwiftUI environment access. It has to reach a
`PreviewTrust` somehow. Two options were weighed:

**(a) Pass the callback in** — add an optional `forgetTrust` parameter to
`TrashLifecycle.purgeSnippet` and `cleanup`, supplied by the views that already
can (or easily can) read `PreviewTrust` from the environment. **This is what
this plan does.**

**(b) Make `PreviewTrust` a singleton** (`static let shared` + `private init()`,
matching `AppIntentNavigator.shared`, `ClipboardMonitor.shared`,
`CaptureDraft.shared`, `MenuBarController.shared`) so `TrashLifecycle` could call
`PreviewTrust.shared.forget(...)` directly. **Rejected**, for three reasons:

1. **It contradicts the type's own doc comment.** `TrashLifecycle` says
   "Context-injected so the logic is testable outside the view"
   (`ContentView.swift:1664-1665`). Every dependency it has is already a
   parameter. Reaching for a global inside it would be the first exception, in
   the one function where the thing being reached for is a security decision.
2. **It would break test isolation on the object that gates code execution and
   network egress.** `Tests/SnippetsTests/PreviewTrustTests.swift` constructs
   `PreviewTrust()` directly in **12 places** (`:27, :33, :44, :53, :57, :63,
   :71, :77, :91, :92, :96, :106, :118`), and two of them —
   `test_runApproval_doesNotSurviveRelaunch` (`:51`) and
   `test_cdnGrant_survivesRelaunch` (`:89`) — model *relaunch* precisely by
   building a second instance. The repo's singleton idiom pairs `static let
   shared` with `private init()`, which would make all 12 uncompilable; keeping
   `init` public to dodge that gives a singleton that is not one, i.e. the worst
   of both.
3. **Ownership is currently explicit and correct.** `PreviewTrust` is
   `@State private var previewTrust = PreviewTrust()` at `SnippetsApp.swift:117`,
   injected at `:128`, `:149` and `:179`. Converting it to global mutable state
   is a real ownership change to a security-relevant object, in service of saving
   one function parameter.

(a) costs one optional parameter on two static functions and one
`@Environment` line in two views. That is the cheaper trade.

### Decision 2: hard delete forgets, soft delete does not

`performDeleteSnippet` (`ContentView.swift:1173-1186`) is the ordinary delete:
it sets `deletedAt`, shows an undo toast, and the snippet sits in Trash for 30
days. **That path must not forget grants.** Three reasons:

- **Forgetting is not undoable.** `undoLastDeletion` (`ContentView.swift:1191`)
  and `TrashView.restore` (`TrashView.swift:89-93`) both restore a snippet by
  clearing `deletedAt` — same object, same uuid. `PreviewTrust` has no way to put
  a revoked grant back, so delete-then-undo would silently and permanently strip
  a standing decision the user made. The next preview of that snippet would drop
  its npm imports with no explanation.
- **There is nothing to protect against meanwhile.** A trashed snippet cannot be
  previewed: `TrashView` passes `onSelect: { _ in }` (`TrashView.swift:72`), so
  no detail view — and therefore no preview engine — is ever reachable for it.
  A grant held during the soft-delete window is unusable by construction.
- **Hard delete is the point of no return.** Once the model is gone the uuid
  refers to nothing, the grant can never be consulted through the UI again, and
  it is pure unauditable residue. That is the moment to drop it.

## Current state

### The files

- `Sources/Snippets/Features/Preview/PreviewTrust.swift` — the consent object.
  `forget(_:)` lives at `:99-105`. **This file is not modified by this plan.**
- `Sources/Snippets/Views/ContentView.swift` — holds `TrashLifecycle` (the
  `@MainActor enum` at `:1664-1700`) and two of the three hard-delete entry
  points.
- `Sources/Snippets/Views/TrashView.swift` — the Trash UI; holds the third
  hard-delete entry point, `permanentlyDelete` at `:95-102`.
- `Tests/SnippetsTests/TrashLifecycleTests.swift` — the structural exemplar and
  the file new tests go into.

### What `forget` drops (`PreviewTrust.swift:96-105`)

```swift
    /// Drops a deleted snippet's grant so a later snippet reusing the id (or a
    /// restored one) does not inherit approval nobody gave it.
    func forget(_ snippetID: UUID?) {
        guard let snippetID else { return }
        cdnGrants.remove(snippetID)
        sessionApproved.remove(snippetID)
    }
```

Both sets are keyed by `Snippet.uuid`, which is `UUID?`
(`Sources/Snippets/Models/Snippet.swift:16`):

- `cdnGrants` (`PreviewTrust.swift:45-52`) — persisted, via a `didSet` that
  writes `"settings.preview.cdnGrants"` to `UserDefaults.standard`. **This is the
  one that matters.** It is the grant that lets a snippet's web preview import
  npm modules from esm.sh, i.e. the only way preview code reaches the network.
  Persisted means a stale entry survives forever.
- `sessionApproved` (`PreviewTrust.swift:54-57`) — in-memory only, cleared on
  relaunch. Lower stakes, forgotten by the same call for free.

### Ownership: `PreviewTrust` is NOT a singleton

`Sources/Snippets/SnippetsApp.swift:115-117`:

```swift
    @State private var environment = AppEnvironment()
    @State private var appearanceSettings = AppearanceSettings()
    @State private var previewTrust = PreviewTrust()
```

Injected into the view tree at `SnippetsApp.swift:128` and `:149` (the two
`WindowGroup` availability branches, both wrapping `ContentView()`) and at `:179`
(the `Settings` scene). Read today by exactly two views:
`Sources/Snippets/Views/Settings/AppearanceView.swift:7` and
`Sources/Snippets/Views/Components/Preview/SnippetPreviewView.swift:21`, both via
`@Environment(PreviewTrust.self)`.

Both files this plan touches are inside that injected tree, so
`@Environment(PreviewTrust.self)` resolves in both — `TrashView()` is
instantiated by `ContentView` itself at `ContentView.swift:504`. Neither file
contains a `#Preview` macro (verified), so there is no preview harness that would
crash for want of the environment object.

### The three hard-delete paths, exhaustively

Verified by `grep -rn "context\.delete(\|Context\.delete(" Sources
--include='*.swift'`. Only these three can hard-delete a `Snippet`:

**Path 1 — `TrashView.permanentlyDelete` (`TrashView.swift:95-102`)**, the
per-snippet "Delete Permanently" in the Trash UI:

```swift
    private func permanentlyDelete(_ snippet: Snippet) {
        for mediaItem in snippet.mediaItems {
            appEnvironment.mediaManager.deleteFile(for: mediaItem)
        }

        modelContext.delete(snippet)
        try? modelContext.save()
    }
```

`TrashView` is declared at `TrashView.swift:4` and its environment properties at
`:5-7` are `modelContext`, `colorScheme`, `appEnvironment` — it does **not** read
`PreviewTrust` today.

**Paths 2 and 3 — `TrashLifecycle` (`ContentView.swift:1664-1700`)**, verbatim as
it exists today:

```swift
/// Hard-delete operations shared by the Trash cleanup and permanent collection
/// delete flows. Context-injected so the logic is testable outside the view.
@MainActor
enum TrashLifecycle {
    /// Hard-deletes a snippet: removes media files from disk, then deletes the model.
    static func purgeSnippet(_ snippet: Snippet, context: ModelContext) {
        for media in snippet.mediaItems {
            MediaManager.deleteFile(for: media)
        }
        context.delete(snippet)
    }

    /// Hard-deletes soft-deleted snippets and collections whose `deletedAt` is
    /// before `cutoff`. Live snippets belonging to an expired collection are
    /// kept; only their membership in the purged collection is removed.
    static func cleanup(
        snippets: [Snippet],
        collections: [SnippetCollection],
        cutoff: Date,
        context: ModelContext
    ) throws {
        for snippet in snippets {
            if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
                purgeSnippet(snippet, context: context)
            }
        }
        for collection in collections {
            if let deletedAt = collection.deletedAt, deletedAt < cutoff {
                for member in collection.snippets {
                    member.collections.removeAll { $0.persistentModelID == collection.persistentModelID }
                }
                context.delete(collection)
            }
        }
        try context.save()
    }
}
```

Its call sites inside `ContentView` — there are exactly two, both of which this
plan updates:

- `ContentView.swift:1264` — inside `performTrashCleanup()` (defined at `:1261`,
  invoked from the `.task` at `:754`, i.e. once per view appearance). This is the
  30-day Trash expiry sweep:

```swift
    private func performTrashCleanup() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.distantPast
        do {
            try TrashLifecycle.cleanup(
                snippets: trashedSnippets,
                collections: collections.filter { $0.deletedAt != nil },
                cutoff: cutoff,
                context: modelContext
            )
        } catch {
            showToast("Couldn't save changes: \(error.localizedDescription)")
        }
    }
```

- `ContentView.swift:1417` — inside `deleteCollectionContentsRecursively`, the
  permanent branch. Reached from `:865` (the collection-delete confirmation
  dialog) and `:1403` (the "collectionAndContents" behavior setting), both with
  `permanent: true`; the third caller at `:1152` passes `permanent: false` and
  goes down the soft-delete branch:

```swift
    private func deleteCollectionContentsRecursively(_ collection: SnippetCollection, permanent: Bool) {
        for snippet in collection.snippets {
            if permanent {
                if selectedSnippetID == snippet.persistentModelID {
                    selectedSnippetID = nil
                }
                TrashLifecycle.purgeSnippet(snippet, context: modelContext)
            } else {
                self.performDeleteSnippet(snippet)
            }
        }
        for child in collection.children {
            deleteCollectionContentsRecursively(child, permanent: permanent)
            self.performDelete(child, permanent: permanent)
        }
    }
```

`ContentView`'s environment properties are at `ContentView.swift:8-12`
(`modelContext`, `colorScheme`, `reduceMotion`, `appearanceSettings`,
`navigator`) — it does **not** read `PreviewTrust` today either.

### Paths that hard-delete a *collection* are not in scope

`TrashView.permanentlyDeleteCollection` (`:110-113`) and
`ContentView.performDelete(_:permanent: true)` (`:1428-1440`) delete a
`SnippetCollection`. `Snippet.collections` is declared
`@Relationship(inverse: \SnippetCollection.snippets)` with **no** delete rule
(`Sources/Snippets/Models/Snippet.swift:26-27`), so the default `.nullify`
applies and no snippet is cascade-deleted by them. `PreviewTrust` is keyed by
`Snippet.uuid` only and knows nothing about collections. Leave both alone.

### Repo conventions to match

- **Swift 6 language mode.** `SWIFT_VERSION = 6.0` in every build config, so
  strict concurrency is on. `PreviewTrust` and `TrashLifecycle` are both
  `@MainActor`. This is why the new parameter's type carries an explicit
  `@MainActor` in step 1 — see the note there.
- **Comments name the failure mode they prevent**, not what the line does. Every
  excerpt above is an example; `PreviewTrust.swift:54-57` and `:99-100` are the
  closest models for this plan's subject matter.
- **`TrashLifecycle` takes its dependencies as parameters.** Its doc comment says
  why. Keep it that way.
- **`Tests/SnippetsTests/TrashLifecycleTests.swift` is the structural exemplar**
  for the new tests: `@MainActor final class ... : XCTestCase`, a private
  `makeInMemoryContainer()` returning the container (with the comment explaining
  that the context alone does not keep it alive), a `daysAgo(_:)` helper, and a
  `cutoff` of `daysAgo(30)`.
- **Every source file must be registered in `Snippets.xcodeproj/project.pbxproj`**
  — the project enumerates files explicitly and a file that only exists on disk
  is silently not compiled. This plan **adds no new files**, deliberately, to
  stay clear of that trap entirely.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | exit 0, `** BUILD SUCCEEDED **` |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | exit 0, `** TEST SUCCEEDED **` |

The suite is **389 tests, 0 failures** before this plan. This plan adds **3**
tests, so after step 4 the expected count is **389 + 3 = 392, 0 failures**.

There is **no** `Package.swift` in this repo. `swift build` and `swift test` do
not work here — `Snippets.xcodeproj` is the only build system. (The header of
`plans/README.md` still shows `swift build --build-path …` from plan 001; that is
stale. Use the table above.) SwiftData macros need the full Xcode-beta
toolchain — the Command Line Tools alone will not build this project, which is
what the `DEVELOPER_DIR` prefix is for.

## Suggested executor toolkit

- The repo ships a `verify` skill at `.claude/skills/verify` for building,
  launching and driving the app at runtime. Step 5 is a runtime check; invoke it
  if available.
- `graphify query "<question>"` is available (`graphify-out/graph.json` exists)
  and is the cheapest way to orient before opening `ContentView.swift`, which is
  ~1700 lines.
- `open` on an already-running build reuses the live process, so you can
  screenshot or read defaults from a stale binary. Check `ps -o lstart` against
  the built binary's mtime before trusting a runtime observation.

## Scope

**In scope** (the only files you should modify):
- `Sources/Snippets/Views/ContentView.swift`
- `Sources/Snippets/Views/TrashView.swift`
- `Tests/SnippetsTests/TrashLifecycleTests.swift`
- `plans/README.md` (status row only)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Snippets/Features/Preview/PreviewTrust.swift` — `forget` is already
  correct and already tested. It needs callers, not edits. In particular do
  **not** make it a singleton (see Design decision 1).
- `Sources/Snippets/SnippetsApp.swift` — ownership and injection are already
  right; both files you touch are inside the injected tree.
- `ContentView.performDeleteSnippet` (`:1173`) and every other soft-delete path,
  including `delete`, `deleteSelection`, `performBulkDelete` and
  `undoLastDeletion`. Soft delete must keep grants (see Design decision 2).
- Collection deletion (`TrashView.permanentlyDeleteCollection`,
  `ContentView.performDelete(_:permanent:)`) — `PreviewTrust` is snippet-keyed.
- **Do not refactor `TrashView.permanentlyDelete` to call
  `TrashLifecycle.purgeSnippet`.** It looks like duplication, but the two use
  different media deleters — `appEnvironment.mediaManager.deleteFile` (instance,
  `MediaManager.swift:127`) versus `MediaManager.deleteFile` (static, `:123`) —
  and unifying them changes which manager instance touches disk. Separate
  concern, separate change.
- Any grant-auditing or grant-expiry UI. Explicitly deferred; see Maintenance
  notes.
- `Sources/Snippets/Views/Components/GallerySection.swift` and
  `Sources/Snippets/Views/SnippetGalleryView.swift` — these had **uncommitted
  changes in the working tree when this plan was written**. They are unrelated.
  Do not revert, commit, or stash them, and expect them in `git status`.

## Git workflow

- Branch: `advisor/016-forget-preview-grants-on-delete`
- Commit per logical unit. Message style, matching `git log`: short sentence-case
  imperative subject, blank line, body explaining the failure mode. Examples from
  this repo: `Tie panel timers to view lifetime, and retire only the banner`,
  `Fix three defects found in runtime verification`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 0: Confirm the gap before changing anything

```sh
grep -rn "\.forget(" Sources --include='*.swift'
```

**Expected**: no output. `forget` has zero call sites; the definition at
`PreviewTrust.swift:101` does not match because it has no leading dot.

```sh
grep -rn "func forget" Sources --include='*.swift'
```

**Expected**: exactly one match,
`Sources/Snippets/Features/Preview/PreviewTrust.swift:101`.

**Verify**: both hold. If the first command already prints call sites, STOP and
report — the premise of this plan is wrong, someone has already wired it.

### Step 1: Give `TrashLifecycle` an optional forget callback

In `Sources/Snippets/Views/ContentView.swift`, modify the `TrashLifecycle` enum
at `:1664-1700`. Add one parameter to each of the two static functions, defaulted
to `nil` so no existing call site breaks:

```swift
    /// Hard-deletes a snippet: removes media files from disk, drops any preview
    /// consent recorded for it, then deletes the model.
    ///
    /// `forgetTrust` is `PreviewTrust.forget` at the call sites that have one.
    /// It is a parameter rather than a global because this type is
    /// context-injected precisely so it stays testable outside a view, and the
    /// object being reached for is the one that gates code execution and
    /// network egress — the last one that should become ambient state.
    ///
    /// It fires *before* the delete, deliberately: reading `snippet.uuid` off a
    /// model the context has already deleted is reading an invalidated object.
    static func purgeSnippet(
        _ snippet: Snippet,
        context: ModelContext,
        forgetTrust: (@MainActor (UUID?) -> Void)? = nil
    ) {
        forgetTrust?(snippet.uuid)
        for media in snippet.mediaItems {
            MediaManager.deleteFile(for: media)
        }
        context.delete(snippet)
    }
```

and thread it through `cleanup`:

```swift
    static func cleanup(
        snippets: [Snippet],
        collections: [SnippetCollection],
        cutoff: Date,
        context: ModelContext,
        forgetTrust: (@MainActor (UUID?) -> Void)? = nil
    ) throws {
        for snippet in snippets {
            if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
                purgeSnippet(snippet, context: context, forgetTrust: forgetTrust)
            }
        }
        // ... collection loop and `try context.save()` unchanged ...
    }
```

Change nothing else in the enum. The collection loop and the trailing
`try context.save()` stay exactly as they are.

Three details that are load-bearing:

- **`@MainActor` on the function type is required, not decorative.** This target
  builds in Swift 6 language mode (`SWIFT_VERSION = 6.0`), and
  `PreviewTrust.forget` is `@MainActor`-isolated. A plain `(UUID?) -> Void`
  parameter would not accept it. `TrashLifecycle` is itself `@MainActor`, so it
  can call the closure synchronously.
- **The callback fires before `context.delete`.** After the delete the model is
  invalidated and `snippet.uuid` is no longer a safe read.
- **Forgetting slightly too eagerly is the safe direction.** If `cleanup`'s
  trailing `try context.save()` throws, a grant may have been dropped for a
  snippet that survived. The cost is that the user re-grants CDN access once; the
  opposite error leaves live network permission attached to nothing. Do not add
  rollback logic for this.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`. Nothing else has changed yet, because both
parameters default to `nil`.

### Step 2: Pass the callback from `ContentView`'s two call sites

Still in `Sources/Snippets/Views/ContentView.swift`.

First, give the view access to the trust object. Add to the environment block at
`:8-12`, after the existing `@Environment` lines:

```swift
    @Environment(PreviewTrust.self) private var previewTrust
```

Then update `performTrashCleanup()` (`:1261-1273`):

```swift
            try TrashLifecycle.cleanup(
                snippets: trashedSnippets,
                collections: collections.filter { $0.deletedAt != nil },
                cutoff: cutoff,
                context: modelContext,
                forgetTrust: { previewTrust.forget($0) }
            )
```

and the permanent branch of `deleteCollectionContentsRecursively` (`:1417`):

```swift
                TrashLifecycle.purgeSnippet(
                    snippet,
                    context: modelContext,
                    forgetTrust: { previewTrust.forget($0) }
                )
```

Write the closure literally as `{ previewTrust.forget($0) }`. Do **not** pass the
bare method reference `previewTrust.forget` — under Swift 6 that is an
unapplied `@MainActor` method value whose conversion is fussier, and the explicit
form reads better at the call site.

Leave the `else` branch (`self.performDeleteSnippet(snippet)`) untouched: that is
soft delete, which must keep grants.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
grep -c "forgetTrust:" Sources/Snippets/Views/ContentView.swift
```
→ `5` — two parameter declarations, the forward from `cleanup` to
`purgeSnippet`, and the two argument labels at the call sites. (Matching on the
trailing colon deliberately excludes `forgetTrust?(snippet.uuid)` and any prose
in the doc comment, so the count does not depend on how you worded those.)

### Step 3: Forget on the Trash view's permanent delete

In `Sources/Snippets/Views/TrashView.swift`, add to the environment block at
`:5-7`:

```swift
    @Environment(PreviewTrust.self) private var previewTrust
```

and change `permanentlyDelete` (`:95-102`) to:

```swift
    private func permanentlyDelete(_ snippet: Snippet) {
        // Read and drop the preview consent before the model goes: after the
        // delete `snippet.uuid` is a read off an invalidated object, and a
        // grant left behind is network permission attached to nothing — the
        // CDN grant is persisted, so it would outlive the snippet forever.
        previewTrust.forget(snippet.uuid)

        for mediaItem in snippet.mediaItems {
            appEnvironment.mediaManager.deleteFile(for: mediaItem)
        }

        modelContext.delete(snippet)
        try? modelContext.save()
    }
```

Do not touch `restore` (`:89-93`), `restoreCollection` (`:104-108`) or
`permanentlyDeleteCollection` (`:110-113`).

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build
```
→ exit 0, `** BUILD SUCCEEDED **`

```sh
grep -rn "\.forget(" Sources --include='*.swift'
```
→ exactly 3 matches: `TrashView.swift` once, `ContentView.swift` twice. Compare
with step 0, which returned nothing.

### Step 4: Add three tests to `TrashLifecycleTests`

Add to the **existing** `Tests/SnippetsTests/TrashLifecycleTests.swift`. Do not
create a new test file: a new file would also have to be registered in
`Snippets.xcodeproj/project.pbxproj` under the `SnippetsTests` target, and a file
that only exists on disk is silently not compiled. Adding cases to a registered
file avoids that class of problem entirely.

First add a `tearDown` next to the existing helpers, because test 3 writes a real
`UserDefaults` key through `PreviewTrust.cdnGrants`'s `didSet` and must not leak
into `PreviewTrustTests` (which clears the same key in its own `setUp`/`tearDown`
— see `PreviewTrustTests.swift:8-20` for the pattern being matched):

```swift
    // `PreviewTrust` persists CDN grants to real user defaults, so a test that
    // grants one must clear it or it leaks into the next suite.
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "settings.preview.cdnGrants")
        super.tearDown()
    }
```

Then the three cases:

```swift
    // MARK: Preview consent

    /// The expiry sweep must drop preview consent for exactly the snippets it
    /// purged — and for no one else, or a survivor silently loses a grant.
    func test_cleanup_forgetsTrustForPurgedSnippetOnly() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = Snippet(title: "Old", code: "a", deletedAt: daysAgo(31))
        let recent = Snippet(title: "New", code: "b", deletedAt: daysAgo(29))
        context.insert(expired)
        context.insert(recent)
        try context.save()
        // Captured before the purge: reading `uuid` off a deleted model is a
        // read of an invalidated object.
        let expiredID = expired.uuid
        XCTAssertNotNil(expiredID)

        var forgotten: [UUID?] = []
        try TrashLifecycle.cleanup(
            snippets: [expired, recent],
            collections: [],
            cutoff: cutoff,
            context: context,
            forgetTrust: { forgotten.append($0) }
        )

        XCTAssertEqual(forgotten.count, 1)
        XCTAssertEqual(forgotten.first ?? nil, expiredID)
    }

    /// The permanent-collection-delete path goes through `purgeSnippet`
    /// directly, so it needs its own coverage.
    func test_purgeSnippet_forgetsTrustForThatSnippet() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let snippet = Snippet(title: "Gone", code: "a")
        context.insert(snippet)
        try context.save()
        let id = snippet.uuid

        var forgotten: [UUID?] = []
        TrashLifecycle.purgeSnippet(snippet, context: context, forgetTrust: { forgotten.append($0) })
        try context.save()

        XCTAssertEqual(forgotten, [id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Snippet>()).isEmpty)
    }

    /// End to end with the real consent object: the point of the callback is
    /// that a purged snippet stops being allowed to reach the network.
    func test_cleanup_withPreviewTrust_dropsPersistedCDNGrant() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = Snippet(title: "Old", code: "a", deletedAt: daysAgo(31))
        context.insert(expired)
        try context.save()
        let id = expired.uuid

        let trust = PreviewTrust()
        trust.setCDNModulesAllowed(true, for: id)
        XCTAssertTrue(trust.allowsCDNModules(id))

        try TrashLifecycle.cleanup(
            snippets: [expired],
            collections: [],
            cutoff: cutoff,
            context: context,
            forgetTrust: { trust.forget($0) }
        )

        XCTAssertFalse(trust.allowsCDNModules(id))
        // And it is gone from the persisted set, not just this instance.
        XCTAssertFalse(PreviewTrust().allowsCDNModules(id))
    }
```

The five existing tests in this file all omit `forgetTrust`, which is exactly the
regression check that the defaulted parameter changed no behaviour. Do not modify
them.

**Verify**:
```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test
```
→ exit 0, `** TEST SUCCEEDED **`, **392 tests, 0 failures**.

If the count is 389, the new cases did not compile into the target — check that
you edited the existing `TrashLifecycleTests.swift` rather than creating a file.
If `PreviewTrustTests` starts failing, the `tearDown` above is missing or the key
string is wrong.

### Step 5: Confirm the grant actually disappears at runtime

The unit tests prove the wiring; this proves the persisted store shrinks.

Rebuild, launch, and confirm you are on the new binary:
```sh
ps -o lstart,comm -p "$(pgrep -n Snippets)"
```
→ start time later than the built binary's mtime.

1. Create a snippet whose web preview declares an npm import (any React/JSX
   snippet with `import … from "…"` will do), open it, and accept the CDN-modules
   banner above the preview. Enabling **Settings (⌘,) → Preferences → Run
   Previews Automatically** first saves a step.
2. Read the persisted grant list:
   ```sh
   defaults read com.halilbagosi.Snippets settings.preview.cdnGrants
   ```
   → an array containing one uuid string. Note it.
3. Delete that snippet (it goes to Trash), then in Trash choose **Delete
   Permanently**.
4. Read the list again:
   ```sh
   defaults read com.halilbagosi.Snippets settings.preview.cdnGrants
   ```
   → the uuid from step 2 is gone (an empty array, or the domain reports the key
   missing, are both fine).

If the value looks unchanged, quit the app and re-read — `cfprefsd` can serve a
cached value while the process holds the domain.

**Also check the soft-delete case does the opposite** (this is the regression
check for Design decision 2):

5. Repeat steps 1–2 with a second snippet, then delete it *without* emptying the
   Trash, and read the key again → **the uuid is still there.** Restore the
   snippet from Trash, open it, and confirm the preview still has its CDN grant
   (no banner re-prompt).

**Verify**: both observed. If step 5 shows the grant vanishing on soft delete,
something is calling `forget` from a soft-delete path — find it rather than
working around it.

## Test plan

- **File**: `Tests/SnippetsTests/TrashLifecycleTests.swift` (existing —
  registered in `project.pbxproj` under the `SnippetsTests` target already; no
  new file, deliberately).
- **Structural pattern**: the file itself. Reuse its `makeInMemoryContainer()`,
  `daysAgo(_:)` and `cutoff` helpers verbatim; add one `tearDown`.
- **New cases** (3):
  1. `test_cleanup_forgetsTrustForPurgedSnippetOnly` — a spy closure records what
     it is handed. Asserts it received exactly one uuid, that of the expired
     snippet, and not the recent survivor's. This is the specific bug: the
     expiry sweep purging a snippet while its grant stays behind.
  2. `test_purgeSnippet_forgetsTrustForThatSnippet` — the same for the direct
     `purgeSnippet` entry point, which is what the permanent-collection-delete
     flow uses; also re-asserts the model is gone so the callback is not
     replacing the delete.
  3. `test_cleanup_withPreviewTrust_dropsPersistedCDNGrant` — end to end against a
     real `PreviewTrust`: grant CDN modules, purge, assert
     `allowsCDNModules` is false both on that instance and on a freshly
     constructed one (which re-reads `UserDefaults`, i.e. proves the *persisted*
     entry went, not just the in-memory set). This is the test that actually
     demonstrates the security property.
- **Regression coverage for "no behaviour change when the callback is absent"**
  is already provided by the five existing cases in the file, all of which call
  `cleanup`/`purgeSnippet` without `forgetTrust`. Leave them untouched.
- **Not unit-tested, by design**: `TrashView.permanentlyDelete`. It is a private
  method on a SwiftUI `View` reading `@Environment`, and `Tests/SnippetsTests/`
  has no SwiftUI view harness — the suite covers pure types and view models
  only. Step 5's runtime check is its verification.
- **Verification**: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test`
  → exit 0, `** TEST SUCCEEDED **`, 392 tests (389 + 3), 0 failures.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` exits 0 with `** BUILD SUCCEEDED **`
- [ ] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` exits 0 with `** TEST SUCCEEDED **` and **392 tests, 0 failures**
- [ ] `grep -rn "\.forget(" Sources --include='*.swift'` returns **at least one** real call site (expected: exactly 3 — one in `TrashView.swift`, two in `ContentView.swift`), none of them the definition
- [ ] `grep -c "forgetTrust:" Sources/Snippets/Views/ContentView.swift` returns `5`
- [ ] `grep -c "@Environment(PreviewTrust.self)" Sources/Snippets/Views/TrashView.swift` returns `1`
- [ ] `grep -n "static let shared" Sources/Snippets/Features/Preview/PreviewTrust.swift` returns no match (`PreviewTrust` did **not** become a singleton)
- [ ] `git diff --stat 08bb49c3..HEAD -- Sources/Snippets/Features/Preview/PreviewTrust.swift` is empty (that file was not modified)
- [ ] `grep -n "forget" Sources/Snippets/Views/ContentView.swift` returns matches only inside `TrashLifecycle` (`:1664-1700`), `performTrashCleanup` and `deleteCollectionContentsRecursively` — and none inside `performDeleteSnippet`, `performBulkDelete`, `deleteSelection` or `undoLastDeletion` (soft delete keeps grants)
- [ ] Step 5's runtime checks observed: grant gone after permanent delete, grant retained after soft delete + restore
- [ ] `git status --porcelain` shows only `Sources/Snippets/Views/ContentView.swift`, `Sources/Snippets/Views/TrashView.swift`, `Tests/SnippetsTests/TrashLifecycleTests.swift` and `plans/README.md` as *your* modifications — `Sources/Snippets/Views/Components/GallerySection.swift` and `Sources/Snippets/Views/SnippetGalleryView.swift` were already dirty before you started and must stay that way
- [ ] `plans/README.md` has a status row for 016

## STOP conditions

Stop and report back (do not improvise) if:

- Step 0's `grep -rn "\.forget(" Sources --include='*.swift'` already returns call
  sites — this plan's premise is that there are none.
- The code at `PreviewTrust.swift:96-105`, `TrashView.swift:95-102`, or
  `ContentView.swift:1261-1273` / `:1411-1426` / `:1664-1700` does not match the
  excerpts in "Current state".
- You find a fourth path that hard-deletes a `Snippet` that is not one of the
  three enumerated here. Report it — the enumeration is the plan's completeness
  claim.
- The build fails on actor isolation for the `forgetTrust` parameter. Report the
  exact diagnostic. Do **not** work around it with `nonisolated(unsafe)`, a
  `@Sendable` annotation, or by wrapping the call in `Task { }` — deferring the
  forget past `context.delete` reintroduces the invalidated-model read this plan
  is careful to avoid.
- The test count after step 4 is anything other than 392.
- `PreviewTrustTests` starts failing after step 4 — that means shared
  `UserDefaults` state is leaking between suites; fix the `tearDown` rather than
  reordering or disabling tests.
- Step 5 shows a grant disappearing on **soft** delete. Find the caller; do not
  compensate by re-granting somewhere.
- The fix appears to require touching `PreviewTrust.swift` or
  `SnippetsApp.swift`. It does not — if it seems to, you are on the singleton
  path that Design decision 1 rejected.

## Maintenance notes

For whoever owns this code next:

- **Every future hard-delete path owes a `forget`.** There are three today and
  they are enumerated above. The invariant is: anything that calls
  `ModelContext.delete` on a `Snippet` must first hand that snippet's `uuid` to
  `PreviewTrust.forget`. If a fourth path appears (bulk "empty trash", an
  importer replacing a snippet, a sync engine reconciling deletions), it inherits
  that obligation. The cheapest guard is the done-criteria grep: `context.delete(`
  on a `Snippet` and `forget(` should stay in lockstep.
- **Reviewers should scrutinise** three things: that no *soft*-delete path
  acquired a `forget` call; that `forgetTrust` fires before `context.delete` in
  `purgeSnippet` (a later refactor that moves it after would compile and then
  read an invalidated model); and that `PreviewTrust` is still constructed in
  `SnippetsApp` rather than as a singleton.
- **This interacts directly with snippet import/sharing.** If an importer that
  preserves uuids ever ships (`plans/005-design-output.md` gates it), this fix
  goes from hygiene to load-bearing: an imported snippet reusing a uuid whose
  grant was never dropped would inherit network egress silently. Revisit the
  enumeration above when that lands, and consider whether import should
  *unconditionally* `forget` the incoming uuid before inserting.
- **Deferred out of this plan, deliberately**: any UI for reviewing or expiring
  CDN grants. `Docs/security-overview.md` section 4 item 6 wants both — pruning
  on delete (this plan) and auditability (not this plan). A settings pane listing
  granted snippets by title would also make orphaned grants visible, which is a
  better long-term answer than trusting every delete path to remember. Also
  deferred: unifying `TrashView.permanentlyDelete` with
  `TrashLifecycle.purgeSnippet`, which would collapse three paths to two and make
  the invariant above easier to hold — see the Scope note for why it was kept
  out.
- **If `Snippet.uuid` ever becomes non-optional** (the `UUIDBackfill` machinery in
  `SnippetsApp.backfillUUIDs` exists to migrate the last nil ones), the
  `UUID?` in `forgetTrust`'s signature and in `forget` itself can tighten to
  `UUID`, and the `guard let` at `PreviewTrust.swift:102` goes away.

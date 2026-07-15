# Plan 002: Make Trash deletion honest — purge expired collections, honor permanent delete, surface failed saves

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Views/ContentView.swift`
> If the file changed since this plan was written, compare the "Current state"
> excerpts against the live code before proceeding; on a mismatch, treat it as
> a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED (touches delete paths — wrong behavior destroys or resurrects user data)
- **Depends on**: none (001 recommended first for build docs)
- **Category**: bug
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

Three related integrity bugs live in the delete/trash code of `ContentView.swift`:

1. **Expired collections are never purged.** `performTrashCleanup()` hard-deletes snippets older than 30 days but has no branch for soft-deleted collections, so they accumulate forever while the UI promises "permanently deleted in N days".
2. **Permanent collection delete doesn't purge its snippets.** `deleteCollectionContentsRecursively(_:permanent:)` calls the soft-delete path for snippets regardless of `permanent`, so purging a collection from Trash leaves its snippets in Recently Deleted — and fires "Snippet moved to Recently Deleted" toasts mid-purge.
3. **Failed saves are swallowed.** Delete/restore/cleanup paths use `try? modelContext.save()`, so a failed save leaves the UI showing state the store never persisted (item reappears on relaunch). The editor already has the correct pattern (capture the error, surface a message).

## Current state

All in `Sources/Snippets/Views/ContentView.swift` (1453 lines; a SwiftUI `View` holding delete/undo/toast logic directly):

- `performDeleteSnippet(_:)` at `:1075` — soft delete: appends to `lastDeletion`, sets `deletedAt`/`updatedAt`, `try? modelContext.save()`, shows the "moved to Recently Deleted" toast. There is **no hard-delete counterpart for a single snippet**; the only hard delete of snippets is in `performTrashCleanup`.
- `performTrashCleanup()` at `:1161-1172`:
  ```swift
  private func performTrashCleanup() {
      let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date.now) ?? Date.distantPast
      for snippet in trashedSnippets {
          if let deletedAt = snippet.deletedAt, deletedAt < cutoff {
              for media in snippet.mediaItems {
                  MediaManager.deleteFile(for: media)
              }
              modelContext.delete(snippet)
          }
      }
      try? modelContext.save()
  }
  ```
- `deleteCollectionContentsRecursively(_:permanent:)` at `:1310`:
  ```swift
  private func deleteCollectionContentsRecursively(_ collection: SnippetCollection, permanent: Bool) {
      for snippet in collection.snippets {
          self.performDeleteSnippet(snippet)     // ← ignores `permanent`
      }
      for child in collection.children {
          deleteCollectionContentsRecursively(child, permanent: permanent)
          self.performDelete(child, permanent: permanent)   // ← honors it for collections
      }
  }
  ```
- `performDelete(_ collection:permanent:)` at `:1320-1349` — when `permanent`, strips the collection from all snippets' `collections` arrays and `modelContext.delete(collection)`; when not, sets `deletedAt` and appends to `lastDeletion`. Ends with `try? modelContext.save()`.
- Swallowed saves in this file at lines ~1085, 1114, 1154, 1171, 1345, 1364, 1409, 1416 (all `try? modelContext.save()`).
- The correct error-surfacing exemplar, `Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift:209-216`:
  ```swift
  do {
      try modelContext.save()
      try onSave(snippet)
      return true
  } catch {
      saveErrorMessage = error.localizedDescription
      return false
  }
  ```
- Toast helper `showToast(_:showsUndo:)` at `ContentView.swift:1155-1158` — the natural surface for save-failure messages.
- Models: `Snippet.deletedAt`, `SnippetCollection.deletedAt` (soft-delete markers); `Collection.swift:39` has `daysUntilPermanentDeletion`. `MediaManager.deleteFile(for:)` (`Sources/Snippets/Services/MediaManager.swift:96-104`) removes a media file from disk.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

## Scope

**In scope** (the only files you should modify/create):
- `Sources/Snippets/Views/ContentView.swift`
- `Tests/SnippetsTests/TrashLifecycleTests.swift` (create)
- `Snippets.xcodeproj/project.pbxproj` — ONLY if you create a new file under `Sources/` (test files under `Tests/` do not need registration; this plan should not need it)

**Out of scope** (do NOT touch, even though they look related):
- `Sources/Snippets/Models/*` — do not rename `isDeleted` or change `deletedAt` semantics (a separate recorded finding).
- Undo/restore logic (`lastDeletion` handling) beyond what step 2 requires.
- Extracting logic out of `ContentView` into a view model (deferred to a future god-file refactor plan).

## Git workflow

- Branch: `advisor/002-trash-delete-integrity`
- Commit per step; short sentence-case imperative subjects (repo style, e.g. `Wrap connected-snippet 'uses' chips instead of clipping`).
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Extract a testable trash-lifecycle helper

The three fixes need tests, and the logic currently lives inside a SwiftUI `View`. Create a small `@MainActor` type **inside `ContentView.swift`** (keeping this plan single-file for app sources; the future god-file refactor will move it):

```swift
@MainActor
enum TrashLifecycle {
    /// Hard-deletes a snippet: removes media files from disk, then deletes the model.
    static func purgeSnippet(_ snippet: Snippet, context: ModelContext) { ... }
    /// Hard-deletes soft-deleted snippets and collections whose deletedAt < cutoff.
    static func cleanup(snippets: [Snippet], collections: [SnippetCollection],
                        cutoff: Date, context: ModelContext) throws { ... }
}
```

`cleanup` must: purge expired snippets exactly as today's loop does (media files first), AND purge collections with `deletedAt < cutoff` — for an expired collection, remove it from any surviving snippets' `collections` arrays (mirror `performDelete`'s permanent branch) before `context.delete`. Do NOT delete a collection's live (non-trashed) snippets during cleanup — only the collection row itself. Throw instead of swallowing the save (`try context.save()`).

**Verify**: build command → exit 0.

### Step 2: Honor `permanent` for snippets in recursive collection delete

In `deleteCollectionContentsRecursively`, branch on `permanent`:
- `permanent == false`: keep calling `performDeleteSnippet(snippet)` (unchanged behavior, with toast).
- `permanent == true`: call `TrashLifecycle.purgeSnippet(snippet, context: modelContext)`; also clear the selection if `selectedSnippetID == snippet.persistentModelID` (mirror `performDeleteSnippet`), do NOT append to `lastDeletion`, and do NOT show a toast.

**Verify**: build → exit 0.

### Step 3: Route `performTrashCleanup` through the helper

Replace the body of `performTrashCleanup()` with a call to `TrashLifecycle.cleanup(...)` passing `trashedSnippets`, the soft-deleted collections (filter the existing `collections` query for `deletedAt != nil` — check how `trashedSnippets` is defined near the top of the file and mirror it), the 30-day cutoff, and `modelContext`. Handle the thrown error per step 4.

**Verify**: build → exit 0.

### Step 4: Surface save failures instead of `try?`

For every `try? modelContext.save()` in `ContentView.swift` (lines ~1085, 1114, 1154, 1171, 1345, 1364, 1409, 1416 at planning time), replace with a `do/catch` that calls a new private helper:

```swift
private func saveOrToast(_ context: ModelContext) {
    do { try context.save() }
    catch { showToast("Couldn't save changes: \(error.localizedDescription)") }
}
```

(Match the editor's pattern of capturing `error.localizedDescription`; the toast is the surfacing mechanism this view already has.)

**Verify**: `grep -cn "try? modelContext.save()" Sources/Snippets/Views/ContentView.swift` → `0`; build → exit 0.

### Step 5: Write the tests (see Test plan)

**Verify**: test command → all pass, including the new `TrashLifecycleTests`.

## Test plan

New file `Tests/SnippetsTests/TrashLifecycleTests.swift`, modeled structurally on `Tests/SnippetsTests/SnippetEditorViewModelTests.swift` (`@MainActor final class … XCTestCase`, and its `makeInMemoryContainer()` helper — copy that helper, including the comment about keeping the container alive). Cases:

1. `cleanup` purges a snippet with `deletedAt` 31 days ago and keeps one 29 days ago.
2. `cleanup` purges a collection with `deletedAt` 31 days ago (regression for the missing-collection-purge bug) and keeps a fresh one.
3. `cleanup` of an expired collection does not delete its live member snippets, and those snippets no longer reference the purged collection.
4. `purgeSnippet` removes the model (fetch returns nil afterwards). Media-file removal can be asserted only if `MediaManager` is injectable; if it is a hard singleton (`MediaManager.shared`), skip disk assertions and note it in the test.
5. `cleanup` propagates a thrown save error (if hard to trigger with in-memory stores, cover via the throws signature compiling + a comment).

## Done criteria

- [ ] Test command exits 0; `TrashLifecycleTests` exists with ≥ 4 passing tests
- [ ] `grep -c "try? modelContext.save()" Sources/Snippets/Views/ContentView.swift` → 0
- [ ] `deleteCollectionContentsRecursively` contains a `permanent` branch for snippets (grep for `purgeSnippet`)
- [ ] `performTrashCleanup` handles collections (grep the function body for `collection`)
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts above don't match the live code (drift).
- You cannot determine how `trashedSnippets` / the collections query are declared, or there is no query that yields soft-deleted collections — report what exists instead.
- Making `MediaManager` file deletion testable seems to require modifying `MediaManager.swift` — that is out of scope; skip that assertion instead.
- Product-intent doubt: if you find UI copy or a setting implying purged collections should *keep* their snippets alive even on permanent delete-with-contents, stop and report — step 2's purge choice would destroy data against intent.

## Maintenance notes

- The future god-file refactor should move `TrashLifecycle` (and the rest of the delete/undo logic) out of `ContentView.swift`; keep its API context-injected so the tests survive the move.
- Reviewer should scrutinize step 2: permanent purge of snippets is irreversible — confirm the confirmation dialog upstream (`collectionToDelete` flow at `:1290-1307`) still gates it.
- Deferred: renaming the custom `isDeleted` (shadows `PersistentModel.isDeleted`) — recorded finding, separate change.

# Plan 006: Characterization tests for the App Intents surface

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Intents/ Tests/SnippetsTests/`
> On changes to `Sources/Snippets/Intents/`, compare the "Current state"
> excerpts against the live code; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (additive tests; one small refactor for injectability may be needed — see STOP conditions)
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

The App Intents (Shortcuts/Siri automation surface) create, mutate, favorite, open, and copy snippets against the shared SwiftData container — and none of them have any test. Only helpers they call (`SnippetQueryFilter`, `UUIDBackfill`) are covered. A regression here silently corrupts user data from automations and is invisible to `swift test`. These are characterization tests: pin current behavior, including the error branches.

## Current state

- Intents (all in `Sources/Snippets/Intents/Actions/`): `CreateSnippetIntent.swift`, `FindSnippetsIntent.swift`, `CopySnippetIntent.swift`, `ToggleFavoriteSnippetIntent.swift`, `OpenSnippetIntent.swift`, `NewSnippetIntent.swift`. No test file references any of them (`grep -rn "Intent" Tests/` → nothing relevant).
- The blocking design fact: each `perform()` obtains its context internally, e.g. `CreateSnippetIntent.swift:29-33`:
  ```swift
  @MainActor
  func perform() async throws -> some IntentResult & ReturnsValue<SnippetEntity> & ProvidesDialog {
      let context = SnippetsData.sharedModelContainer.mainContext
      let snippet = Snippet(title: title, language: language, code: code)
      context.insert(snippet)
      if let collection {
          guard let target = try SnippetStore.collection(uuid: collection.id, in: context) else {
              throw SnippetIntentError.collectionNotFound
          }
          snippet.collections.append(target)
          target.updatedAt = .now
      }
      try context.save()
      ...
  }
  ```
  `SnippetsData.sharedModelContainer` is the app's real on-disk container — tests must NOT run intents against it.
- Lookup helpers, `Sources/Snippets/Intents/SnippetStore.swift` — `@MainActor enum SnippetStore` with `snippet(uuid:in:)` / `collection(uuid:in:)`, both fetching live (`deletedAt == nil`) models and matching `uuid`. `SnippetIntentError` has `.snippetNotFound` / `.collectionNotFound` cases (same file, `:4-15`).
- Test exemplar: `Tests/SnippetsTests/SnippetEditorViewModelTests.swift` — `@MainActor final class … XCTestCase` with:
  ```swift
  // Returns the container: the context alone does not keep it alive, and
  // inserting into a context whose container was deallocated traps.
  private func makeInMemoryContainer() throws -> ModelContainer {
      try ModelContainer(
          for: Snippet.self, MediaItem.self, SnippetCollection.self,
          configurations: ModelConfiguration(isStoredInMemoryOnly: true)
      )
  }
  ```
- `FindSnippetsIntent.swift:25-52` — fetches, runs `UUIDBackfill`, filters via `SnippetQueryFilter` (query/language/favorites/collection membership).
- Related latent findings to characterize (do not fix): `SnippetEntity.swift:24` fabricates `id: snippet.uuid ?? UUID()` when uuid is nil; `FindSnippetsIntent` doesn't backfill collections reached via relationships.

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |
| One test class | append `--filter SnippetIntentLogicTests` to the test command | targeted run passes |

## Scope

**In scope**:
- `Tests/SnippetsTests/SnippetIntentLogicTests.swift` (create)
- `Sources/Snippets/Intents/Actions/*.swift` and `Sources/Snippets/Intents/SnippetStore.swift` — ONLY the minimal injectability refactor described in Step 1, nothing behavioral
- `Snippets.xcodeproj/project.pbxproj` — ONLY if step 1 creates a new file under `Sources/` (register it; see commit `e017328d` for the pattern). Modifying existing files needs no registration.

**Out of scope**:
- Fixing the latent uuid/backfill findings — characterize current behavior only.
- `AppIntentNavigator`, App Shortcuts phrases, entity display representations.
- Any UI file.

## Git workflow

- Branch: `advisor/006-app-intents-tests`
- Short sentence-case imperative commit subjects; commit the refactor and the tests separately.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Make the intents' core logic testable without the shared container

Preferred (smallest diff): extract each intent's `perform()` body into a static function taking `ModelContext`, which `perform()` calls with the shared context. Example shape for Create:

```swift
extension CreateSnippetIntent {
    @MainActor
    static func execute(title: String, code: String, language: String,
                        collectionID: UUID?, in context: ModelContext) throws -> Snippet { ... }
}
```

`perform()` becomes a thin wrapper (shared context + dialog/result construction). Repeat for Find / Copy (clipboard write stays in `perform`; the lookup+error logic moves) / ToggleFavorite. `OpenSnippetIntent` and `NewSnippetIntent` are likely navigation-only — inspect them; if they only call `AppIntentNavigator`, cover them with at most a lookup-error test and note it.

**Verify**: build → exit 0 (no behavior change; `perform()` outputs identical).

### Step 2: Write the tests

Create `Tests/SnippetsTests/SnippetIntentLogicTests.swift`, `@MainActor`, modeled on `SnippetEditorViewModelTests` (copy `makeInMemoryContainer()` verbatim, including its comment). Cases:

1. Create: inserts a snippet with given title/language/code; persisted after save (re-fetch).
2. Create into a collection: snippet appended to the collection, `collection.updatedAt` bumped.
3. Create with an unknown collection UUID: throws `SnippetIntentError.collectionNotFound`, and no snippet remains persisted (characterize: does the current code leave the inserted snippet in the context? Assert whatever is true and comment it).
4. ToggleFavorite: flips `isFavorite` and persists; unknown UUID throws `.snippetNotFound`.
5. Find: returns matching live snippets; excludes soft-deleted (`deletedAt != nil`); respects the language and favorites filters (mirror what `SnippetQueryFilter` receives).
6. Find backfills missing `uuid`s (assert a snippet inserted with `uuid = nil` has a non-nil uuid after execute).
7. Copy: lookup by uuid returns the right snippet's code; unknown uuid throws (skip actual NSPasteboard assertions if the clipboard write stayed in `perform`).

**Verify**: targeted test command → all new tests pass.

### Step 3: Full suite

**Verify**: full test command → exit 0, no existing test broken.

## Test plan

Covered by step 2 (this plan IS the test plan). Pattern source: `Tests/SnippetsTests/SnippetEditorViewModelTests.swift`.

## Done criteria

- [ ] `Tests/SnippetsTests/SnippetIntentLogicTests.swift` exists with ≥ 7 passing tests
- [ ] Full test command exits 0
- [ ] Each refactored intent's `perform()` is a thin wrapper (no fetch/mutation logic left inline) — visible in diff
- [ ] `grep -rn "sharedModelContainer" Tests/` → 0 matches (tests never touch the real store)
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Excerpts don't match (drift).
- The extraction in step 1 requires changing an intent's parameter/result types or any `AppIntent` protocol surface — that risks breaking registered Shortcuts; stop and report.
- `Snippet`/`SnippetCollection` initializers used in tests don't match what `SnippetEditorViewModelTests` uses — check that file first; if models changed, report.
- App Intents metadata processing fails the build after the refactor (the `appintentsmetadataprocessor` can be finicky about extensions) — report the exact error rather than restructuring further.

## Maintenance notes

- Every new intent should get an `execute(...in context:)` twin and tests — note this in CLAUDE.md (plan 001) if convenient.
- These are characterization tests: cases 3 and 6 pin possibly-imperfect current behavior. When the latent uuid findings are fixed, update those assertions deliberately.
- Plan 007 (CI) depends on this suite being green and fast.

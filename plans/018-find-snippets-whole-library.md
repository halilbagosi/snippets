# Plan 018: Make the "Find Snippets" Shortcuts action search the whole library

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 41ed0b44 -- Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift Tests/SnippetsTests/SnippetIntentLogicTests.swift`
> (no `..HEAD` — this compares the working tree, so uncommitted edits count
> too). If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `41ed0b44`, 2026-10-07

## Why this matters

`FindSnippetsIntent` (the "Find Snippets" action in Shortcuts and Siri) fetches
only the 200 most recently edited snippets and *then* applies the text,
collection and favorites filters. In a library with more than 200 snippets, an
older snippet can never be found: searching "Parser" returns an empty list
when "Parser" was last edited before the 200 newest, and "Favorites Only" and
the collection filter silently drop older members too. The result is
incomplete with no error. After this plan, the whole library is filtered
first and the 200 cap applies only to the *results*.

## Current state

- `Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift` — the intent; its
  testable core is `static func execute(searchText:collectionID:favoritesOnly:in:)`.
- `Sources/Snippets/Intents/SnippetQueryFilter.swift` — the pure filter it calls
  (do not change it in this plan).
- `Tests/SnippetsTests/SnippetIntentLogicTests.swift` — characterization tests
  for the intents, using an in-memory `ModelContainer`.

`FindSnippetsIntent.swift:36-66` today:

```swift
    /// Core logic, context-injected for tests.
    @MainActor
    static func execute(
        searchText: String?, collectionID: UUID?, favoritesOnly: Bool,
        in context: ModelContext
    ) throws -> [Snippet] {
        var descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let snippets = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: snippets, collections: []) > 0 {
            try? context.save()
        }

        return SnippetQueryFilter.filter(
            snippets,
            query: searchText,
            collectionUUID: collectionID,
            favoritesOnly: favoritesOnly,
            projection: { snippet in
                SnippetQueryFilter.Candidate(
                    ...
                )
            }
        )
    }
```

Test pattern to copy — `SnippetIntentLogicTests.swift:102-128`
(`test_find_returnsLiveMatches_excludesDeleted_respectsFilters`): it builds a
container with `makeInMemoryContainer()`, inserts `Snippet(title:language:code:...)`
values, saves, then calls `FindSnippetsIntent.execute(...)`. The `Snippet`
initializer accepts `updatedAt:` (see `Sources/Snippets/Models/Snippet.swift:47-60`).

Comment style in this repo: explain *why*, in full sentences, above the line
(see the existing comments in `FindSnippetsIntent.swift`).

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Focused tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/SnippetIntentLogicTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` (a run briefly launches Snippets.app) |

## Scope

**In scope** (the only files you should modify):
- `Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift`
- `Tests/SnippetsTests/SnippetIntentLogicTests.swift`

**Out of scope** (do NOT touch):
- `Sources/Snippets/Intents/SnippetQueryFilter.swift` — a separate plan (024)
  rewrites its matching; changing it here causes a merge conflict.
- `Sources/Snippets/Intents/Entities/SnippetEntity.swift` — its query has no
  limit and is already correct.
- Any other file that the working tree shows as modified — that is the
  owner's in-progress work. Stage only the two in-scope files.

## Git workflow

- Branch: `advisor/018-find-snippets-whole-library`
- Commit message style matches `git log`: one plain imperative sentence, e.g.
  `Search the whole library in Find Snippets, then cap the results`.
- `git add` the in-scope paths explicitly — never `git add -A`.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Write the failing test

In `SnippetIntentLogicTests.swift`, inside the `// MARK: Find` section, add:

```swift
    func test_find_searchesBeyondTheNewest200_andCapsResults() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        // The target is the *oldest* snippet; 250 newer ones bury it.
        let target = Snippet(title: "Parser", code: "p", updatedAt: .distantPast)
        context.insert(target)
        for index in 0..<250 {
            context.insert(Snippet(title: "Note \(index)", code: "n", updatedAt: .now))
        }
        try context.save()

        let found = try FindSnippetsIntent.execute(
            searchText: "Parser", collectionID: nil, favoritesOnly: false, in: context
        )
        XCTAssertEqual(found.map(\.title), ["Parser"])

        // Unfiltered, the result is still capped so Shortcuts never receives
        // an unbounded array.
        let all = try FindSnippetsIntent.execute(
            searchText: nil, collectionID: nil, favoritesOnly: false, in: context
        )
        XCTAssertEqual(all.count, 200)
    }
```

**Verify**: focused tests command → `** TEST FAILED **`, and the output names
`test_find_searchesBeyondTheNewest200_andCapsResults` (the first assertion
fails with `[] != ["Parser"]`).

### Step 2: Filter first, cap after

In `FindSnippetsIntent.execute`:

1. Delete the line `descriptor.fetchLimit = 200` (and change `var descriptor`
   to `let descriptor`).
2. Wrap the `SnippetQueryFilter.filter(...)` result so the cap applies to the
   matches, keeping the newest-first order the fetch already provides:

```swift
        // Filter the whole library, then cap. Capping the fetch instead made
        // anything older than the 200 most recently edited snippets
        // unfindable, with no error to say so.
        let matched = SnippetQueryFilter.filter(
            snippets,
            ...unchanged arguments...
        )
        return Array(matched.prefix(Self.resultLimit))
```

3. Add `static let resultLimit = 200` to the struct, with a one-line comment
   that it bounds what Shortcuts receives.

Leave the `UUIDBackfill.assign` call as it is — it now runs over every live
snippet, which is what it is for.

**Verify**: focused tests command → `** TEST SUCCEEDED **`.

### Step 3: Full suite

**Verify**: build command → `** BUILD SUCCEEDED **`; full tests command →
`** TEST SUCCEEDED **`.

## Test plan

- New: `test_find_searchesBeyondTheNewest200_andCapsResults` (step 1) covers the
  bug and the result cap.
- Existing `test_find_returnsLiveMatches_excludesDeleted_respectsFilters` and
  `test_find_backfillsMissingSnippetUUIDs` must still pass unchanged.

## Done criteria

- [ ] `grep -n "fetchLimit" Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift` returns nothing
- [ ] `grep -n "resultLimit" Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift` shows the constant and its use
- [ ] Full test suite → `** TEST SUCCEEDED **`, including the new test
- [ ] `git status` shows no changes of yours outside the two in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

- The `execute` function no longer matches the excerpt (for example it already
  has no `fetchLimit`, or it sorts differently).
- The new test still fails after step 2 — do not change the test's numbers to
  make it pass; report the actual output.
- The full suite fails in a test outside `SnippetIntentLogicTests` that you
  cannot connect to this change.

## Maintenance notes

- The whole library is now fetched on each Find. That includes code bodies
  (SwiftData faults them lazily, but filtering touches title, description and
  language only). At realistic library sizes (thousands) this is fine; if it
  ever matters, move the favorites and collection conditions into the
  `#Predicate`.
- Plan 024 changes how `SnippetQueryFilter` matches text (multi-word,
  accent-insensitive). It does not interact with the cap.

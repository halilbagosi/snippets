# Plan 024: One snippet search everywhere — multi-word, case- and accent-insensitive, and fast

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 41ed0b44 -- Sources/Snippets/Intents/SnippetQueryFilter.swift Sources/Snippets/Views/ContentView.swift Sources/Snippets/Views/TrashView.swift Tests/SnippetsTests/SnippetQueryFilterTests.swift Tests/SnippetsTests/SnippetFilterCacheTests.swift`
> (includes uncommitted edits). Plan 019 edits `ContentView.swift` lines
> ~453/1611/1650 and adds a test to `SnippetFilterCacheTests.swift`; those
> changes are expected. Any change to the functions excerpted below is a STOP
> condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (matching only gets broader, see "Why this matters")
- **Depends on**: plan 019 should land first (same two files, nearby lines)
- **Category**: tech-debt / bug
- **Planned at**: commit `41ed0b44`, 2026-10-07

## Why this matters

Three separate text matchers exist: the gallery, the Trash, and
`SnippetQueryFilter` (used by both the quick-copy panel and Shortcuts). Each is
a single case-insensitive substring search on the *whole* query. The natural
queries fail:

- `swift parser` finds nothing for a Swift snippet titled "JSON parser",
  because the phrase isn't contiguous in any one field.
- `user fetch` finds nothing for "Fetch user profile".
- `cafe` doesn't find "Café menu" (no accent folding).

After this plan, one `SnippetSearch` type is used everywhere. It splits the
query into words; every word must appear in at least one field; matching
ignores case and accents. Each call site still chooses its own fields
(the gallery also searches code and collection names; quick copy and
Shortcuts search title, description and language).

This **can only add matches, never remove one**. If the whole query occurred
in a field, then each of its words occurs in that field too.

Bonus: the matcher compares through `NSString`. A measurement (1000 snippets
× 5 KB of code, a query with no hits) took **560 ms** with Swift's
`String.range(of:options:)` and **26 ms** with `(field as NSString).range(of:options:)`,
including the bridge. Accent-insensitivity added no measurable cost. The
gallery searches every snippet's full code, so this also speeds up typing in
the search field.

## Current state

- `Sources/Snippets/Intents/SnippetQueryFilter.swift` — pure filter used by
  `QuickCopyResults.sections` (`Features/QuickCopy/QuickCopyResults.swift:41`),
  `SnippetEntityQuery.entities(matching:)` (`Intents/Entities/SnippetEntity.swift:62`)
  and `FindSnippetsIntent` (via `filter`).

`SnippetQueryFilter.swift:15-23`:
```swift
    /// Case-insensitive substring match across title, description, and language.
    /// An empty/whitespace query matches everything.
    static func matches(title: String, description: String, language: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return title.range(of: needle, options: .caseInsensitive) != nil
            || description.range(of: needle, options: .caseInsensitive) != nil
            || language.range(of: needle, options: .caseInsensitive) != nil
    }
```

`Sources/Snippets/Views/ContentView.swift:1666-1693` (in `enum GallerySnippetFilter`):
```swift
    /// Case-insensitive substring match without allocating a lowercased copy
    /// of `haystack` (search runs over every snippet's full code per pass).
    static func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    static func searchResults(in pool: [Snippet], needle: String) -> [Snippet] {
        guard !needle.isEmpty else { return [] }

        return pool.filter { snippet in
            matches(snippet.title, needle) ||
            matches(snippet.snippetDescription, needle) ||
            matches(snippet.code, needle) ||
            matches(snippet.language, needle) ||
            snippet.collections.contains { !$0.isDeleted && matches($0.name, needle) }
        }
    }

    static func searchCollections(
        _ collections: [SnippetCollection], needle: String, showFavoritesOnly: Bool
    ) -> [SnippetCollection] {
        guard !needle.isEmpty else { return [] }

        return collections.filter { collection in
            !collection.isDeleted &&
            (!showFavoritesOnly || collection.isFavorite) &&
            matches(collection.name, needle)
        }
    }
```

`Sources/Snippets/Views/TrashView.swift:24-44`:
```swift
    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Case-insensitive substring match without allocating a lowercased copy
    /// of `haystack` (runs over every trashed snippet's full code per pass).
    private func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: .caseInsensitive) != nil
    }

    private var matchingTrashedSnippets: [Snippet] {
        let needle = trimmedSearchText
        guard !needle.isEmpty else { return [] }

        return trashedSnippets.filter { snippet in
            matches(snippet.title, needle) ||
            matches(snippet.snippetDescription, needle) ||
            matches(snippet.code, needle) ||
            matches(snippet.language, needle)
        }
    }
```

Tests: `Tests/SnippetsTests/SnippetQueryFilterTests.swift` (pure, no SwiftData;
see `test_matches_isCaseInsensitiveAcrossFields` at line 26) and
`Tests/SnippetsTests/SnippetFilterCacheTests.swift` (in-memory SwiftData; see
`test_searchResults_matchTitleAndCode_respectNeedle` around line 100).

**File placement:** put `SnippetSearch` in the existing
`SnippetQueryFilter.swift`, above `enum SnippetQueryFilter`. A new file would
have to be registered in `Snippets.xcodeproj/project.pbxproj` (this project
lists files explicitly), and an unregistered file is silently not compiled.

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Focused tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/SnippetQueryFilterTests -only-testing:SnippetsTests/SnippetFilterCacheTests -only-testing:SnippetsTests/QuickCopyResultsTests -only-testing:SnippetsTests/SnippetIntentLogicTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |

## Scope

**In scope**:
- `Sources/Snippets/Intents/SnippetQueryFilter.swift`
- `Sources/Snippets/Views/ContentView.swift` — `GallerySnippetFilter.matches`, `searchResults`, `searchCollections` only
- `Sources/Snippets/Views/TrashView.swift` — `matches` and `matchingTrashedSnippets` only
- `Tests/SnippetsTests/SnippetQueryFilterTests.swift`, `Tests/SnippetsTests/SnippetFilterCacheTests.swift`

**Out of scope** (do NOT touch):
- **Which fields** each surface searches. Adding code bodies to quick copy and
  Shortcuts is deliberately deferred to the quick-copy ranking work, because
  without ranking it adds noisy matches in arbitrary order.
- `QuickCopyResults.swift` ordering and sectioning. It calls
  `SnippetQueryFilter.matches` and needs no edit.
- Collection-name-only filters: `Features/Gallery/CollectionMoveTree.swift:47`,
  `SnippetGalleryView.swift:136`, and `SnippetEditorView.swift:646` (the
  latter has the owner's uncommitted work).
- `FindSnippetsIntent.swift` (plan 018).

## Git workflow

- Branch: `advisor/024-shared-snippet-search`
- Commit message: `Search snippets by every word, ignoring case and accents, in one shared matcher`
- `git add` the in-scope paths only. Do NOT push unless instructed.

## Steps

### Step 1: Failing tests

In `SnippetQueryFilterTests.swift` add:

```swift
    func test_search_everyWordMustMatchSomeField_inAnyOrder() {
        XCTAssertTrue(SnippetQueryFilter.matches(title: "JSON parser", description: "", language: "Swift", query: "swift parser"))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "Fetch user profile", description: "", language: "Swift", query: "user fetch"))
        XCTAssertFalse(SnippetQueryFilter.matches(title: "Fetch user profile", description: "", language: "Swift", query: "user delete"))
    }

    func test_search_ignoresAccents() {
        XCTAssertTrue(SnippetQueryFilter.matches(title: "Café menu", description: "", language: "Swift", query: "cafe"))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "Kód", description: "", language: "Swift", query: "kod"))
    }

    func test_searchTerms_splitOnAnyWhitespace() {
        XCTAssertEqual(SnippetSearch.terms("  a \t b\nc  "), ["a", "b", "c"])
        XCTAssertEqual(SnippetSearch.terms("   "), [])
    }
```

In `SnippetFilterCacheTests.swift` add:

```swift
    func test_searchResults_matchWordsAcrossFieldsAndCollections() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let networking = SnippetCollection(name: "Networking")
        let snippet = Snippet(title: "Retry helper", language: "Swift", code: "func retry() {}")
        context.insert(networking)
        context.insert(snippet)
        snippet.collections = [networking]
        try context.save()

        // "networking" is only the collection's name, "retry" only the title.
        XCTAssertEqual(GallerySnippetFilter.searchResults(in: [snippet], needle: "networking retry").map(\.title), ["Retry helper"])
        XCTAssertTrue(GallerySnippetFilter.searchResults(in: [snippet], needle: "networking delete").isEmpty)
        XCTAssertEqual(GallerySnippetFilter.searchCollections([networking], needle: "netw", showFavoritesOnly: false).map(\.name), ["Networking"])
    }
```

**Verify**: build fails because `SnippetSearch` does not exist. That is the
expected red state.

### Step 2: Add `SnippetSearch`

In `SnippetQueryFilter.swift`, above `enum SnippetQueryFilter`, add:

```swift
/// Text search shared by every surface that searches snippets — the gallery,
/// Trash, the quick-copy panel and Shortcuts — so a query means the same thing
/// everywhere. The query is split into words; every word must appear in at
/// least one field, ignoring case and accents, so word order and contiguity
/// don't matter ("swift parser" finds a Swift snippet titled "JSON parser").
enum SnippetSearch {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    /// The words of a query. Empty for a blank query.
    static func terms(_ query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Whether every term occurs in at least one field. No terms matches.
    static func matches(terms: [String], in fields: [String]) -> Bool {
        terms.allSatisfy { term in
            fields.contains { contains($0, term) }
        }
    }

    /// Compares through NSString: Swift's `String.range(of:options:)` is about
    /// 20x slower on large native strings, and the gallery searches every
    /// snippet's full code on each keystroke.
    private static func contains(_ haystack: String, _ term: String) -> Bool {
        (haystack as NSString).range(of: term, options: options).location != NSNotFound
    }
}
```

**Verify**: build command → `** BUILD SUCCEEDED **`.

### Step 3: Route the three matchers through it

1. `SnippetQueryFilter.matches(title:description:language:query:)`: keep the
   signature and replace the body and doc comment with:
   ```swift
    /// Every word of the query in title, description, or language (see
    /// `SnippetSearch`). An empty/whitespace query matches everything.
    static func matches(title: String, description: String, language: String, query: String) -> Bool {
        SnippetSearch.matches(terms: SnippetSearch.terms(query), in: [title, description, language])
    }
   ```
2. `GallerySnippetFilter` in `ContentView.swift`: delete `static func matches(_:_:)`
   and its comment. Then rewrite the other two functions:
   ```swift
    static func searchResults(in pool: [Snippet], needle: String) -> [Snippet] {
        let terms = SnippetSearch.terms(needle)
        guard !terms.isEmpty else { return [] }

        return pool.filter { snippet in
            let collectionNames = snippet.collections.compactMap { $0.isDeleted ? nil : $0.name }
            return SnippetSearch.matches(
                terms: terms,
                in: [snippet.title, snippet.snippetDescription, snippet.code, snippet.language] + collectionNames
            )
        }
    }

    static func searchCollections(
        _ collections: [SnippetCollection], needle: String, showFavoritesOnly: Bool
    ) -> [SnippetCollection] {
        let terms = SnippetSearch.terms(needle)
        guard !terms.isEmpty else { return [] }

        return collections.filter { collection in
            !collection.isDeleted &&
            (!showFavoritesOnly || collection.isFavorite) &&
            SnippetSearch.matches(terms: terms, in: [collection.name])
        }
    }
   ```
3. `TrashView.swift`: delete `private func matches(_:_:)` and its comment.
   Then rewrite `matchingTrashedSnippets`:
   ```swift
    private var matchingTrashedSnippets: [Snippet] {
        let terms = SnippetSearch.terms(searchText)
        guard !terms.isEmpty else { return [] }

        return trashedSnippets.filter { snippet in
            SnippetSearch.matches(
                terms: terms,
                in: [snippet.title, snippet.snippetDescription, snippet.code, snippet.language]
            )
        }
    }
   ```
   If `trimmedSearchText` is now unused, the build will warn. Delete it only
   if `grep -n "trimmedSearchText" Sources/Snippets/Views/TrashView.swift`
   shows no other use.

**Verify**: build → `** BUILD SUCCEEDED **` with no new warnings in these
files. `grep -rn "options: .caseInsensitive) != nil" Sources/Snippets/Intents/SnippetQueryFilter.swift Sources/Snippets/Views/TrashView.swift`
→ no matches. `grep -n "range(of: needle" Sources/Snippets/Views/ContentView.swift`
→ no matches. Focused tests → `** TEST SUCCEEDED **`.

### Step 4: Full suite

**Verify**: full tests command → `** TEST SUCCEEDED **`.

## Test plan

- New: multi-word in any order, a word that matches nothing fails the query,
  accents, splitting, and gallery words across title plus collection names
  (step 1).
- Existing tests that must pass unchanged: `test_matches_isCaseInsensitiveAcrossFields`,
  `test_matches_emptyOrWhitespaceQuery_returnsTrue`,
  `test_searchResults_matchTitleAndCode_respectNeedle`,
  `test_searchCollections_excludesDeleted_respectsFavorites`, all
  `QuickCopyResultsTests`, and the Find tests in `SnippetIntentLogicTests`.

## Done criteria

- [ ] `grep -rn "enum SnippetSearch" Sources` → 1 match, in `SnippetQueryFilter.swift`
- [ ] The step 3 greps return no matches
- [ ] Full tests → `** TEST SUCCEEDED **`
- [ ] `git status` shows changes of yours only in the in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

- An existing test fails because it asserted that a multi-word or accented
  query does **not** match. Report which one: that is a product decision, not
  a test to edit.
- `GallerySnippetFilter.matches(_:_:)` turns out to have callers outside
  `ContentView.swift`. Check with `grep -rn "GallerySnippetFilter.matches" Sources Tests`
  before deleting it, and if there are any, keep it as a thin wrapper instead.
- The gallery's filter cache (plan 010's memoization in
  `SnippetGalleryView.swift`) stops invalidating correctly. Symptom: stale
  results in a `SnippetFilterCacheTests` failure. Do not modify the cache
  signature yourself; report it.

## Maintenance notes

- Next step (deferred): relevance ranking for the quick-copy panel. Typing
  plus Enter copies whatever sorts first, by recency or copy count rather
  than relevance. Ranking should build on `SnippetSearch.terms`. Once ranking
  exists, adding `code` to the quick-copy and Shortcuts fields becomes safe.
- Any new search surface must use `SnippetSearch`, not a fresh
  `range(of:options:)`.
- Quoted phrases (`"exact phrase"`) are not supported. Every whitespace
  splits the query.

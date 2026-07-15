# Plan 010: Memoize gallery filtering/search so unrelated re-renders stop re-scanning every snippet

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 79537db3..HEAD -- Sources/Snippets/Views/ContentView.swift`
> Plan 002 modifies the same file (delete paths, not the filter section);
> reconcile with its changes. On mismatches in the filter-section excerpts
> below, STOP.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (a wrong cache signature shows stale search results — worse than slow ones)
- **Depends on**: 002 (same-file ordering only; logic is independent)
- **Category**: perf
- **Planned at**: commit `79537db3`, 2026-07-15

## Why this matters

`ContentView`'s filter chain — `baseFilteredSnippets`, `searchFilteredSnippets`, `searchResultSnippets`, `searchResultCollections` — are computed properties that re-run full scans over all snippets on **every body evaluation**, including renders triggered by unrelated state (selection, hover, sheet presentation, toasts). `searchResultSnippets` substring-matches every snippet's **entire code text** and internally re-derives `searchFilteredSnippets` (a second full pass). The 300ms search debounce throttles typing but not re-renders. The file already contains the exact right pattern for the fix — `CollectionIndexCache`, a non-observed cache class refreshed on a structure signature — so this plan extends that established pattern rather than inventing one.

## Current state

All in `Sources/Snippets/Views/ContentView.swift` (line numbers at planning time; plan 002 may shift them — anchor by symbol names):

- The exemplar pattern (`:133-155`):
  ```swift
  /// Memoized collection indexes. Plain (non-observed) class on purpose:
  /// refreshing it during body evaluation must not invalidate the view, and
  /// the signature check keeps it consistent with the `collections` query.
  private final class CollectionIndexCache {
      var signature: Int? = nil
      var lookup: [PersistentIdentifier: SnippetCollection] = [:]
      var descendantIDs: [PersistentIdentifier: Set<PersistentIdentifier>] = [:]
  }
  @State private var collectionIndexCache = CollectionIndexCache()

  private var collectionStructureSignature: Int { /* Hasher over collections' ids + parent ids */ }
  private func refreshCollectionIndexCacheIfNeeded() { guard cache.signature != signature else { return } ... }
  ```
- `baseFilteredSnippets` (`:192-224`) — filters `snippets` by language / selected collection (direct membership) / uncategorized / search-collections (descendant membership) / favorites.
- `searchFilteredSnippets` (`:226-245`) — same minus the selected-collection constraint.
- `matches(_:_:)` (`:247-251`) — case-insensitive `range(of:)`, deliberately allocation-free; keep it.
- `searchResultSnippets` (`:264-275`) — `searchFilteredSnippets.filter { matches(title) || matches(description) || matches(code) || matches(language) || collection-name match }` gated on `trimmedSearchText`.
- `searchResultCollections` (`:253-262`) — scans `collections` by name.
- Inputs feeding the chain: `snippets` (a `@Query`), `selectedLanguages`, `selectedCollectionID`, `showUncategorizedOnly`, `selectedSearchCollections`, `showFavoritesOnly`, `debouncedSearchText` (via `trimmedSearchText`), plus collection structure/deletion state.
- **The hard part — a correct snippet signature**: unlike the collection cache (structure only), filter results depend on snippet *content* (`code`, `title`, favorites, `deletedAt`, collection membership) . A signature must hash, per snippet: `persistentModelID` and `updatedAt` (the codebase consistently bumps `updatedAt` on mutations — e.g. delete paths and editor save do), plus each snippet's collection membership ids, plus the collection-structure signature, plus every filter input listed above. If any mutation path does NOT bump `updatedAt`, the cache would serve stale results — verify before trusting it (see STOP conditions).

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Build | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build --build-path /tmp/snippets-build` | exit 0 |
| Tests | `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --build-path /tmp/snippets-test-build` | all pass |

## Scope

**In scope**:
- `Sources/Snippets/Views/ContentView.swift`
- `Tests/SnippetsTests/SnippetFilterCacheTests.swift` (create) — only if step 1's extraction makes the logic testable; see steps
- `Snippets.xcodeproj/project.pbxproj` — only if a new `Sources/` file is created (register it)

**Out of scope**:
- `SnippetGalleryViewModel` / `SnippetQueryFilter` (the intents-side filter — different code path).
- Changing filter *semantics* in any way — results must be identical, only cheaper.
- The delete/trash logic (plan 002 territory).

## Git workflow

- Branch: `advisor/010-gallery-filter-memoization`
- Short sentence-case imperative subjects; commit per step.
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Verify the `updatedAt` invariant

Grep every mutation of `Snippet` fields that affect filtering (`isFavorite`, `deletedAt`, `collections`, `code`, `title`, `language`) and confirm each bumps `updatedAt`. Check at minimum: `ContentView` delete/restore/favorite paths, `SnippetEditorViewModel.save`, drag-drop collection moves, and the App Intents (`ToggleFavoriteSnippetIntent`, `CreateSnippetIntent`). Record the result as a comment on the cache class. If any path mutates without bumping `updatedAt`, either add the bump there (small, in-scope for ContentView; STOP if it's elsewhere) or include that field directly in the signature.

**Verify**: a written list (in the commit message or code comment) of checked mutation sites.

### Step 2: Add a `SnippetFilterCache` following the `CollectionIndexCache` pattern

Non-observed final class held in `@State`, storing: `signature: Int?`, `base: [Snippet]`, `searchFiltered: [Snippet]`, `searchResults: [Snippet]`, `searchResultCollections: [SnippetCollection]`. Signature = Hasher over: each snippet's `persistentModelID` + `updatedAt` (+ membership ids), `collectionStructureSignature`, and all filter inputs (languages, selected collection, uncategorized, search-collections, favorites, `trimmedSearchText`). One `refreshFilterCacheIfNeeded()` computes all four arrays in a single pass (compute `searchFiltered` once; derive `searchResults` from it — this also removes the existing double-derivation). The four computed properties become cache reads.

Keep the per-element predicate logic byte-for-byte identical to today's — move, don't rewrite.

**Verify**: build → exit 0; app behavior identical (no semantic diff in predicates).

### Step 3: Extract the pure filter core for testability (bounded)

If cheap (< ~100 lines moved): lift the predicate logic into a `struct GallerySnippetFilter` (plain function of inputs → outputs, no SwiftUI) in the same file, called by the cache refresh. This enables direct unit tests. If the entanglement with `@Query`/view state makes this bleed beyond the filter section, skip and test via signature behavior only — note it.

**Verify**: build → exit 0.

### Step 4: Tests

**Verify**: full test command → exit 0.

## Test plan

New `Tests/SnippetsTests/SnippetFilterCacheTests.swift`, modeled on `SnippetEditorViewModelTests` (in-memory container helper). Cases (adapt to what step 3 achieved):

1. Filtering matches expectations for: language filter, favorites, uncategorized, search text hitting title vs. code, soft-deleted exclusion.
2. Signature changes when a snippet's `updatedAt` bumps, when membership changes, and when any filter input changes.
3. Signature does NOT change for irrelevant state (same inputs twice → equal signatures) — the cache-hit case.
4. Regression: search results derived from the cached `searchFiltered` equal a from-scratch computation on the same data.

## Done criteria

- [ ] Full test suite exits 0 including new filter tests
- [ ] `baseFilteredSnippets`/`searchFilteredSnippets`/`searchResultSnippets`/`searchResultCollections` are cache reads (visible in diff); the double-derivation of `searchFilteredSnippets` inside `searchResultSnippets` is gone
- [ ] Step 1's mutation-site audit recorded as a code comment
- [ ] No filter semantics changed (predicates moved verbatim)
- [ ] No files outside scope modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

- Step 1 finds a mutation path outside `ContentView.swift` that skips `updatedAt` and can't be covered by adding the field to the signature — stale-cache risk needs a maintainer decision.
- The excerpted filter properties have materially changed (drift beyond plan 002's expected delete-path edits).
- SwiftData faulting behavior makes hashing `updatedAt` across all snippets itself expensive enough to defeat the purpose (if refresh-check cost is O(full scan of realized models) anyway, report findings with rough timings instead of shipping).

## Maintenance notes

- Any new filter input added to the gallery MUST be added to the signature — this is the classic failure mode of signature caches; reviewer should check the signature covers every input the predicates read.
- If the library grows to where even signature computation is hot, the next step is moving search to a proper index (e.g. incremental token index), not more caching here.
- Profiling before/after was deliberately skipped (maintainer accepted the structural argument); an Instruments comparison would still be good PR evidence.

# Plan 019: Treat unrecognized stored languages as Unknown everywhere the gallery filters

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 41ed0b44 -- Sources/Snippets/Services/LanguageDetector.swift Sources/Snippets/Views/ContentView.swift Sources/Snippets/Views/SnippetGalleryView.swift Tests/SnippetsTests/SnippetFilterCacheTests.swift`
> (no `..HEAD` — this includes uncommitted edits). If any in-scope file
> changed since this plan was written, compare the "Current state" excerpts
> against the live code before proceeding; on a mismatch, treat it as a STOP
> condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (land before plan 024, which edits `ContentView.swift` nearby)
- **Category**: bug
- **Planned at**: commit `41ed0b44`, 2026-10-07

## Why this matters

A snippet's `language` is a free-text `String`. Shortcuts' "Create Snippet"
action accepts any text (for example "Bash"), and the importer stores the
archive's value verbatim. `SupportedLanguage(rawValue:)` returns `nil` for such
values, and the gallery's language filter is written as
`if let lang = SupportedLanguage(rawValue:), !selected.contains(lang) { return false }`
— so a `nil` **passes every language filter**. With the Swift chip selected, a
"Bash" snippet is still in the filtered list (it just isn't drawn, because
section grouping files it under Unknown). "Select All" builds its selection
from that list, so Select All → Delete can trash a snippet the user never saw.
Separately, the Unknown chip never appears for such snippets, because the
"available languages" list drops `nil`s. After this plan, every unrecognized
value means `.unknown`, in one place.

## Current state

- `Sources/Snippets/Services/LanguageDetector.swift:3-35` — `enum SupportedLanguage`,
  with a custom `init?(rawValue:)` that canonicalizes case and whitespace.
- `Sources/Snippets/Views/ContentView.swift` — `enum GallerySnippetFilter`
  (pure filter core, starts at line 1599) and `buildAvailableLanguages()`.
- `Sources/Snippets/Views/SnippetGalleryView.swift` — section grouping and
  per-collection language sets.

Excerpts:

`ContentView.swift:452-455`
```swift
    private func buildAvailableLanguages() -> [SupportedLanguage] {
        let used = Set(snippets.compactMap { SupportedLanguage(rawValue: $0.language) })
        return SupportedLanguage.allCases.filter { used.contains($0) }
    }
```

`ContentView.swift:1611` (in `GallerySnippetFilter.base`) and `:1650` (in
`GallerySnippetFilter.searchPool`) — the same line twice:
```swift
            if !selectedLanguages.isEmpty, let lang = SupportedLanguage(rawValue: snippet.language), !selectedLanguages.contains(lang) { return false }
```

`SnippetGalleryView.swift:860-862` (already correct — the behavior to match):
```swift
        let grouped = Dictionary(grouping: ordered) { snippet in
            SupportedLanguage(rawValue: snippet.language) ?? .unknown
        }
```

`SnippetGalleryView.swift:1036-1040` (in `languages(in:favoritesOnly:)`):
```swift
        for snippet in collection.snippets where !snippet.isDeleted && (!favoritesOnly || snippet.isFavorite) {
            if let language = SupportedLanguage(rawValue: snippet.language) {
                result.insert(language)
            }
        }
```

Test pattern: `Tests/SnippetsTests/SnippetFilterCacheTests.swift:36-71`
(`test_base_filtersByLanguageFavoritesAndUncategorized`) and its private
`searchPool(_:favoritesOnly:uncategorizedOnly:languages:)` helper at lines 20-34.

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Focused tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/SnippetFilterCacheTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |

## Scope

**In scope**:
- `Sources/Snippets/Services/LanguageDetector.swift` — only add the new initializer next to `init?(rawValue:)`
- `Sources/Snippets/Views/ContentView.swift` — lines 453, 1611, 1650 only
- `Sources/Snippets/Views/SnippetGalleryView.swift` — lines 860-862 and 1036-1040 only
- `Tests/SnippetsTests/SnippetFilterCacheTests.swift`

**Out of scope** (do NOT touch):
- `ContentView.swift:471` (`buildBackgroundPalette`) and `Services/Theme.swift:80` —
  they deliberately skip unknown languages for colors.
- `Views/Sidebar/ModernSidebar.swift:98` — parses a sidebar selection, not stored data.
- `Features/Editor/SnippetEditorViewModel.swift` — plan 020 owns it.
- Normalizing what Shortcuts or the importer *write* — keeping the original
  text ("Bash") is useful if that language is supported later.
- The rest of `LanguageDetector.swift` — plan 023 edits the detector below.

## Git workflow

- Branch: `advisor/019-unknown-language-filtering`
- Commit message, plain imperative sentence: `Treat unrecognized languages as Unknown in gallery filters`
- `git add` the in-scope paths explicitly. Other files may be modified in the
  working tree by the owner — leave them unstaged.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Failing tests

Add to `SnippetFilterCacheTests.swift`:

```swift
    func test_unrecognizedLanguage_isFilteredAsUnknown() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let swift = Snippet(title: "A", language: "Swift", code: "a")
        let bash = Snippet(title: "B", language: "Bash", code: "b")
        context.insert(swift)
        context.insert(bash)
        try context.save()

        func base(_ languages: Set<SupportedLanguage>) -> [String] {
            GallerySnippetFilter.base(
                snippets: [swift, bash], selectedLanguages: languages,
                selectedCollectionID: nil, showUncategorizedOnly: false,
                selectedSearchCollections: [], showFavoritesOnly: false,
                lookup: [:], descendantIDs: [:]
            ).map(\.title)
        }
        XCTAssertEqual(base([.swift]), ["A"])
        XCTAssertEqual(base([.unknown]), ["B"])
        XCTAssertEqual(searchPool([swift, bash], languages: [.swift]).map(\.title), ["A"])
        XCTAssertEqual(searchPool([swift, bash], languages: [.unknown]).map(\.title), ["B"])
    }

    func test_storedLanguage_resolvesUnrecognizedToUnknown() {
        XCTAssertEqual(SupportedLanguage(stored: "Bash"), .unknown)
        XCTAssertEqual(SupportedLanguage(stored: " swift "), .swift)
        XCTAssertEqual(SupportedLanguage(stored: ""), .unknown)
    }
```

**Verify**: build-for-testing fails to compile because `SupportedLanguage(stored:)`
does not exist yet. That is the expected red state — continue.

### Step 2: Add the single resolver

In `LanguageDetector.swift`, directly after the existing `init?(rawValue:)`
(ends at line 33), add:

```swift
    /// The language a stored snippet belongs to. Free text that names no
    /// supported language (Shortcuts and imports can store anything) is
    /// `.unknown` — the same bucket the gallery groups it under — so filters
    /// and sections never disagree about where a snippet is.
    init(stored rawValue: String) {
        self = SupportedLanguage(rawValue: rawValue) ?? .unknown
    }
```

**Verify**: build command → `** BUILD SUCCEEDED **`.

### Step 3: Use it at the five call sites

- `ContentView.swift:453` → `let used = Set(snippets.map { SupportedLanguage(stored: $0.language) })`
- `ContentView.swift:1611` and `:1650` → replace each with:
  ```swift
            if !selectedLanguages.isEmpty, !selectedLanguages.contains(SupportedLanguage(stored: snippet.language)) { return false }
  ```
- `SnippetGalleryView.swift:860-862` → `SupportedLanguage(stored: snippet.language)` inside the grouping closure.
- `SnippetGalleryView.swift:1037-1039` → `result.insert(SupportedLanguage(stored: snippet.language))` (no `if let`).

**Verify**: `grep -n "SupportedLanguage(rawValue: snippet.language)\|SupportedLanguage(rawValue: \$0.language)" Sources/Snippets/Views/ContentView.swift Sources/Snippets/Views/SnippetGalleryView.swift`
→ only `ContentView.swift:471` remains (the palette, out of scope).
Focused tests command → `** TEST SUCCEEDED **`.

### Step 4: Full suite

**Verify**: full tests command → `** TEST SUCCEEDED **`.

## Test plan

- The two new tests in step 1 (filter behavior for both `base` and `searchPool`, and the resolver).
- Existing `SnippetFilterCacheTests` and `SnippetGalleryViewModelTests` must pass unchanged.

## Done criteria

- [ ] `grep -n "init(stored" Sources/Snippets/Services/LanguageDetector.swift` → 1 match
- [ ] The grep in step 3 shows only `ContentView.swift:471`
- [ ] Full tests → `** TEST SUCCEEDED **`
- [ ] `git status` shows no changes of yours outside the in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

- Lines 1611/1650 no longer contain the `let lang = SupportedLanguage(rawValue:` pattern.
- The full suite fails in a gallery or sidebar test after step 3. Report which
  assertion: some test may pin the old "unrecognized passes every filter"
  behavior. Do not edit that test without reporting it.
- `SupportedLanguage` already has an initializer with the label `stored:`.

## Maintenance notes

- Use `SupportedLanguage(stored:)` for any new code that reads `Snippet.language`.
  The failable `init?(rawValue:)` stays for parsing user or menu input, where
  "not a language" must stay distinguishable.
- A snippet stored as "Bash" now shows under the Unknown chip, and that chip
  appears when such snippets exist. If Bash support is added later, those
  snippets move to the new chip automatically, because the stored text was
  never rewritten.

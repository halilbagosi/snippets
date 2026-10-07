# Plan 020: Store the right language — detect at save time, and stop locking auto-detected languages on edit

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Precondition (run first)**: `git diff HEAD --stat -- Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift Sources/Snippets/Views/SnippetEditorView.swift`
> must print nothing. When this plan was written, the owner had uncommitted
> work in both files (shown in "Current state" below). If the command prints
> anything, STOP and ask the operator to commit that work first — otherwise
> your commit would sweep it in.
>
> **Drift check**: `git diff --stat 41ed0b44..HEAD -- Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift Tests/SnippetsTests/SnippetEditorViewModelTests.swift`
> The expected change is the owner's `resetManualLanguage` edit (3 added lines,
> shown below). Anything else in the excerpted regions is a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (the owner's in-progress editor work must be committed first — see Precondition)
- **Category**: bug
- **Planned at**: commit `41ed0b44` (+ uncommitted editor edits), 2026-10-07

## Why this matters

A snippet's language decides its syntax highlighting, its live-preview engine
and its file extension. Two editor bugs store the wrong one:

1. **Save beats the debounce.** The editor re-detects 300 ms after typing
   stops. Paste code into a new snippet and press Save within 300 ms, and the
   value saved is the one detected for the *empty* field: "Unknown". The
   pending detection is then cancelled when the editor closes, so the snippet
   stays Unknown, with no highlighting and no preview.
2. **Editing locks the language.** When an existing snippet is opened,
   its stored language is loaded as if the user had *hand-picked* it
   (`manualLanguage`), and auto-detection is skipped while a manual pick is
   set. So rewriting a snippet's code in another language keeps the old label,
   and a snippet saved as "Unknown" never gets detected again.

The model stores no "was this picked by hand" flag, and adding one is a schema
and archive-format change. This plan uses a rule that needs neither: a stored
label that **agrees** with the detector is treated as auto-detected (it is
indistinguishable from one), and a label that **disagrees** is treated as a
hand pick and kept. "Unknown" is never a hand pick.

## Current state

- `Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift` — `@Observable`
  view model; `detectedLanguage`, `manualLanguage`, `effectiveLanguage`
  (`manualLanguage ?? detectedLanguage`), `load(mode:)`, `save(...)`.
- `Sources/Snippets/Views/SnippetEditorView.swift:744-768` —
  `debounceLanguageDetection(for:)`: 300 ms debounce, detection runs off the
  main thread, and it returns early when `manualLanguage != nil`. **Do not edit
  this file.**
- `Sources/Snippets/Services/LanguageDetector.swift` —
  `LanguageDetector.detect(code:) -> SupportedLanguage`. It is pure,
  thread-safe, and takes about 11 ms on an 8 KB input (its scan is capped at
  8 KB).

`SnippetEditorViewModel.swift:66-81` (in `load(mode:)`):
```swift
        if case .edit(let snippet) = mode {
            title = snippet.title
            snippetDescription = snippet.snippetDescription
            code = snippet.code
            mediaItems = snippet.mediaItems
            selectedCollectionIDs = Set(snippet.collections.map(\.persistentModelID))
            dependencies = snippet.dependencies

            if let language = SupportedLanguage(rawValue: snippet.language) {
                manualLanguage = language
                detectedLanguage = language
            } else {
                detectedLanguage = LanguageDetector.detect(code: snippet.code)
            }
        } else {
```

`SnippetEditorViewModel.swift:101-106` (the owner's uncommitted edit at plan time):
```swift
    func resetManualLanguage() {
        manualLanguage = nil
        // Typing doesn't re-detect while a language is picked by hand, so
        // `detectedLanguage` may be stale by now.
        detectedLanguage = LanguageDetector.detect(code: code)
    }
```

`SnippetEditorViewModel.swift:154-160` (start of `save`):
```swift
    func save(
        mode: SnippetEditorMode,
        availableCollections: [SnippetCollection],
        modelContext: ModelContext,
        onSave: (Snippet) throws -> Void
    ) -> Bool {
        guard canSave else { return false }

        switch mode {
```
Both branches then read `effectiveLanguage.rawValue` (lines 167 and 195).

Test pattern: `Tests/SnippetsTests/SnippetEditorViewModelTests.swift:52-71`
(`test_save_editMode_persistsDependencyChanges`): an in-memory container,
`sut.load(mode: .edit(entry))`, then
`sut.save(mode:availableCollections:modelContext:onSave:)`. The existing
`test_load_whenEditingSnippet_populatesFormState` (line 93) stores
`language: "Python"` with code `print('hello')`. The detector returns Unknown
for that code, so under the new rule it stays a hand pick and the test still
passes. It must not be changed.

## Commands you will need

If `xcode-select -p` prints `/Library/Developer/CommandLineTools`, prefix
every command with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

| Purpose | Command | Expected on success |
|---|---|---|
| Build | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build` | `** BUILD SUCCEEDED **` |
| Focused tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/SnippetEditorViewModelTests` | `** TEST SUCCEEDED **` |
| Full tests | `xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test` | `** TEST SUCCEEDED **` |

## Scope

**In scope**:
- `Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift` — `load(mode:)` and the top of `save(...)` only
- `Tests/SnippetsTests/SnippetEditorViewModelTests.swift`

**Out of scope** (do NOT touch):
- `Sources/Snippets/Views/SnippetEditorView.swift` — the debounce is fine once
  save re-detects.
- `Sources/Snippets/Models/Snippet.swift` — no new stored property (no schema change).
- `Sources/Snippets/Services/LanguageDetector*.swift` — plan 023 improves the detector.
- Media handling in the same view model (`removeMediaItem`) has its own known
  issue, which is not part of this plan.

## Git workflow

- Branch: `advisor/020-editor-language-detection`
- Commit message: `Detect the language at save and keep auto-detected languages automatic on edit`
- `git add` the two in-scope paths only.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Failing tests

Add to `SnippetEditorViewModelTests.swift` (it already has `makeInMemoryContainer()`):

```swift
    private let swiftUICode = "import SwiftUI\nstruct A: View { var body: some View { Text(\"a\") } }"
    private let domScript = "document.querySelector('#a').addEventListener('click', () => console.log('x'))"

    func test_save_createMode_detectsLanguageEvenBeforeDebounceRuns() throws {
        let container = try makeInMemoryContainer()
        let sut = SnippetEditorViewModel()
        sut.load(mode: .create())
        sut.title = "View"
        sut.code = swiftUICode   // the view's debounce never ran
        var saved: Snippet?
        XCTAssertTrue(sut.save(mode: .create(), availableCollections: [],
                               modelContext: container.mainContext, onSave: { saved = $0 }))
        XCTAssertEqual(saved?.language, SupportedLanguage.swift.rawValue)
    }

    func test_load_editMode_labelMatchingDetector_staysAutomatic() throws {
        let snippet = Snippet(title: "V", language: "Swift", code: swiftUICode)
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))
        XCTAssertNil(sut.manualLanguage)
        XCTAssertEqual(sut.effectiveLanguage, .swift)
    }

    func test_load_editMode_storedUnknown_isNotAHandPick() throws {
        let snippet = Snippet(title: "V", language: "Unknown", code: "hello")
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))
        XCTAssertNil(sut.manualLanguage)
    }

    func test_save_editMode_redetectsWhenCodeChangesLanguage() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let snippet = Snippet(title: "V", language: "Swift", code: swiftUICode)
        context.insert(snippet)
        try context.save()

        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))
        sut.code = domScript
        XCTAssertTrue(sut.save(mode: .edit(snippet), availableCollections: [],
                               modelContext: context, onSave: { _ in }))
        XCTAssertEqual(snippet.language, SupportedLanguage.javascript.rawValue)
    }

    func test_save_editMode_keepsALabelThatDisagreesWithTheDetector() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        // The detector does not say Python for this code, so "Python" was a hand pick.
        let snippet = Snippet(title: "P", language: "Python", code: "print('hello')")
        context.insert(snippet)
        try context.save()

        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))
        sut.code = "print('hello, world')"
        XCTAssertTrue(sut.save(mode: .edit(snippet), availableCollections: [],
                               modelContext: context, onSave: { _ in }))
        XCTAssertEqual(snippet.language, "Python")
    }
```

**Verify**: focused tests command → `** TEST FAILED **`. The new tests
`..._detectsLanguageEvenBeforeDebounceRuns`, `..._labelMatchingDetector_staysAutomatic`,
`..._storedUnknown_isNotAHandPick` and `..._redetectsWhenCodeChangesLanguage` fail;
`..._keepsALabelThatDisagreesWithTheDetector` already passes.

### Step 2: Load — only a disagreeing label is a hand pick

Replace the `if let language = ... else { ... }` block in `load(mode:)` with:

```swift
            // The model doesn't record whether a language was picked by hand.
            // A stored label the detector agrees with is indistinguishable
            // from an auto-detected one, so keep detecting; only a label that
            // disagrees can have been a deliberate choice. "Unknown" is never
            // a choice worth locking in.
            let detected = LanguageDetector.detect(code: snippet.code)
            detectedLanguage = detected
            if let stored = SupportedLanguage(rawValue: snippet.language),
               stored != .unknown, stored != detected {
                manualLanguage = stored
            }
```

**Verify**: focused tests command → the two `load_editMode` tests now pass.

### Step 3: Save — detect synchronously when automatic

At the top of `save(...)`, directly after `guard canSave else { return false }`, add:

```swift
        // Detection is debounced while typing, so a save right after a paste
        // would otherwise store the language of the code as it was before.
        if manualLanguage == nil {
            detectedLanguage = LanguageDetector.detect(code: code)
        }
```

**Verify**: focused tests command → `** TEST SUCCEEDED **` (all five new
tests and the existing ones).

### Step 4: Full suite

**Verify**: full tests command → `** TEST SUCCEEDED **`.

## Test plan

- The five tests in step 1 cover save-before-debounce, an agreeing label staying
  automatic, "Unknown" not being locked, re-detection on save after a language
  change, and a disagreeing label being preserved.
- All existing `SnippetEditorViewModelTests` pass unchanged.

## Done criteria

- [ ] `grep -n "manualLanguage = language" Sources/Snippets/Features/Editor/SnippetEditorViewModel.swift` returns nothing (the old unconditional lock is gone)
- [ ] Focused and full tests → `** TEST SUCCEEDED **`
- [ ] `git status` shows changes of yours only in the two in-scope files
- [ ] `plans/README.md` status row updated

## STOP conditions

- The Precondition command prints anything.
- `load(mode:)` or `save(...)` no longer match the excerpts.
- `test_load_whenEditingSnippet_populatesFormState` fails after step 2. That
  means the detector now returns Python for `print('hello')` and the test
  needs a different fixture. Report it; don't edit the test silently.
- A test in another class fails, for example in the UI layer, because it
  relied on edit mode always setting `manualLanguage`.

## Maintenance notes

- Trade-off: a user who hand-picked a language the detector *also* returns
  will see auto-detect on the next edit. Their label only changes if they
  then change the code enough for the detector to say something else, which
  is the case where re-detection is wanted anyway.
- Plan 023 changes detector results. Snippets whose stored label stops
  matching the detector will load as hand picks and keep their label. That
  is safe.
- If a persisted "language source" flag is ever added (schema plus archive
  format), it replaces the comparison in step 2.

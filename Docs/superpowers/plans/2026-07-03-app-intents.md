# App Intents Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expose Snippets' data and core actions to the system via App Intents so snippets and collections are usable from Shortcuts, Siri, and Spotlight.

**Architecture:** Add `AppEntity` types (`SnippetEntity`, `SnippetCollectionEntity`) backed by the app's SwiftData store through a single shared `ModelContainer`, expose five focused `AppIntent`s, register `AppShortcuts`, and bridge an "open snippet" intent into `ContentView` via an `@Observable` navigator. A stable `UUID?` is added to both models for entity identity.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, AppIntents, macOS 26+, XCTest.

## Global Constraints

- Platform floor: macOS 26 (`platforms: [.macOS(.v26)]`). App is AppKit/macOS-only.
- Build/test toolchain: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` before any `swift` command (Command Line Tools lack the SwiftData macros).
- Unit tests run via `swift test` only; full app bundle + App Intents metadata generation happens via the Xcode `.swiftpm/xcode` workspace (not required for these tasks to pass).
- Test conventions: XCTest, `@testable import Snippets`, `@MainActor final class …: XCTestCase`. Test files live in `Tests/SnippetsTests/`.
- All intents and entity queries run on `@MainActor` and use `SnippetsData.sharedModelContainer.mainContext`.
- Entity queries and lookups exclude soft-deleted rows (`deletedAt != nil`).
- Commit after each task.
- Swift 6 strict concurrency (tools-version 6.2): every **stored** `static var` type property used to satisfy an `AppEntity`/`AppIntent`/`EntityQuery` conformance — `title`, `description`, `openAppWhenRun`, `typeDisplayRepresentation`, `defaultQuery` — MUST be declared `static let` (a `let` satisfies the protocol's get-only requirement; a mutable `static var` is rejected as nonisolated global shared mutable state). **Computed** statics that return a value each call (`parameterSummary`, `appShortcuts`) stay as `static var`. Established by Task 4. Any code block below still written with `static var` for a stored conformance property should be transcribed as `static let`.

---

### Task 1: Add stable `uuid` to models + `UUIDBackfill`

**Files:**
- Modify: `Sources/Snippets/Models/Snippet.swift`
- Modify: `Sources/Snippets/Models/Collection.swift`
- Create: `Sources/Snippets/Intents/UUIDBackfill.swift`
- Test: `Tests/SnippetsTests/UUIDBackfillTests.swift`

**Interfaces:**
- Produces:
  - `Snippet.uuid: UUID?` (stored), init gains `uuid: UUID? = UUID()`.
  - `SnippetCollection.uuid: UUID?` (stored), init gains `uuid: UUID? = UUID()`.
  - `enum UUIDBackfill { static func assign(snippets: [Snippet], collections: [SnippetCollection]) -> Int }` — assigns a UUID to every model whose `uuid == nil`, returns how many were assigned, does **not** save.

- [ ] **Step 1: Write the failing test**

Create `Tests/SnippetsTests/UUIDBackfillTests.swift`:

```swift
import XCTest
@testable import Snippets

@MainActor
final class UUIDBackfillTests: XCTestCase {
    func test_newSnippet_hasUUIDByDefault() {
        XCTAssertNotNil(Snippet(title: "x").uuid)
    }

    func test_newCollection_hasUUIDByDefault() {
        XCTAssertNotNil(SnippetCollection(name: "x").uuid)
    }

    func test_assign_fillsOnlyNilUUIDs_andReturnsCount() {
        let keep = Snippet(title: "keep")
        let keptUUID = keep.uuid
        let missing = Snippet(title: "missing")
        missing.uuid = nil
        let collection = SnippetCollection(name: "c")
        collection.uuid = nil

        let assigned = UUIDBackfill.assign(snippets: [keep, missing], collections: [collection])

        XCTAssertEqual(assigned, 2)
        XCTAssertEqual(keep.uuid, keptUUID)
        XCTAssertNotNil(missing.uuid)
        XCTAssertNotNil(collection.uuid)
    }

    func test_assign_whenNothingMissing_returnsZero() {
        let assigned = UUIDBackfill.assign(snippets: [Snippet(title: "a")], collections: [])
        XCTAssertEqual(assigned, 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test --filter UUIDBackfillTests`
Expected: FAIL — `uuid` is not a member / `UUIDBackfill` not found.

- [ ] **Step 3: Add `uuid` to `Snippet`**

In `Sources/Snippets/Models/Snippet.swift`, add the stored property after `var deletedAt: Date?`:

```swift
    var uuid: UUID?
```

Add `uuid: UUID? = UUID()` as the first parameter of `init(...)` and assign it. The init signature becomes:

```swift
    init(
        uuid: UUID? = UUID(),
        title: String = "",
        snippetDescription: String = "",
        language: String = "Unknown",
        code: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        copyCount: Int = 0,
        isFavorite: Bool = false,
        deletedAt: Date? = nil,
        mediaItems: [MediaItem] = [],
        collections: [SnippetCollection] = []
    ) {
        self.uuid = uuid
        self.title = title
```

(leave the remaining assignments unchanged.)

- [ ] **Step 4: Add `uuid` to `SnippetCollection`**

In `Sources/Snippets/Models/Collection.swift`, add after `var isFavorite: Bool = false`:

```swift
    var uuid: UUID?
```

Add `uuid: UUID? = UUID()` as the first parameter of `init(...)` and assign it first:

```swift
    init(
        uuid: UUID? = UUID(),
        name: String,
        colorHex: String = SnippetCollection.defaultColorHex,
        colorHexDark: String? = nil,
        iconName: String = SnippetCollection.defaultIconName,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil,
        isFavorite: Bool = false,
        snippets: [Snippet] = [],
        parent: SnippetCollection? = nil,
        children: [SnippetCollection] = []
    ) {
        self.uuid = uuid
        self.name = name
```

(leave the remaining assignments unchanged.)

- [ ] **Step 5: Create `UUIDBackfill`**

Create `Sources/Snippets/Intents/UUIDBackfill.swift`:

```swift
import Foundation

/// Assigns stable UUIDs to any models that predate the `uuid` property (existing
/// rows migrate to `nil`). Pure: mutates the passed models but never saves — the
/// caller owns persistence.
enum UUIDBackfill {
    @discardableResult
    static func assign(snippets: [Snippet], collections: [SnippetCollection]) -> Int {
        var assigned = 0
        for snippet in snippets where snippet.uuid == nil {
            snippet.uuid = UUID()
            assigned += 1
        }
        for collection in collections where collection.uuid == nil {
            collection.uuid = UUID()
            assigned += 1
        }
        return assigned
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test --filter UUIDBackfillTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add Sources/Snippets/Models/Snippet.swift Sources/Snippets/Models/Collection.swift Sources/Snippets/Intents/UUIDBackfill.swift Tests/SnippetsTests/UUIDBackfillTests.swift
git commit -m "Add stable uuid to Snippet/SnippetCollection with backfill"
```

---

### Task 2: Extract shared `ModelContainer` + wire app launch backfill

**Files:**
- Create: `Sources/Snippets/Intents/SnippetsData.swift`
- Modify: `Sources/Snippets/SnippetsApp.swift`

**Interfaces:**
- Consumes: `UUIDBackfill.assign(snippets:collections:)` (Task 1).
- Produces: `enum SnippetsData { @MainActor static let sharedModelContainer: ModelContainer }`.

- [ ] **Step 1: Create `SnippetsData`**

Create `Sources/Snippets/Intents/SnippetsData.swift` (move the container-building logic out of `SnippetsApp`):

```swift
import Foundation
import SwiftData

/// The single SwiftData container shared by the SwiftUI app and every App Intent.
/// Intents may run while the app is backgrounded, so both paths must open the
/// same store — two containers on one URL would conflict.
enum SnippetsData {
    @MainActor
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([Snippet.self, MediaItem.self, SnippetCollection.self])
        let appSupport = URL.applicationSupportDirectory
        let storeURL = appSupport.appending(path: "Snippets.store")

        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: storeURL)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unresolved error loading SwiftData container: \(error.localizedDescription)")
        }
    }()
}
```

- [ ] **Step 2: Point `SnippetsApp` at the shared container**

In `Sources/Snippets/SnippetsApp.swift`, delete the `private var sharedModelContainer: ModelContainer = { … }()` computed block (lines defining it inside `struct SnippetsApp`). Replace the `.modelContainer(sharedModelContainer)` call with:

```swift
        .modelContainer(SnippetsData.sharedModelContainer)
```

- [ ] **Step 3: Add a launch backfill**

In `Sources/Snippets/SnippetsApp.swift`, add a one-time UUID backfill so pre-existing rows gain stable ids. Add this modifier to `ContentView()` inside the `WindowGroup` (after the existing `.environment(...)` calls):

```swift
                .task { SnippetsApp.backfillUUIDs() }
```

And add this static helper inside `struct SnippetsApp`:

```swift
    @MainActor
    static func backfillUUIDs() {
        let context = SnippetsData.sharedModelContainer.mainContext
        let snippets = (try? context.fetch(FetchDescriptor<Snippet>())) ?? []
        let collections = (try? context.fetch(FetchDescriptor<SnippetCollection>())) ?? []
        if UUIDBackfill.assign(snippets: snippets, collections: collections) > 0 {
            try? context.save()
        }
    }
```

Ensure `import SwiftData` is present at the top of the file (it already is).

- [ ] **Step 4: Verify the project still compiles and existing tests pass**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS — module compiles, all existing tests green.

- [ ] **Step 5: Commit**

```bash
git add Sources/Snippets/Intents/SnippetsData.swift Sources/Snippets/SnippetsApp.swift
git commit -m "Extract shared ModelContainer and backfill UUIDs on launch"
```

---

### Task 3: `SnippetQueryFilter` (pure filtering logic)

**Files:**
- Create: `Sources/Snippets/Intents/SnippetQueryFilter.swift`
- Test: `Tests/SnippetsTests/SnippetQueryFilterTests.swift`

**Interfaces:**
- Produces:
  - `struct SnippetQueryFilter.Candidate { let title, description, language: String; let isFavorite: Bool; let collectionUUIDs: Set<UUID> }`
  - `static func matches(title:description:language:query:) -> Bool`
  - `static func filter<T>(_ items: [T], query: String?, collectionUUID: UUID?, favoritesOnly: Bool, projection: (T) -> Candidate) -> [T]`

- [ ] **Step 1: Write the failing test**

Create `Tests/SnippetsTests/SnippetQueryFilterTests.swift`:

```swift
import XCTest
@testable import Snippets

final class SnippetQueryFilterTests: XCTestCase {
    private func candidate(
        title: String = "",
        description: String = "",
        language: String = "Swift",
        isFavorite: Bool = false,
        collectionUUIDs: Set<UUID> = []
    ) -> SnippetQueryFilter.Candidate {
        .init(title: title, description: description, language: language,
              isFavorite: isFavorite, collectionUUIDs: collectionUUIDs)
    }

    private func filter(
        _ items: [SnippetQueryFilter.Candidate],
        query: String? = nil,
        collectionUUID: UUID? = nil,
        favoritesOnly: Bool = false
    ) -> [SnippetQueryFilter.Candidate] {
        SnippetQueryFilter.filter(items, query: query, collectionUUID: collectionUUID,
                                  favoritesOnly: favoritesOnly, projection: { $0 })
    }

    func test_matches_isCaseInsensitiveAcrossFields() {
        XCTAssertTrue(SnippetQueryFilter.matches(title: "Debounce", description: "", language: "Swift", query: "debo"))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "", description: "A JSON helper", language: "Swift", query: "json"))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "", description: "", language: "Python", query: "PYTH"))
        XCTAssertFalse(SnippetQueryFilter.matches(title: "abc", description: "def", language: "Swift", query: "zzz"))
    }

    func test_matches_emptyOrWhitespaceQuery_returnsTrue() {
        XCTAssertTrue(SnippetQueryFilter.matches(title: "a", description: "b", language: "c", query: ""))
        XCTAssertTrue(SnippetQueryFilter.matches(title: "a", description: "b", language: "c", query: "   "))
    }

    func test_filter_nilQuery_returnsAll() {
        let items = [candidate(title: "a"), candidate(title: "b")]
        XCTAssertEqual(filter(items).count, 2)
    }

    func test_filter_query_matchesTitle() {
        let items = [candidate(title: "Debounce"), candidate(title: "Throttle")]
        XCTAssertEqual(filter(items, query: "debo").map(\.title), ["Debounce"])
    }

    func test_filter_favoritesOnly() {
        let items = [candidate(title: "a", isFavorite: true), candidate(title: "b", isFavorite: false)]
        XCTAssertEqual(filter(items, favoritesOnly: true).map(\.title), ["a"])
    }

    func test_filter_byCollectionUUID() {
        let target = UUID()
        let items = [
            candidate(title: "in", collectionUUIDs: [target]),
            candidate(title: "out", collectionUUIDs: [UUID()])
        ]
        XCTAssertEqual(filter(items, collectionUUID: target).map(\.title), ["in"])
    }

    func test_filter_combinesCriteria() {
        let target = UUID()
        let items = [
            candidate(title: "keep", isFavorite: true, collectionUUIDs: [target]),
            candidate(title: "keepNotFav", isFavorite: false, collectionUUIDs: [target]),
            candidate(title: "other", isFavorite: true, collectionUUIDs: [target])
        ]
        let result = filter(items, query: "keep", collectionUUID: target, favoritesOnly: true)
        XCTAssertEqual(result.map(\.title), ["keep"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test --filter SnippetQueryFilterTests`
Expected: FAIL — `SnippetQueryFilter` not found.

- [ ] **Step 3: Implement `SnippetQueryFilter`**

Create `Sources/Snippets/Intents/SnippetQueryFilter.swift`:

```swift
import Foundation

/// Pure, dependency-free filtering shared by `SnippetEntityQuery` and
/// `FindSnippetsIntent`. Operates over lightweight value projections so it needs
/// no `ModelContainer` and is fully unit-testable.
enum SnippetQueryFilter {
    struct Candidate {
        let title: String
        let description: String
        let language: String
        let isFavorite: Bool
        let collectionUUIDs: Set<UUID>
    }

    /// Case-insensitive substring match across title, description, and language.
    /// An empty/whitespace query matches everything.
    static func matches(title: String, description: String, language: String, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        return title.range(of: needle, options: .caseInsensitive) != nil
            || description.range(of: needle, options: .caseInsensitive) != nil
            || language.range(of: needle, options: .caseInsensitive) != nil
    }

    static func filter<T>(
        _ items: [T],
        query: String?,
        collectionUUID: UUID?,
        favoritesOnly: Bool,
        projection: (T) -> Candidate
    ) -> [T] {
        items.filter { item in
            let candidate = projection(item)
            if favoritesOnly && !candidate.isFavorite { return false }
            if let collectionUUID, !candidate.collectionUUIDs.contains(collectionUUID) { return false }
            if let query, !matches(title: candidate.title, description: candidate.description,
                                   language: candidate.language, query: query) {
                return false
            }
            return true
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test --filter SnippetQueryFilterTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Snippets/Intents/SnippetQueryFilter.swift Tests/SnippetsTests/SnippetQueryFilterTests.swift
git commit -m "Add pure SnippetQueryFilter for entity/find filtering"
```

---

### Task 4: `SnippetCollectionEntity` + query

**Files:**
- Create: `Sources/Snippets/Intents/Entities/SnippetCollectionEntity.swift`

**Interfaces:**
- Consumes: `SnippetsData.sharedModelContainer` (Task 2), `UUIDBackfill.assign` (Task 1).
- Produces:
  - `struct SnippetCollectionEntity: AppEntity { let id: UUID; @Property var name: String; init(id:name:); init(_ collection: SnippetCollection) }`
  - `struct SnippetCollectionEntityQuery: EntityQuery` with `entities(for:)` and `suggestedEntities()`.

- [ ] **Step 1: Implement the entity + query**

Create `Sources/Snippets/Intents/Entities/SnippetCollectionEntity.swift`:

```swift
import AppIntents
import SwiftData

struct SnippetCollectionEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Collection"
    static var defaultQuery = SnippetCollectionEntityQuery()

    let id: UUID
    @Property(title: "Name") var name: String

    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    init(_ collection: SnippetCollection) {
        self.init(id: collection.uuid ?? UUID(), name: collection.name)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SnippetCollectionEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetCollectionEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        let all = try fetchLive(context)
        let wanted = Set(identifiers)
        return all
            .filter { $0.uuid.map(wanted.contains) ?? false }
            .map(SnippetCollectionEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetCollectionEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        return try fetchLive(context).map(SnippetCollectionEntity.init)
    }

    /// Fetches non-deleted collections and guarantees each has a stable `uuid`.
    @MainActor
    private func fetchLive(_ context: ModelContext) throws -> [SnippetCollection] {
        var descriptor = FetchDescriptor<SnippetCollection>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 100
        let collections = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: [], collections: collections) > 0 {
            try? context.save()
        }
        return collections
    }
}
```

- [ ] **Step 2: Verify it compiles (and existing tests still pass)**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS — module compiles with the new entity, all tests green.

- [ ] **Step 3: Commit**

```bash
git add Sources/Snippets/Intents/Entities/SnippetCollectionEntity.swift
git commit -m "Add SnippetCollectionEntity and its query"
```

---

### Task 5: `SnippetEntity` + query

**Files:**
- Create: `Sources/Snippets/Intents/Entities/SnippetEntity.swift`

**Interfaces:**
- Consumes: `SnippetsData.sharedModelContainer` (Task 2), `UUIDBackfill.assign` (Task 1), `SnippetQueryFilter.matches` (Task 3).
- Produces:
  - `struct SnippetEntity: AppEntity { let id: UUID; @Property var title, language, code: String; @Property var isFavorite: Bool; init(id:title:language:code:isFavorite:); init(_ snippet: Snippet) }`
  - `struct SnippetEntityQuery: EntityQuery, EntityStringQuery` with `entities(for:)`, `suggestedEntities()`, `entities(matching:)`.

- [ ] **Step 1: Implement the entity + query**

Create `Sources/Snippets/Intents/Entities/SnippetEntity.swift`:

```swift
import AppIntents
import SwiftData

struct SnippetEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Snippet"
    static var defaultQuery = SnippetEntityQuery()

    let id: UUID
    @Property(title: "Title") var title: String
    @Property(title: "Language") var language: String
    @Property(title: "Code") var code: String
    @Property(title: "Favorite") var isFavorite: Bool

    init(id: UUID, title: String, language: String, code: String, isFavorite: Bool) {
        self.id = id
        self.title = title
        self.language = language
        self.code = code
        self.isFavorite = isFavorite
    }

    init(_ snippet: Snippet) {
        self.init(
            id: snippet.uuid ?? UUID(),
            title: snippet.title,
            language: snippet.language,
            // Truncate for display/transport; the full code is copied by CopySnippetIntent.
            code: String(snippet.code.prefix(4000)),
            isFavorite: snippet.isFavorite
        )
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title.isEmpty ? "Untitled" : title)",
            subtitle: "\(language)"
        )
    }
}

struct SnippetEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SnippetEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        let wanted = Set(identifiers)
        return try fetchLive(context)
            .filter { $0.uuid.map(wanted.contains) ?? false }
            .map(SnippetEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SnippetEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        return try fetchLive(context, limit: 10).map(SnippetEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SnippetEntity] {
        let context = SnippetsData.sharedModelContainer.mainContext
        return try fetchLive(context)
            .filter {
                SnippetQueryFilter.matches(
                    title: $0.title, description: $0.snippetDescription,
                    language: $0.language, query: string
                )
            }
            .map(SnippetEntity.init)
    }

    /// Fetches non-deleted snippets (newest first) and guarantees each has a
    /// stable `uuid`.
    @MainActor
    private func fetchLive(_ context: ModelContext, limit: Int? = nil) throws -> [Snippet] {
        var descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let limit { descriptor.fetchLimit = limit }
        let snippets = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: snippets, collections: []) > 0 {
            try? context.save()
        }
        return snippets
    }
}
```

- [ ] **Step 2: Verify it compiles (and existing tests still pass)**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/Snippets/Intents/Entities/SnippetEntity.swift
git commit -m "Add SnippetEntity with string-searchable query"
```

---

### Task 6: `AppIntentNavigator` + `OpenSnippetIntent` + ContentView hook

**Files:**
- Create: `Sources/Snippets/Intents/AppIntentNavigator.swift`
- Create: `Sources/Snippets/Intents/Actions/OpenSnippetIntent.swift`
- Modify: `Sources/Snippets/SnippetsApp.swift`
- Modify: `Sources/Snippets/Views/ContentView.swift`

**Interfaces:**
- Consumes: `SnippetEntity` (Task 5).
- Produces:
  - `@MainActor @Observable final class AppIntentNavigator { static let shared: AppIntentNavigator; var pendingOpenSnippetUUID: UUID? }`
  - `struct OpenSnippetIntent: AppIntent` (`openAppWhenRun = true`, param `snippet: SnippetEntity`).

- [ ] **Step 1: Create the navigator**

Create `Sources/Snippets/Intents/AppIntentNavigator.swift`:

```swift
import Observation

/// One-way bridge from `OpenSnippetIntent` into the running UI. The intent sets
/// `pendingOpenSnippetUUID`; `ContentView` observes it, opens the snippet, and
/// clears it back to `nil`.
@MainActor
@Observable
final class AppIntentNavigator {
    static let shared = AppIntentNavigator()
    var pendingOpenSnippetUUID: UUID?
    private init() {}
}
```

- [ ] **Step 2: Create `OpenSnippetIntent`**

Create `Sources/Snippets/Intents/Actions/OpenSnippetIntent.swift`:

```swift
import AppIntents

struct OpenSnippetIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Snippet"
    static var description = IntentDescription("Opens a snippet in Snippets.")
    static var openAppWhenRun = true

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentNavigator.shared.pendingOpenSnippetUUID = snippet.id
        return .result()
    }
}
```

- [ ] **Step 3: Inject the navigator into the environment**

In `Sources/Snippets/SnippetsApp.swift`, add the navigator to the `WindowGroup`'s `ContentView` alongside the existing `.environment(...)` calls:

```swift
                .environment(AppIntentNavigator.shared)
```

- [ ] **Step 4: Observe the navigator in `ContentView`**

In `Sources/Snippets/Views/ContentView.swift`, add the environment property near the other `@Environment` declarations at the top of `struct ContentView`:

```swift
    @Environment(AppIntentNavigator.self) private var navigator
```

Then add this `.onChange` to the `NavigationSplitView` in `body`, immediately after the existing `.onChange(of: sidebarSelectionContext) { … }` modifier:

```swift
        .onChange(of: navigator.pendingOpenSnippetUUID) { _, newValue in
            guard let uuid = newValue else { return }
            if let match = snippets.first(where: { $0.uuid == uuid }) {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    searchText = ""
                    selectedCollectionID = nil
                    sidebarSelectionContext = .allSnippets
                    selectedSnippetID = match.persistentModelID
                }
            }
            navigator.pendingOpenSnippetUUID = nil
        }
```

- [ ] **Step 5: Verify it compiles (and existing tests still pass)**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/Snippets/Intents/AppIntentNavigator.swift Sources/Snippets/Intents/Actions/OpenSnippetIntent.swift Sources/Snippets/SnippetsApp.swift Sources/Snippets/Views/ContentView.swift
git commit -m "Add OpenSnippetIntent with navigator bridge into ContentView"
```

---

### Task 7: Intent support + `CopySnippetIntent` + `ToggleFavoriteSnippetIntent`

**Files:**
- Create: `Sources/Snippets/Intents/SnippetStore.swift`
- Create: `Sources/Snippets/Intents/Actions/CopySnippetIntent.swift`
- Create: `Sources/Snippets/Intents/Actions/ToggleFavoriteSnippetIntent.swift`

**Interfaces:**
- Consumes: `SnippetsData.sharedModelContainer` (Task 2), `SnippetEntity` (Task 5), `Clipboard.copy(_:)` (existing `Sources/Snippets/Services/Clipboard.swift`).
- Produces:
  - `enum SnippetIntentError: Error, CustomLocalizedStringResourceConvertible { case snippetNotFound, collectionNotFound }`
  - `@MainActor enum SnippetStore { static func snippet(uuid:in:) throws -> Snippet?; static func collection(uuid:in:) throws -> SnippetCollection? }`
  - `struct CopySnippetIntent: AppIntent`, `struct ToggleFavoriteSnippetIntent: AppIntent`.

- [ ] **Step 1: Create the lookup + error support**

Create `Sources/Snippets/Intents/SnippetStore.swift`:

```swift
import AppIntents
import SwiftData

enum SnippetIntentError: Error, CustomLocalizedStringResourceConvertible {
    case snippetNotFound
    case collectionNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .snippetNotFound: "That snippet no longer exists."
        case .collectionNotFound: "That collection no longer exists."
        }
    }
}

/// Shared, `uuid`-keyed lookups over the live (non-deleted) store for intents.
@MainActor
enum SnippetStore {
    static func snippet(uuid: UUID, in context: ModelContext) throws -> Snippet? {
        let all = try context.fetch(
            FetchDescriptor<Snippet>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return all.first { $0.uuid == uuid }
    }

    static func collection(uuid: UUID, in context: ModelContext) throws -> SnippetCollection? {
        let all = try context.fetch(
            FetchDescriptor<SnippetCollection>(predicate: #Predicate { $0.deletedAt == nil })
        )
        return all.first { $0.uuid == uuid }
    }
}
```

- [ ] **Step 2: Create `CopySnippetIntent`**

Create `Sources/Snippets/Intents/Actions/CopySnippetIntent.swift`:

```swift
import AppIntents

struct CopySnippetIntent: AppIntent {
    static var title: LocalizedStringResource = "Copy Snippet Code"
    static var description = IntentDescription("Copies a snippet's code to the clipboard.")
    static var openAppWhenRun = false

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Copy code from \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = SnippetsData.sharedModelContainer.mainContext
        guard let model = try SnippetStore.snippet(uuid: snippet.id, in: context) else {
            throw SnippetIntentError.snippetNotFound
        }
        Clipboard.copy(model.code)
        // Mirror in-app copy: bump copyCount (feeds "Frequently Used"); leave
        // updatedAt untouched so the gallery order doesn't shift.
        model.copyCount += 1
        try? context.save()

        let name = model.title.isEmpty ? "Untitled" : model.title
        return .result(value: model.code, dialog: "Copied \(name).")
    }
}
```

- [ ] **Step 3: Create `ToggleFavoriteSnippetIntent`**

Create `Sources/Snippets/Intents/Actions/ToggleFavoriteSnippetIntent.swift`:

```swift
import AppIntents

struct ToggleFavoriteSnippetIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Snippet Favorite"
    static var description = IntentDescription("Adds or removes a snippet from favorites.")
    static var openAppWhenRun = false

    @Parameter(title: "Snippet")
    var snippet: SnippetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle favorite for \(\.$snippet)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let context = SnippetsData.sharedModelContainer.mainContext
        guard let model = try SnippetStore.snippet(uuid: snippet.id, in: context) else {
            throw SnippetIntentError.snippetNotFound
        }
        model.isFavorite.toggle()
        model.updatedAt = .now
        try? context.save()

        let name = model.title.isEmpty ? "Untitled" : model.title
        let dialog: IntentDialog = model.isFavorite
            ? "Added \(name) to favorites."
            : "Removed \(name) from favorites."
        return .result(value: model.isFavorite, dialog: dialog)
    }
}
```

- [ ] **Step 4: Verify it compiles (and existing tests still pass)**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Snippets/Intents/SnippetStore.swift Sources/Snippets/Intents/Actions/CopySnippetIntent.swift Sources/Snippets/Intents/Actions/ToggleFavoriteSnippetIntent.swift
git commit -m "Add Copy and Toggle-Favorite snippet intents"
```

---

### Task 8: `CreateSnippetIntent` + `FindSnippetsIntent`

**Files:**
- Create: `Sources/Snippets/Intents/Actions/CreateSnippetIntent.swift`
- Create: `Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift`

**Interfaces:**
- Consumes: `SnippetsData.sharedModelContainer` (Task 2), `SnippetEntity`/`SnippetEntityQuery` (Task 5), `SnippetCollectionEntity` (Task 4), `SnippetStore` + `SnippetIntentError` (Task 7), `SnippetQueryFilter` (Task 3), `UUIDBackfill` (Task 1).
- Produces: `struct CreateSnippetIntent: AppIntent`, `struct FindSnippetsIntent: AppIntent`.

- [ ] **Step 1: Create `CreateSnippetIntent`**

Create `Sources/Snippets/Intents/Actions/CreateSnippetIntent.swift`:

```swift
import AppIntents
import SwiftData

struct CreateSnippetIntent: AppIntent {
    static var title: LocalizedStringResource = "Create Snippet"
    static var description = IntentDescription("Creates a new snippet in Snippets.")
    static var openAppWhenRun = false

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Code")
    var code: String

    @Parameter(title: "Language", default: "Unknown")
    var language: String

    @Parameter(title: "Collection")
    var collection: SnippetCollectionEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Create snippet \(\.$title)") {
            \.$code
            \.$language
            \.$collection
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<SnippetEntity> & ProvidesDialog {
        let context = SnippetsData.sharedModelContainer.mainContext

        let snippet = Snippet(
            title: title,
            language: language,
            code: code
        )
        context.insert(snippet)

        if let collection {
            guard let target = try SnippetStore.collection(uuid: collection.id, in: context) else {
                throw SnippetIntentError.collectionNotFound
            }
            snippet.collections.append(target)
            target.updatedAt = .now
        }
        try? context.save()

        let name = title.isEmpty ? "Untitled" : title
        return .result(value: SnippetEntity(snippet), dialog: "Created \(name).")
    }
}
```

- [ ] **Step 2: Create `FindSnippetsIntent`**

Create `Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift`:

```swift
import AppIntents
import SwiftData

struct FindSnippetsIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Snippets"
    static var description = IntentDescription("Finds snippets by text, collection, or favorites.")
    static var openAppWhenRun = false

    @Parameter(title: "Search Text")
    var searchText: String?

    @Parameter(title: "Collection")
    var collection: SnippetCollectionEntity?

    @Parameter(title: "Favorites Only", default: false)
    var favoritesOnly: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Find snippets matching \(\.$searchText)") {
            \.$collection
            \.$favoritesOnly
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[SnippetEntity]> {
        let context = SnippetsData.sharedModelContainer.mainContext
        var descriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        let snippets = try context.fetch(descriptor)
        if UUIDBackfill.assign(snippets: snippets, collections: []) > 0 {
            try? context.save()
        }

        let matched = SnippetQueryFilter.filter(
            snippets,
            query: searchText,
            collectionUUID: collection?.id,
            favoritesOnly: favoritesOnly,
            projection: { snippet in
                SnippetQueryFilter.Candidate(
                    title: snippet.title,
                    description: snippet.snippetDescription,
                    language: snippet.language,
                    isFavorite: snippet.isFavorite,
                    collectionUUIDs: Set(snippet.collections.compactMap { $0.isDeleted ? nil : $0.uuid })
                )
            }
        )
        return .result(value: matched.map(SnippetEntity.init))
    }
}
```

- [ ] **Step 3: Verify it compiles (and existing tests still pass)**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/Snippets/Intents/Actions/CreateSnippetIntent.swift Sources/Snippets/Intents/Actions/FindSnippetsIntent.swift
git commit -m "Add Create and Find snippet intents"
```

---

### Task 9: `SnippetsAppShortcuts` provider

**Files:**
- Create: `Sources/Snippets/Intents/SnippetsAppShortcuts.swift`

**Interfaces:**
- Consumes: `CreateSnippetIntent` (Task 8), `FindSnippetsIntent` (Task 8), `CopySnippetIntent` (Task 7).
- Produces: `struct SnippetsAppShortcuts: AppShortcutsProvider`.

- [ ] **Step 1: Create the provider**

Create `Sources/Snippets/Intents/SnippetsAppShortcuts.swift`:

```swift
import AppIntents

/// Siri / Spotlight phrases for the app's primary intents. Phrases must include
/// `\(.applicationName)`. Discovery of these requires the App Intents metadata
/// that Xcode generates at build time (not produced by a plain `swift build`).
struct SnippetsAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateSnippetIntent(),
            phrases: [
                "Create a snippet in \(.applicationName)",
                "Add a snippet to \(.applicationName)"
            ],
            shortTitle: "Create Snippet",
            systemImageName: "plus.square"
        )
        AppShortcut(
            intent: FindSnippetsIntent(),
            phrases: [
                "Find snippets in \(.applicationName)",
                "Search \(.applicationName)"
            ],
            shortTitle: "Find Snippets",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: CopySnippetIntent(),
            phrases: [
                "Copy a snippet from \(.applicationName)"
            ],
            shortTitle: "Copy Snippet",
            systemImageName: "doc.on.doc"
        )
    }
}
```

- [ ] **Step 2: Verify it compiles (and existing tests still pass)**

Run: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test`
Expected: PASS.

- [ ] **Step 3: Update graphify graph**

Run: `graphify update .`
Expected: graph refreshes with the new files (AST-only, no API cost).

- [ ] **Step 4: Commit**

```bash
git add Sources/Snippets/Intents/SnippetsAppShortcuts.swift graphify-out
git commit -m "Register App Shortcuts for Snippets intents"
```

---

## Final verification

- [ ] Run full test suite: `export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer && swift test` — all green.
- [ ] Open the project in Xcode via the `.swiftpm/xcode` workspace and build (⌘B) to confirm the App Intents metadata generates without error.
- [ ] (Manual) In the macOS Shortcuts app, confirm "Snippets" actions appear (Copy Snippet Code, Create Snippet, Open Snippet, Find Snippets, Toggle Snippet Favorite) and that a snippet/collection picker populates.

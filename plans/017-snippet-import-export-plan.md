# Snippet Import & Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export snippets (whole library, a collection, or a selection) to one `.snippets` JSON file and import such files back, with a Finder-style Stop / Skip / Replace + Apply to all conflict prompt.

**Architecture:** Three UI-free units under `Sources/Snippets/Features/Transfer/` — `SnippetArchive` (file format + validation), `SnippetExporter` (models → archive), `SnippetImporter` (archive → models, conflict callback) — plus one `@MainActor` glue object, `SnippetTransferController`, that runs panels, the `NSAlert` conflict prompt, file I/O, and publishes a toast message. Menu items, context menus, the select-mode bar, and Finder "open" all call the controller's singleton.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AppKit (`NSSavePanel`, `NSOpenPanel`, `NSAlert`), XCTest. Design: `plans/017-snippet-import-export-design.md`.

## Global Constraints

- Build system is `Snippets.xcodeproj` only; every new `.swift` file must be registered (helper below). No `Package.swift`.
- Toolchain: `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if `xcode-select -p` is not Xcode.
- Swift 6 language mode, no default actor isolation: annotate `@MainActor` explicitly on anything touching SwiftData models or AppKit.
- Two build configurations must both compile and pass tests: Debug, and `AppStore` (sandboxed, `APP_STORE` defined) run with `ENABLE_TESTABILITY=YES`.
- File format id `com.halilbagosi.snippets`, extension `.snippets`, `version` 1, max file size 500 MB.
- Never export Trash, preview permissions, or app settings. Replaced snippets must have `PreviewTrust.forget(uuid)` called.
- Imported media is written under `UUID().<ext>` only; the extension must belong to `MediaManager.allowedTypes`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

### Commands used throughout

```bash
# Debug suite
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test 2>&1 | grep -E "error:|Executed [0-9]+ tests.*seconds$|TEST (SUCCEEDED|FAILED)|failed \(" | tail -6
# One test class (Debug)
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' test -only-testing:SnippetsTests/<ClassName> 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)|failed \(" | tail -6
# AppStore suite
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' -configuration AppStore ENABLE_TESTABILITY=YES test 2>&1 | grep -E "error:|Executed [0-9]+ tests.*seconds$|TEST (SUCCEEDED|FAILED)|failed \(" | tail -6
```

### Registering files (do this, not `mod-pbxproj`, which re-sorts the whole project file)

Save this helper once as `$TMPDIR/pbx_register.py`:

```python
"""usage: python3 pbx_register.py group <Name> <parentGroupID>   -> prints new group id
       python3 pbx_register.py file <File.swift> <groupID> app|tests"""
import re, secrets, sys
project = "Snippets.xcodeproj/project.pbxproj"
s = open(project, encoding="utf-8").read()
used = set(re.findall(r"\b[0-9A-F]{24}\b", s))
def new_id():
    while True:
        i = secrets.token_hex(12).upper()
        if i not in used:
            used.add(i); return i
def insert_after(pattern, text):
    global s
    m = list(re.finditer(pattern, s))
    assert len(m) == 1, f"anchor {pattern!r} matched {len(m)} times"
    s = s[: m[0].end()] + text + s[m[0].end():]
def add_child(group_id, child_id, name):
    insert_after(r"\t\t" + group_id + r" /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n",
                 f"\t\t\t\t{child_id} /* {name} */,\n")
PHASE = {"app": r"\t\t\t\t[0-9A-F]{24} /\* AppEnvironment\.swift in Sources \*/,\n",
         "tests": r"\t\t\t\t[0-9A-F]{24} /\* AppearanceSettingsTests\.swift in Sources \*/,\n"}
kind, args = sys.argv[1], sys.argv[2:]
if kind == "group":
    name, parent = args; gid = new_id()
    insert_after(r"/\* Begin PBXGroup section \*/\n",
                 f'\t\t{gid} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t);\n'
                 f'\t\t\tpath = {name};\n\t\t\tsourceTree = "<group>";\n\t\t}};\n')
    add_child(parent, gid, name); print(gid)
else:
    name, group, target = args; fr, bf = new_id(), new_id()
    insert_after(r"/\* Begin PBXFileReference section \*/\n",
                 f'\t\t{fr} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {name}; sourceTree = "<group>"; }};\n')
    insert_after(r"/\* Begin PBXBuildFile section \*/\n",
                 f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};\n")
    add_child(group, fr, name)
    insert_after(PHASE[target], f"\t\t\t\t{bf} /* {name} in Sources */,\n")
open(project, "w", encoding="utf-8").write(s)
```

Group ids: `Features` = `D162801B5F6E0AE5BCE07169`, `App` = `52340538EFD250B44AE38B68`, test group `SnippetsTests` = `5E57E5700000000000000003`. After registering, `plutil -lint Snippets.xcodeproj/project.pbxproj` must print OK.

---

### Task 1: `SnippetArchive` — file format, validation, sanitising

**Files:**
- Create: `Sources/Snippets/Features/Transfer/SnippetArchive.swift`
- Test: `Tests/SnippetsTests/SnippetArchiveTests.swift`
- Modify: `Snippets.xcodeproj/project.pbxproj` (register both, create `Transfer` group)

**Interfaces:**
- Produces:
  - `extension UTType { static let snippetsArchive: UTType }`
  - `struct SnippetArchive: Codable, Equatable` with `format: String`, `version: Int`, `exportedAt: Date`, `appVersion: String`, `collections: [CollectionRecord]`, `snippets: [SnippetRecord]`; statics `formatIdentifier`, `currentVersion`, `maxByteCount`
  - `SnippetArchive.CollectionRecord(id:name:colorHex:colorHexDark:iconName:parentID:isFavorite:createdAt:updatedAt:)`
  - `SnippetArchive.SnippetRecord(id:title:description:language:code:createdAt:updatedAt:isFavorite:copyCount:collectionIDs:dependencyIDs:paramConfigs:activeParamConfigID:media:)`
  - `SnippetArchive.MediaRecord(kind:fileExtension:addedAt:data:)`
  - `enum SnippetArchive.ReadError: LocalizedError, Equatable { case tooLarge, notAnArchive, newerVersion, damaged }`
  - `static func decode(_ data: Data, maxByteCount: Int = SnippetArchive.maxByteCount) throws -> SnippetArchive` (returns sanitised)
  - `func encoded() throws -> Data`
  - `func sanitized() -> SnippetArchive`
  - `static func isAcceptable(_ media: MediaRecord) -> Bool`

- [ ] **Step 1: Register the files**

```bash
mkdir -p Sources/Snippets/Features/Transfer
touch Sources/Snippets/Features/Transfer/SnippetArchive.swift Tests/SnippetsTests/SnippetArchiveTests.swift
G=$(python3 $TMPDIR/pbx_register.py group Transfer D162801B5F6E0AE5BCE07169); echo "Transfer group: $G"
python3 $TMPDIR/pbx_register.py file SnippetArchive.swift $G app
python3 $TMPDIR/pbx_register.py file SnippetArchiveTests.swift 5E57E5700000000000000003 tests
plutil -lint Snippets.xcodeproj/project.pbxproj
```

Record the printed `Transfer` group id — Tasks 2–4 register into it.

- [ ] **Step 2: Write the failing tests** — `Tests/SnippetsTests/SnippetArchiveTests.swift`

```swift
import XCTest
@testable import Snippets

final class SnippetArchiveTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func media(_ kind: String, _ ext: String) -> SnippetArchive.MediaRecord {
        .init(kind: kind, fileExtension: ext, addedAt: t, data: Data([1, 2, 3]))
    }

    private func snippet(
        _ id: UUID = UUID(),
        collections: [UUID] = [],
        deps: [UUID] = [],
        configs: [PreviewParamConfig] = [],
        active: UUID? = nil,
        media: [SnippetArchive.MediaRecord] = []
    ) -> SnippetArchive.SnippetRecord {
        .init(id: id, title: "Title", description: "Desc", language: "React", code: "code",
              createdAt: t, updatedAt: t, isFavorite: true, copyCount: 4,
              collectionIDs: collections, dependencyIDs: deps,
              paramConfigs: configs, activeParamConfigID: active, media: media)
    }

    private func collection(_ id: UUID = UUID(), name: String = "C", parent: UUID? = nil) -> SnippetArchive.CollectionRecord {
        .init(id: id, name: name, colorHex: "#FF0000", colorHexDark: "#330000", iconName: "star",
              parentID: parent, isFavorite: true, createdAt: t, updatedAt: t)
    }

    func test_encodeDecode_roundTripsEveryField() throws {
        let root = UUID(), child = UUID(), dep = UUID(), config = UUID()
        let archive = SnippetArchive(
            exportedAt: t, appVersion: "1.0",
            collections: [collection(root, name: "Root"), collection(child, name: "Child", parent: root)],
            snippets: [
                snippet(dep),
                snippet(collections: [child], deps: [dep],
                        configs: [PreviewParamConfig(id: config, name: "Big", values: ["size": .number(40)], isDefault: false)],
                        active: config, media: [media("image", "png")]),
            ])
        XCTAssertEqual(try SnippetArchive.decode(archive.encoded()), archive)
    }

    func test_decode_rejectsNonJSON() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data("hello".utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .notAnArchive)
        }
    }

    func test_decode_rejectsOtherFormats() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data(#"{"format":"com.example.other","version":1}"#.utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .notAnArchive)
        }
    }

    func test_decode_rejectsNewerVersion_beforeLookingAtTheBody() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data(#"{"format":"com.halilbagosi.snippets","version":2}"#.utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .newerVersion)
        }
    }

    func test_decode_rejectsMissingFields() {
        XCTAssertThrowsError(try SnippetArchive.decode(Data(#"{"format":"com.halilbagosi.snippets","version":1}"#.utf8))) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .damaged)
        }
    }

    func test_decode_rejectsDuplicateIDs() throws {
        let id = UUID()
        let archive = SnippetArchive(exportedAt: t, appVersion: "1.0", collections: [], snippets: [snippet(id), snippet(id)])
        XCTAssertThrowsError(try SnippetArchive.decode(archive.encoded())) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .damaged)
        }
    }

    func test_decode_rejectsOversizedData() throws {
        let data = try SnippetArchive(exportedAt: t, appVersion: "1.0", collections: [], snippets: []).encoded()
        XCTAssertThrowsError(try SnippetArchive.decode(data, maxByteCount: data.count - 1)) {
            XCTAssertEqual($0 as? SnippetArchive.ReadError, .tooLarge)
        }
    }

    func test_sanitized_dropsDanglingReferences() {
        let real = UUID(), self_ = UUID()
        let archive = SnippetArchive(
            exportedAt: t, appVersion: "1.0",
            collections: [collection(real, parent: UUID())],
            snippets: [
                snippet(self_, collections: [real, UUID(), real], deps: [UUID(), self_], active: UUID()),
            ]).sanitized()
        XCTAssertNil(archive.collections[0].parentID)
        XCTAssertEqual(archive.snippets[0].collectionIDs, [real])
        XCTAssertEqual(archive.snippets[0].dependencyIDs, [])
        XCTAssertNil(archive.snippets[0].activeParamConfigID)
    }

    func test_sanitized_keepsDependencyOrder() {
        let a = UUID(), b = UUID(), c = UUID()
        let archive = SnippetArchive(exportedAt: t, appVersion: "1.0", collections: [],
                                     snippets: [snippet(a, deps: [c, b]), snippet(b), snippet(c)]).sanitized()
        XCTAssertEqual(archive.snippets[0].dependencyIDs, [c, b])
    }

    func test_sanitized_breaksParentCycles() {
        let a = UUID(), b = UUID()
        let archive = SnippetArchive(exportedAt: t, appVersion: "1.0",
                                     collections: [collection(a, parent: b), collection(b, parent: a)],
                                     snippets: []).sanitized()
        XCTAssertEqual(archive.collections[0].parentID, b)
        XCTAssertNil(archive.collections[1].parentID)
    }

    func test_sanitized_dropsUnacceptableMedia() {
        let archive = SnippetArchive(
            exportedAt: t, appVersion: "1.0", collections: [],
            snippets: [snippet(media: [
                media("image", "png"), media("video", "mov"), media("audio", "png"),
                media("image", "exe"), media("image", "../png"), media("image", ""),
            ])]).sanitized()
        XCTAssertEqual(archive.snippets[0].media.map(\.fileExtension), ["png", "mov"])
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: one-class command with `SnippetArchiveTests`.
Expected: build error `cannot find 'SnippetArchive' in scope`.

- [ ] **Step 4: Implement** — `Sources/Snippets/Features/Transfer/SnippetArchive.swift`

```swift
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A Snippets export (`.snippets`). Declared in `Snippets-Info.plist`.
    static let snippetsArchive = UTType(exportedAs: "com.halilbagosi.snippets", conformingTo: .json)
}

/// The on-disk shape of a `.snippets` export. Plain values only — no
/// SwiftData — so encoding, decoding and validation are testable on their own.
///
/// Preview permissions are deliberately absent from the format: a file can
/// never carry run approval or network access into someone's library.
struct SnippetArchive: Codable, Equatable {
    static let formatIdentifier = "com.halilbagosi.snippets"
    static let currentVersion = 1
    /// The whole file is held in memory while it is read, media included.
    static let maxByteCount = 500 * 1024 * 1024

    var format: String = SnippetArchive.formatIdentifier
    var version: Int = SnippetArchive.currentVersion
    var exportedAt: Date
    var appVersion: String
    var collections: [CollectionRecord]
    var snippets: [SnippetRecord]

    struct CollectionRecord: Codable, Equatable {
        var id: UUID
        var name: String
        var colorHex: String
        var colorHexDark: String?
        var iconName: String
        var parentID: UUID?
        var isFavorite: Bool
        var createdAt: Date
        var updatedAt: Date
    }

    struct SnippetRecord: Codable, Equatable {
        var id: UUID
        var title: String
        var description: String
        var language: String
        var code: String
        var createdAt: Date
        var updatedAt: Date
        var isFavorite: Bool
        var copyCount: Int
        var collectionIDs: [UUID]
        /// In the user's arranged order.
        var dependencyIDs: [UUID]
        var paramConfigs: [PreviewParamConfig]
        var activeParamConfigID: UUID?
        var media: [MediaRecord]
    }

    struct MediaRecord: Codable, Equatable {
        var kind: String
        var fileExtension: String
        var addedAt: Date
        /// Base64 in the JSON (JSONEncoder's default for `Data`).
        var data: Data
    }

    enum ReadError: LocalizedError, Equatable {
        case tooLarge, notAnArchive, newerVersion, damaged

        var errorDescription: String? {
            switch self {
            case .tooLarge: "This file is too large to import."
            case .notAnArchive: "This isn't a Snippets export."
            case .newerVersion: "This file was made by a newer version of Snippets."
            case .damaged: "This Snippets export is damaged."
            }
        }
    }

    // MARK: Coding

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return try encoder.encode(self)
    }

    /// Validates and sanitises before returning; nothing it returns needs
    /// re-checking by the importer.
    static func decode(_ data: Data, maxByteCount: Int = SnippetArchive.maxByteCount) throws -> SnippetArchive {
        guard data.count <= maxByteCount else { throw ReadError.tooLarge }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(string, strategy: .iso8601) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date \(string)")
        }

        // Read the envelope first, so a newer file says so instead of failing
        // on whichever field changed shape.
        struct Envelope: Decodable { let format: String; let version: Int }
        guard let envelope = try? decoder.decode(Envelope.self, from: data),
              envelope.format == formatIdentifier
        else { throw ReadError.notAnArchive }
        guard envelope.version <= currentVersion else { throw ReadError.newerVersion }

        let archive: SnippetArchive
        do { archive = try decoder.decode(SnippetArchive.self, from: data) } catch { throw ReadError.damaged }

        guard Set(archive.collections.map(\.id)).count == archive.collections.count,
              Set(archive.snippets.map(\.id)).count == archive.snippets.count
        else { throw ReadError.damaged }

        return archive.sanitized()
    }

    // MARK: Sanitising

    /// Drops what cannot be honoured instead of rejecting the file: references
    /// to ids not in the file, self-dependencies, parent cycles, an active
    /// config that does not exist, and media the app would not accept.
    func sanitized() -> SnippetArchive {
        let collectionIDs = Set(collections.map(\.id))
        let snippetIDs = Set(snippets.map(\.id))
        var copy = self

        copy.collections = Self.breakingParentCycles(collections.map { record in
            var record = record
            if let parent = record.parentID, parent == record.id || !collectionIDs.contains(parent) {
                record.parentID = nil
            }
            return record
        })

        copy.snippets = snippets.map { record in
            var record = record
            record.collectionIDs = record.collectionIDs.filter(collectionIDs.contains).removingDuplicates()
            record.dependencyIDs = record.dependencyIDs
                .filter { snippetIDs.contains($0) && $0 != record.id }
                .removingDuplicates()
            if let active = record.activeParamConfigID, !record.paramConfigs.contains(where: { $0.id == active }) {
                record.activeParamConfigID = nil
            }
            record.media = record.media.filter(Self.isAcceptable)
            return record
        }
        return copy
    }

    /// Walks each parent chain; the link that would close a loop is cut.
    private static func breakingParentCycles(_ collections: [CollectionRecord]) -> [CollectionRecord] {
        var parent = Dictionary(collections.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
        for start in collections.map(\.id) {
            var path: Set<UUID> = [start]
            var current = start
            while let next = parent[current] ?? nil {
                if path.contains(next) {
                    parent[current] = .some(nil)
                    break
                }
                path.insert(next)
                current = next
            }
        }
        return collections.map { record in
            var record = record
            record.parentID = parent[record.id] ?? nil
            return record
        }
    }

    /// Only image/video attachments whose extension maps to a type the media
    /// picker already accepts. The extension is the only part of an imported
    /// attachment that ever reaches a file name.
    static func isAcceptable(_ media: MediaRecord) -> Bool {
        guard MediaKind(rawValue: media.kind) != nil,
              !media.fileExtension.isEmpty,
              media.fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              let type = UTType(filenameExtension: media.fileExtension.lowercased())
        else { return false }
        return MediaManager.allowedTypes.contains { type.conforms(to: $0) }
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: one-class command with `SnippetArchiveTests`.
Expected: `Executed 11 tests, with 0 failures`, `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Snippets/Features/Transfer/SnippetArchive.swift Tests/SnippetsTests/SnippetArchiveTests.swift Snippets.xcodeproj/project.pbxproj
git commit -m "Add the .snippets archive format with validation

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `SnippetExporter` — library models → archive

**Files:**
- Create: `Sources/Snippets/Features/Transfer/SnippetExporter.swift`
- Test: `Tests/SnippetsTests/SnippetExporterTests.swift`
- Modify: `Snippets.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SnippetArchive`, `CollectionRecord`, `SnippetRecord`, `MediaRecord`, `sanitized()` (Task 1).
- Produces: `@MainActor enum SnippetExporter { static func archive(snippets: [Snippet], collections: [SnippetCollection], appVersion: String, now: Date = .now, mediaData: (MediaItem) -> Data?) -> SnippetArchive }`. Assigns a `uuid` to any included model lacking one (caller saves the context).

- [ ] **Step 1: Register the files** (use the `Transfer` group id from Task 1)

```bash
touch Sources/Snippets/Features/Transfer/SnippetExporter.swift Tests/SnippetsTests/SnippetExporterTests.swift
python3 $TMPDIR/pbx_register.py file SnippetExporter.swift <TransferGroupID> app
python3 $TMPDIR/pbx_register.py file SnippetExporterTests.swift 5E57E5700000000000000003 tests
plutil -lint Snippets.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Write the failing tests** — `Tests/SnippetsTests/SnippetExporterTests.swift`

```swift
import XCTest
import SwiftData
@testable import Snippets

@MainActor
final class SnippetExporterTests: XCTestCase {
    // Returned so the caller keeps the container alive.
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Snippet.self, MediaItem.self, SnippetCollection.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func export(_ snippets: [Snippet] = [], _ collections: [SnippetCollection] = [],
                        media: [String: Data] = [:]) -> SnippetArchive {
        SnippetExporter.archive(snippets: snippets, collections: collections, appVersion: "1.0",
                                mediaData: { media[$0.fileName] })
    }

    func test_trashedSnippetsAndCollections_neverLeave() throws {
        let container = try makeContainer(); let context = container.mainContext
        let kept = Snippet(title: "kept"), gone = Snippet(title: "gone", deletedAt: .now)
        let live = SnippetCollection(name: "live"), dead = SnippetCollection(name: "dead", deletedAt: .now)
        [kept, gone].forEach(context.insert); [live, dead].forEach(context.insert)
        kept.collections = [live, dead]
        try context.save()

        let archive = export([kept, gone], [live, dead])

        XCTAssertEqual(archive.snippets.map(\.title), ["kept"])
        XCTAssertEqual(archive.collections.map(\.name), ["live"])
        XCTAssertEqual(archive.snippets[0].collectionIDs, [live.uuid!])
    }

    func test_snippetExport_bringsItsCollectionsAndTheirAncestors() throws {
        let container = try makeContainer(); let context = container.mainContext
        let root = SnippetCollection(name: "root"), mid = SnippetCollection(name: "mid"), other = SnippetCollection(name: "other")
        let snippet = Snippet(title: "s")
        [root, mid, other].forEach(context.insert); context.insert(snippet)
        mid.parent = root
        snippet.collections = [mid]
        try context.save()

        let archive = export([snippet])

        XCTAssertEqual(Set(archive.collections.map(\.name)), ["root", "mid"])
        XCTAssertEqual(archive.collections.first { $0.name == "mid" }?.parentID, root.uuid)
        XCTAssertNil(archive.collections.first { $0.name == "root" }?.parentID)
    }

    func test_collectionExport_includesSubtreeEmptyChildrenAndSnippets() throws {
        let container = try makeContainer(); let context = container.mainContext
        let top = SnippetCollection(name: "top"), child = SnippetCollection(name: "child"), empty = SnippetCollection(name: "empty")
        let inside = Snippet(title: "inside"), outside = Snippet(title: "outside")
        [top, child, empty].forEach(context.insert); [inside, outside].forEach(context.insert)
        child.parent = top
        empty.parent = child
        inside.collections = [child]
        try context.save()

        let archive = export([], [top])

        XCTAssertEqual(Set(archive.collections.map(\.name)), ["top", "child", "empty"])
        XCTAssertEqual(archive.snippets.map(\.title), ["inside"])
    }

    func test_dependencies_keepOrder_andDropThoseOutsideTheExport() throws {
        let container = try makeContainer(); let context = container.mainContext
        let a = Snippet(title: "a"), b = Snippet(title: "b"), c = Snippet(title: "c")
        [a, b, c].forEach(context.insert)
        a.dependencies = [c, b]
        try context.save()

        let all = export([a, b, c])
        XCTAssertEqual(all.snippets.first { $0.title == "a" }?.dependencyIDs, [c.uuid!, b.uuid!])

        let partial = export([a, b])
        XCTAssertEqual(partial.snippets.first { $0.title == "a" }?.dependencyIDs, [b.uuid!])
    }

    func test_modelsWithoutUUID_getOneThatTheRecordUses() throws {
        let container = try makeContainer(); let context = container.mainContext
        let snippet = Snippet(uuid: nil, title: "old")
        let collection = SnippetCollection(uuid: nil, name: "old")
        context.insert(snippet); context.insert(collection)
        snippet.collections = [collection]

        let archive = export([snippet])

        XCTAssertNotNil(snippet.uuid)
        XCTAssertNotNil(collection.uuid)
        XCTAssertEqual(archive.snippets[0].id, snippet.uuid)
        XCTAssertEqual(archive.snippets[0].collectionIDs, [collection.uuid!])
    }

    func test_configsAndReadableMedia_areCarried() throws {
        let container = try makeContainer(); let context = container.mainContext
        let snippet = Snippet(title: "s", language: "React", code: "x")
        context.insert(snippet)
        let config = PreviewParamConfig(id: UUID(), name: "Big", values: ["size": .number(40)], isDefault: false)
        snippet.paramConfigs = [config]
        snippet.activeParamConfigID = config.id
        let readable = MediaItem(fileName: "a.png", kind: .image), missing = MediaItem(fileName: "b.png", kind: .image)
        context.insert(readable); context.insert(missing)
        snippet.mediaItems = [readable, missing]

        let record = export([snippet], media: ["a.png": Data([1, 2])]).snippets[0]

        XCTAssertEqual(record.paramConfigs, [config])
        XCTAssertEqual(record.activeParamConfigID, config.id)
        XCTAssertEqual(record.media, [.init(kind: "image", fileExtension: "png", addedAt: readable.addedAt, data: Data([1, 2]))])
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: one-class command with `SnippetExporterTests`.
Expected: build error `cannot find 'SnippetExporter' in scope`.

- [ ] **Step 4: Implement** — `Sources/Snippets/Features/Transfer/SnippetExporter.swift`

```swift
import Foundation
import SwiftData

/// Turns library models into a `SnippetArchive`. Trash never leaves, and
/// preview trust is not part of the models, so it cannot leave either.
@MainActor
enum SnippetExporter {
    /// - Parameters:
    ///   - snippets: exported on their own; their collections and every
    ///     ancestor of those come along so the nesting rebuilds on import.
    ///   - collections: exported whole — the subtree (empty children too) and
    ///     every snippet in it.
    ///   - mediaData: reads an attachment's bytes; nil drops the attachment.
    static func archive(
        snippets: [Snippet],
        collections: [SnippetCollection],
        appVersion: String,
        now: Date = .now,
        mediaData: (MediaItem) -> Data?
    ) -> SnippetArchive {
        var includedCollections: [SnippetCollection] = []
        var seenCollections = Set<PersistentIdentifier>()
        func addCollection(_ collection: SnippetCollection) {
            guard !collection.isDeleted, seenCollections.insert(collection.persistentModelID).inserted else { return }
            includedCollections.append(collection)
        }

        var includedSnippets: [Snippet] = []
        var seenSnippets = Set<PersistentIdentifier>()
        func addSnippet(_ snippet: Snippet) {
            guard !snippet.isDeleted, seenSnippets.insert(snippet.persistentModelID).inserted else { return }
            includedSnippets.append(snippet)
        }

        func addSubtree(_ collection: SnippetCollection) {
            guard !collection.isDeleted else { return }
            addCollection(collection)
            collection.snippets.forEach(addSnippet)
            collection.children.forEach(addSubtree)
        }

        collections.forEach(addSubtree)
        snippets.forEach(addSnippet)
        for snippet in includedSnippets { snippet.collections.forEach(addCollection) }
        // Grows while iterating: each added parent gets its own parent checked.
        var index = 0
        while index < includedCollections.count {
            if let parent = includedCollections[index].parent { addCollection(parent) }
            index += 1
        }

        // Rows predating the uuid backfill get one now, so a re-export is stable
        // and an import can recognise them. The caller saves the context.
        for collection in includedCollections where collection.uuid == nil { collection.uuid = UUID() }
        for snippet in includedSnippets where snippet.uuid == nil { snippet.uuid = UUID() }

        let collectionRecords = includedCollections
            .sorted { ($0.createdAt, $0.uuid!.uuidString) < ($1.createdAt, $1.uuid!.uuidString) }
            .map { collection in
                SnippetArchive.CollectionRecord(
                    id: collection.uuid!,
                    name: collection.name,
                    colorHex: collection.colorHex,
                    colorHexDark: collection.colorHexDark,
                    iconName: collection.iconName,
                    parentID: collection.parent?.uuid,
                    isFavorite: collection.isFavorite,
                    createdAt: collection.createdAt,
                    updatedAt: collection.updatedAt
                )
            }

        let snippetRecords = includedSnippets
            .sorted { ($0.createdAt, $0.uuid!.uuidString) < ($1.createdAt, $1.uuid!.uuidString) }
            .map { snippet in
                SnippetArchive.SnippetRecord(
                    id: snippet.uuid!,
                    title: snippet.title,
                    description: snippet.snippetDescription,
                    language: snippet.language,
                    code: snippet.code,
                    createdAt: snippet.createdAt,
                    updatedAt: snippet.updatedAt,
                    isFavorite: snippet.isFavorite,
                    copyCount: snippet.copyCount,
                    collectionIDs: snippet.collections.compactMap(\.uuid).sorted { $0.uuidString < $1.uuidString },
                    dependencyIDs: snippet.dependencies.compactMap(\.uuid),
                    paramConfigs: snippet.paramConfigs,
                    activeParamConfigID: snippet.activeParamConfigID,
                    media: snippet.mediaItems.sorted { $0.addedAt < $1.addedAt }.compactMap { item in
                        guard let data = mediaData(item) else { return nil }
                        return SnippetArchive.MediaRecord(
                            kind: item.fileTypeRaw,
                            fileExtension: (item.fileName as NSString).pathExtension.lowercased(),
                            addedAt: item.addedAt,
                            data: data
                        )
                    }
                )
            }

        // `sanitized` is the one place that drops references leaving the file
        // (dependencies outside the export, trashed collections, unknown ids).
        return SnippetArchive(exportedAt: now, appVersion: appVersion,
                              collections: collectionRecords, snippets: snippetRecords).sanitized()
    }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: one-class command with `SnippetExporterTests`.
Expected: `Executed 6 tests, with 0 failures`.

If `test_collectionExport_…` fails because `children`/`snippets` inverses are empty, confirm `try context.save()` precedes the export (it does in the test) before changing production code.

- [ ] **Step 6: Commit**

```bash
git add Sources/Snippets/Features/Transfer/SnippetExporter.swift Tests/SnippetsTests/SnippetExporterTests.swift Snippets.xcodeproj/project.pbxproj
git commit -m "Export snippets, collections and media to a SnippetArchive

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `SnippetImporter` — archive → models with conflict resolution

**Files:**
- Create: `Sources/Snippets/Features/Transfer/SnippetImporter.swift`
- Test: `Tests/SnippetsTests/SnippetImporterTests.swift`
- Modify: `Snippets.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `SnippetArchive` & records (Task 1), `SnippetExporter.archive` (Task 2, round-trip test only), `MediaManager.kind(for: URL) -> MediaKind` (existing).
- Produces:
  - `struct ImportConflict: Equatable { let id: UUID; let title: String; let isInTrash: Bool }`
  - `enum ConflictChoice: Equatable { case skip, replace, stop }`
  - `struct ConflictResolution: Equatable { var choice: ConflictChoice; var applyToAll: Bool }`
  - `struct ImportSummary: Equatable { var added = 0; var replaced = 0; var skipped = 0; var stopped = false; var message: String }`
  - `@MainActor struct SnippetImporter { var writeMedia: @MainActor (Data, String) throws -> String; var removeMedia: @MainActor (String) -> Void; var forgetTrust: @MainActor (UUID) -> Void; func apply(_ archive: SnippetArchive, to context: ModelContext, resolve: @MainActor (ImportConflict) async -> ConflictResolution) async throws -> ImportSummary }`
  - `removeMedia` receives a file name and is called only after the context saved.

- [ ] **Step 1: Register the files**

```bash
touch Sources/Snippets/Features/Transfer/SnippetImporter.swift Tests/SnippetsTests/SnippetImporterTests.swift
python3 $TMPDIR/pbx_register.py file SnippetImporter.swift <TransferGroupID> app
python3 $TMPDIR/pbx_register.py file SnippetImporterTests.swift 5E57E5700000000000000003 tests
plutil -lint Snippets.xcodeproj/project.pbxproj
```

- [ ] **Step 2: Write the failing tests** — `Tests/SnippetsTests/SnippetImporterTests.swift`

```swift
import XCTest
import SwiftData
@testable import Snippets

/// Stand-in for the media directory. Main-actor isolated, which makes it
/// Sendable and so capturable by the importer's `@MainActor` closures.
@MainActor
private final class MediaStore {
    var files: [String: Data] = [:]
    var removed: [String] = []

    func write(_ data: Data, ext: String) -> String {
        let name = "\(UUID().uuidString).\(ext)"
        files[name] = data
        return name
    }
}

@MainActor
private final class Recorder<Value> {
    var values: [Value] = []
}

@MainActor
final class SnippetImporterTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Snippet.self, MediaItem.self, SnippetCollection.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func importer(_ media: MediaStore, forgotten: Recorder<UUID> = Recorder()) -> SnippetImporter {
        SnippetImporter(
            writeMedia: { data, ext in media.write(data, ext: ext) },
            removeMedia: { name in media.removed.append(name); media.files[name] = nil },
            forgetTrust: { forgotten.values.append($0) }
        )
    }

    private func record(_ id: UUID = UUID(), title: String = "Imported", code: String = "theirs",
                        collections: [UUID] = [], deps: [UUID] = [],
                        media: [SnippetArchive.MediaRecord] = []) -> SnippetArchive.SnippetRecord {
        .init(id: id, title: title, description: "", language: "Swift", code: code,
              createdAt: t, updatedAt: t, isFavorite: false, copyCount: 0,
              collectionIDs: collections, dependencyIDs: deps,
              paramConfigs: [], activeParamConfigID: nil, media: media)
    }

    private func archive(_ snippets: [SnippetArchive.SnippetRecord],
                         collections: [SnippetArchive.CollectionRecord] = []) -> SnippetArchive {
        SnippetArchive(exportedAt: t, appVersion: "1.0", collections: collections, snippets: snippets).sanitized()
    }

    /// A library snippet with `id` and one attachment.
    @discardableResult
    private func seed(_ context: ModelContext, _ media: MediaStore, id: UUID, title: String = "Local",
                      trashed: Bool = false) -> Snippet {
        let snippet = Snippet(uuid: id, title: title, code: "local", deletedAt: trashed ? .now : nil)
        context.insert(snippet)
        let item = MediaItem(fileName: media.write(Data([9]), ext: "png"), kind: .image)
        context.insert(item)
        snippet.mediaItems = [item]
        return snippet
    }

    private let never: @MainActor (ImportConflict) async -> ConflictResolution = { _ in
        XCTFail("no conflict expected")
        return ConflictResolution(choice: .stop, applyToAll: false)
    }

    // MARK: Round trip

    func test_roundTrip_intoEmptyStore_preservesEverything() async throws {
        let sourceContainer = try makeContainer(); let source = sourceContainer.mainContext
        let sourceMedia = MediaStore()
        let root = SnippetCollection(name: "Root", colorHex: "#FF0000", colorHexDark: "#330000", iconName: "star", isFavorite: true)
        let child = SnippetCollection(name: "Child")
        let css = Snippet(title: "Theme", language: "CSS", code: "body {}")
        let entry = Snippet(title: "App", snippetDescription: "entry", language: "React",
                            code: "export default () => null", copyCount: 3, isFavorite: true)
        [root, child].forEach(source.insert); [css, entry].forEach(source.insert)
        child.parent = root
        entry.collections = [child]
        entry.dependencies = [css]
        let config = PreviewParamConfig(id: UUID(), name: "Big", values: ["size": .number(40)], isDefault: false)
        entry.paramConfigs = [config]
        entry.activeParamConfigID = config.id
        let sourceName = sourceMedia.write(Data([1, 2, 3]), ext: "png")
        let item = MediaItem(fileName: sourceName, kind: .image)
        source.insert(item)
        entry.mediaItems = [item]
        try source.save()

        let exported = SnippetExporter.archive(snippets: [entry, css], collections: [], appVersion: "1.0",
                                               mediaData: { sourceMedia.files[$0.fileName] })
        let decoded = try SnippetArchive.decode(exported.encoded())

        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore()
        let summary = try await importer(media).apply(decoded, to: context, resolve: never)

        XCTAssertEqual(summary, ImportSummary(added: 2))
        let app = try XCTUnwrap(try context.fetch(FetchDescriptor<Snippet>()).first { $0.title == "App" })
        XCTAssertEqual(app.uuid, entry.uuid)
        XCTAssertEqual(app.snippetDescription, "entry")
        XCTAssertEqual(app.language, "React")
        XCTAssertEqual(app.code, "export default () => null")
        XCTAssertEqual(app.copyCount, 3)
        XCTAssertTrue(app.isFavorite)
        XCTAssertEqual(app.createdAt.timeIntervalSince1970, entry.createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(app.paramConfigs, [config])
        XCTAssertEqual(app.activeParamConfigID, config.id)
        XCTAssertEqual(app.dependencies.map(\.title), ["Theme"])
        XCTAssertEqual(app.collections.map(\.name), ["Child"])
        let importedRoot = try XCTUnwrap(app.collections.first?.parent)
        XCTAssertEqual(importedRoot.name, "Root")
        XCTAssertEqual(importedRoot.colorHex, "#FF0000")
        XCTAssertEqual(importedRoot.colorHexDark, "#330000")
        XCTAssertEqual(importedRoot.iconName, "star")
        XCTAssertTrue(importedRoot.isFavorite)
        XCTAssertEqual(app.mediaItems.count, 1)
        XCTAssertEqual(app.mediaItems.first?.kind, .image)
        XCTAssertNotEqual(app.mediaItems.first?.fileName, sourceName, "imported media gets a fresh name")
        XCTAssertEqual(media.files[app.mediaItems[0].fileName], Data([1, 2, 3]))
    }

    // MARK: Collections

    func test_existingCollections_areReusedAndRestored_notOverwritten() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let mineID = UUID()
        let mine = SnippetCollection(uuid: mineID, name: "Mine", deletedAt: .now)
        context.insert(mine)
        try context.save()
        let childID = UUID()
        let file = archive(
            [record(collections: [childID])],
            collections: [
                .init(id: mineID, name: "Theirs", colorHex: "#000000", colorHexDark: nil, iconName: "x",
                      parentID: nil, isFavorite: false, createdAt: t, updatedAt: t),
                .init(id: childID, name: "Child", colorHex: "#000000", colorHexDark: nil, iconName: "x",
                      parentID: mineID, isFavorite: false, createdAt: t, updatedAt: t),
            ])

        _ = try await importer(MediaStore()).apply(file, to: context, resolve: never)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SnippetCollection>()), 2)
        XCTAssertEqual(mine.name, "Mine")
        XCTAssertNil(mine.deletedAt)
        let child = try XCTUnwrap(try context.fetch(FetchDescriptor<SnippetCollection>()).first { $0.name == "Child" })
        XCTAssertTrue(child.parent === mine)
    }

    // MARK: Conflicts

    func test_skip_leavesTheLocalSnippetUntouched() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let id = UUID()
        let local = seed(context, media, id: id)
        let asked = Recorder<ImportConflict>()

        let summary = try await importer(media).apply(archive([record(id)]), to: context) { conflict in
            asked.values.append(conflict)
            return ConflictResolution(choice: .skip, applyToAll: false)
        }

        XCTAssertEqual(asked.values, [ImportConflict(id: id, title: "Local", isInTrash: false)])
        XCTAssertEqual(summary, ImportSummary(skipped: 1))
        XCTAssertEqual(local.code, "local")
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Snippet>()), 1)
        XCTAssertTrue(media.removed.isEmpty)
    }

    func test_replace_overwrites_restoresFromTrash_forgetsTrust_swapsMedia() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let id = UUID(); let forgotten = Recorder<UUID>()
        let local = seed(context, media, id: id, trashed: true)
        let oldFile = local.mediaItems[0].fileName
        try context.save()
        let incoming = record(id, media: [.init(kind: "video", fileExtension: "mov", addedAt: t, data: Data([7]))])

        let summary = try await importer(media, forgotten: forgotten).apply(archive([incoming]), to: context) { conflict in
            XCTAssertTrue(conflict.isInTrash)
            return ConflictResolution(choice: .replace, applyToAll: false)
        }

        XCTAssertEqual(summary, ImportSummary(replaced: 1))
        XCTAssertEqual(local.title, "Imported")
        XCTAssertEqual(local.code, "theirs")
        XCTAssertNil(local.deletedAt)
        XCTAssertEqual(forgotten.values, [id])
        XCTAssertEqual(local.mediaItems.count, 1)
        XCTAssertEqual(local.mediaItems.first?.kind, .video)
        XCTAssertEqual(media.files[local.mediaItems[0].fileName], Data([7]))
        XCTAssertEqual(media.removed, [oldFile])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Snippet>()), 1)
    }

    func test_stop_keepsWhatWasImportedBeforeIt() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let id = UUID()
        seed(context, media, id: id)

        let summary = try await importer(media).apply(
            archive([record(title: "first"), record(id), record(title: "after")]), to: context
        ) { _ in ConflictResolution(choice: .stop, applyToAll: false) }

        XCTAssertEqual(summary, ImportSummary(added: 1, stopped: true))
        let titles = Set(try context.fetch(FetchDescriptor<Snippet>()).map(\.title))
        XCTAssertEqual(titles, ["Local", "first"])
    }

    func test_applyToAll_asksOnce() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let a = UUID(), b = UUID()
        seed(context, media, id: a); seed(context, media, id: b)
        let asked = Recorder<ImportConflict>()

        let summary = try await importer(media).apply(archive([record(a), record(b)]), to: context) { conflict in
            asked.values.append(conflict)
            return ConflictResolution(choice: .skip, applyToAll: true)
        }

        XCTAssertEqual(asked.values.count, 1)
        XCTAssertEqual(summary, ImportSummary(skipped: 2))
    }

    func test_dependencyOnASkippedSnippet_linksTheLocalOne() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let localID = UUID()
        let local = seed(context, media, id: localID)

        _ = try await importer(media).apply(
            archive([record(localID), record(title: "uses local", deps: [localID])]), to: context
        ) { _ in ConflictResolution(choice: .skip, applyToAll: false) }

        let user = try XCTUnwrap(try context.fetch(FetchDescriptor<Snippet>()).first { $0.title == "uses local" })
        XCTAssertEqual(user.dependencies.count, 1)
        XCTAssertTrue(user.dependencies.first === local)
    }

    // MARK: Summary

    func test_summaryMessage() {
        XCTAssertEqual(ImportSummary(added: 1).message, "Imported 1 snippet")
        XCTAssertEqual(ImportSummary(added: 12, replaced: 3, skipped: 30).message,
                       "Imported 12 snippets · 3 replaced · 30 skipped")
        XCTAssertEqual(ImportSummary(added: 2, skipped: 1, stopped: true).message,
                       "Import stopped after 2 snippets · 1 skipped")
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: one-class command with `SnippetImporterTests`.
Expected: build error `cannot find 'SnippetImporter' in scope`.

- [ ] **Step 4: Implement** — `Sources/Snippets/Features/Transfer/SnippetImporter.swift`

```swift
import Foundation
import SwiftData

/// A snippet in the file whose id is already in the library (Trash included).
struct ImportConflict: Equatable {
    let id: UUID
    /// The local snippet's title — the one the user knows.
    let title: String
    let isInTrash: Bool
}

enum ConflictChoice: Equatable { case skip, replace, stop }

struct ConflictResolution: Equatable {
    var choice: ConflictChoice
    var applyToAll: Bool
}

struct ImportSummary: Equatable {
    var added = 0
    var replaced = 0
    var skipped = 0
    var stopped = false

    /// "Imported 12 snippets · 3 replaced · 30 skipped"
    var message: String {
        let noun = added == 1 ? "snippet" : "snippets"
        var parts = [stopped ? "Import stopped after \(added) \(noun)" : "Imported \(added) \(noun)"]
        if replaced > 0 { parts.append("\(replaced) replaced") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        return parts.joined(separator: " · ")
    }
}

/// Writes a validated `SnippetArchive` into the library. File and trust side
/// effects go through closures so the rules are testable without the media
/// directory or `PreviewTrust`.
@MainActor
struct SnippetImporter {
    /// Stores attachment bytes with the given (validated) extension; returns the file name.
    var writeMedia: @MainActor (Data, String) throws -> String
    /// Deletes a replaced attachment's file. Called only after the save succeeded.
    var removeMedia: @MainActor (String) -> Void
    /// Drops preview permissions for a replaced snippet.
    var forgetTrust: @MainActor (UUID) -> Void

    func apply(
        _ archive: SnippetArchive,
        to context: ModelContext,
        resolve: @MainActor (ImportConflict) async -> ConflictResolution
    ) async throws -> ImportSummary {
        var snippetsByID: [UUID: Snippet] = [:]
        for snippet in try context.fetch(FetchDescriptor<Snippet>()) {
            if let id = snippet.uuid { snippetsByID[id] = snippet }
        }
        var collectionsByID: [UUID: SnippetCollection] = [:]
        for collection in try context.fetch(FetchDescriptor<SnippetCollection>()) {
            if let id = collection.uuid { collectionsByID[id] = collection }
        }

        // Collections first, so snippets can join them. Existing ones are
        // reused as they are (only brought back from Trash); new ones are
        // created, then linked to their parents once all of them exist.
        var created: [UUID: SnippetCollection] = [:]
        for record in archive.collections {
            if let existing = collectionsByID[record.id] {
                existing.deletedAt = nil
            } else {
                let collection = SnippetCollection(
                    uuid: record.id, name: record.name, colorHex: record.colorHex,
                    colorHexDark: record.colorHexDark, iconName: record.iconName,
                    createdAt: record.createdAt, updatedAt: record.updatedAt, isFavorite: record.isFavorite
                )
                context.insert(collection)
                collectionsByID[record.id] = collection
                created[record.id] = collection
            }
        }
        for record in archive.collections {
            guard let collection = created[record.id], let parentID = record.parentID else { continue }
            collection.parent = collectionsByID[parentID]
        }

        var summary = ImportSummary()
        var standingChoice: ConflictChoice?
        var written: [(record: SnippetArchive.SnippetRecord, snippet: Snippet)] = []
        var replacedFiles: [String] = []

        for record in archive.snippets {
            guard let existing = snippetsByID[record.id] else {
                let snippet = Snippet(uuid: record.id)
                context.insert(snippet)
                replacedFiles += overwrite(snippet, with: record, collections: collectionsByID, in: context)
                snippetsByID[record.id] = snippet
                written.append((record, snippet))
                summary.added += 1
                continue
            }

            let choice: ConflictChoice
            if let standingChoice {
                choice = standingChoice
            } else {
                let resolution = await resolve(
                    ImportConflict(id: record.id, title: existing.title, isInTrash: existing.isDeleted)
                )
                if resolution.applyToAll { standingChoice = resolution.choice }
                choice = resolution.choice
            }

            if choice == .stop {
                summary.stopped = true
                break
            }
            if choice == .skip {
                summary.skipped += 1
                continue
            }
            replacedFiles += overwrite(existing, with: record, collections: collectionsByID, in: context)
            forgetTrust(record.id)
            written.append((record, existing))
            summary.replaced += 1
        }

        // Connections last: a dependency may appear later in the file. Ids that
        // resolve to nothing (a snippet never written because of Stop) drop out.
        for (record, snippet) in written {
            snippet.dependencies = record.dependencyIDs.compactMap { snippetsByID[$0] }
        }

        try context.save()
        replacedFiles.forEach(removeMedia)
        return summary
    }

    /// Copies every imported field onto `snippet` and swaps its attachments.
    /// Returns the file names of attachments it removed, for deletion after
    /// the save — a failed save must not have destroyed the user's files.
    private func overwrite(
        _ snippet: Snippet,
        with record: SnippetArchive.SnippetRecord,
        collections: [UUID: SnippetCollection],
        in context: ModelContext
    ) -> [String] {
        snippet.title = record.title
        snippet.snippetDescription = record.description
        snippet.language = record.language
        snippet.code = record.code
        snippet.createdAt = record.createdAt
        snippet.updatedAt = record.updatedAt
        snippet.isFavorite = record.isFavorite
        snippet.copyCount = record.copyCount
        snippet.deletedAt = nil
        snippet.paramConfigs = record.paramConfigs
        snippet.activeParamConfigID = record.activeParamConfigID
        snippet.collections = record.collectionIDs.compactMap { collections[$0] }

        let removed = snippet.mediaItems.map(\.fileName)
        snippet.mediaItems.forEach(context.delete)

        var items: [MediaItem] = []
        for media in record.media {
            // An attachment that cannot be written is dropped, not fatal.
            guard let name = try? writeMedia(media.data, media.fileExtension.lowercased()) else { continue }
            let item = MediaItem(fileName: name, kind: MediaManager.kind(for: URL(fileURLWithPath: name)), addedAt: media.addedAt)
            context.insert(item)
            items.append(item)
        }
        snippet.mediaItems = items
        return removed
    }
}
```

- [ ] **Step 5: Run to verify they pass**

Run: one-class command with `SnippetImporterTests`.
Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Snippets/Features/Transfer/SnippetImporter.swift Tests/SnippetsTests/SnippetImporterTests.swift Snippets.xcodeproj/project.pbxproj
git commit -m "Import SnippetArchives with skip/replace/stop conflict handling

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Wire it into the app — controller, menus, context menus, Finder open, sandbox

**Files:**
- Modify: `Sources/Snippets/Services/MediaManager.swift` (three methods)
- Create: `Sources/Snippets/Features/Transfer/SnippetTransferController.swift`
- Create: `Sources/Snippets/App/TransferCommands.swift`
- Modify: `Sources/Snippets/SnippetsApp.swift` (init, commands, `application(_:open:)`)
- Modify: `Sources/Snippets/Views/ContentView.swift` (toast)
- Modify: `Sources/Snippets/Views/SnippetGalleryView.swift` (card context menu, select-mode bar)
- Modify: `Sources/Snippets/Views/Sidebar/ModernSidebar.swift` (collection context menu)
- Modify: `Snippets-Info.plist` (exported type + document type)
- Modify: `Snippets-AppStore.entitlements` (read-write)
- Modify: `README.md`, `plans/017-snippet-import-export-design.md`
- Modify: `Snippets.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: everything from Tasks 1–3; `PreviewTrust.forget(_:)`, `MainWindowOpener.activate()`, `SnippetsData.sharedModelContainer`.
- Produces: `@MainActor @Observable final class SnippetTransferController { static let shared; var previewTrust: PreviewTrust?; private(set) var notice: Notice?; func clearNotice(); func exportLibrary(); func exportCollection(_:); func exportSnippets(_:collections:); func importWithPanel(); func importFile(at:) }`, `MediaManager.data(for:)`, `MediaManager.storeImported(_:fileExtension:)`, `MediaManager.deleteFile(named:)`.

- [ ] **Step 1: Register the new files**

```bash
touch Sources/Snippets/Features/Transfer/SnippetTransferController.swift Sources/Snippets/App/TransferCommands.swift
python3 $TMPDIR/pbx_register.py file SnippetTransferController.swift <TransferGroupID> app
python3 $TMPDIR/pbx_register.py file TransferCommands.swift 52340538EFD250B44AE38B68 app
plutil -lint Snippets.xcodeproj/project.pbxproj
```

- [ ] **Step 2: `MediaManager` — read, store and delete by name**

In `Sources/Snippets/Services/MediaManager.swift`, replace the instance `deleteFile(for:)`:

```swift
    func deleteFile(for item: MediaItem) {
        let url = resolvedURL(for: item.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Failed to delete media file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
```

with:

```swift
    func deleteFile(for item: MediaItem) {
        deleteFile(named: item.fileName)
    }

    func deleteFile(named fileName: String) {
        let url = resolvedURL(for: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.error("Failed to delete media file \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// An attachment's bytes for export; nil when the file is gone.
    func data(for item: MediaItem) -> Data? {
        try? Data(contentsOf: resolvedURL(for: item.fileName))
    }

    /// Stores imported bytes under a fresh name. Nothing from the import file
    /// reaches the path except an extension `SnippetArchive` already vetted.
    func storeImported(_ data: Data, fileExtension: String) throws -> String {
        let name = "\(UUID().uuidString).\(fileExtension)"
        try data.write(to: resolvedURL(for: name), options: .atomic)
        return name
    }
```

- [ ] **Step 3: The controller** — `Sources/Snippets/Features/Transfer/SnippetTransferController.swift`

```swift
import AppKit
import SwiftData
import UniformTypeIdentifiers

/// Runs import and export end to end: save/open panels, file I/O, the
/// Finder-style conflict alert, and the message ContentView shows as a toast.
/// The rules live in the UI-free `SnippetArchive`, `SnippetExporter` and
/// `SnippetImporter`; this type only connects them to AppKit.
@MainActor
@Observable
final class SnippetTransferController {
    static let shared = SnippetTransferController()

    struct Notice: Equatable {
        let id = UUID()
        let message: String
    }

    /// The latest result, for ContentView's toast. Cleared once shown.
    private(set) var notice: Notice?

    /// The app's live trust store (set by `SnippetsApp`). A second instance
    /// would hold stale in-memory approvals, so replaced snippets must be
    /// forgotten through this one.
    @ObservationIgnored var previewTrust: PreviewTrust?

    @ObservationIgnored private var isImporting = false

    private var context: ModelContext { SnippetsData.sharedModelContainer.mainContext }
    private var media: MediaManager { .shared }
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    func clearNotice() { notice = nil }

    // MARK: Export

    func exportLibrary() {
        do {
            export(snippets: try context.fetch(FetchDescriptor<Snippet>()),
                   collections: try context.fetch(FetchDescriptor<SnippetCollection>()),
                   suggestedName: "Snippets Library")
        } catch {
            report(error, doing: "export")
        }
    }

    func exportCollection(_ collection: SnippetCollection) {
        export(snippets: [], collections: [collection], suggestedName: collection.name)
    }

    func exportSnippets(_ snippets: [Snippet], collections: [SnippetCollection] = []) {
        let name = switch (snippets.count, collections.count) {
        case (1, 0): snippets[0].title
        case (0, 1): collections[0].name
        default: "Snippets"
        }
        export(snippets: snippets, collections: collections, suggestedName: name)
    }

    private func export(snippets: [Snippet], collections: [SnippetCollection], suggestedName: String) {
        let archive = SnippetExporter.archive(snippets: snippets, collections: collections,
                                              appVersion: appVersion, mediaData: media.data(for:))
        guard !archive.snippets.isEmpty || !archive.collections.isEmpty else {
            notice = Notice(message: "Nothing to export")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.snippetsArchive]
        panel.nameFieldStringValue = Self.fileName(for: suggestedName)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try context.save()   // keeps any uuid the exporter just assigned
            try archive.encoded().write(to: url, options: .atomic)
            let count = archive.snippets.count
            notice = Notice(message: "Exported \(count) \(count == 1 ? "snippet" : "snippets")")
        } catch {
            report(error, doing: "export")
        }
    }

    static func fileName(for suggested: String) -> String {
        let cleaned = suggested
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return (cleaned.isEmpty ? "Snippets" : cleaned) + ".snippets"
    }

    // MARK: Import

    func importWithPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.snippetsArchive]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importFile(at: url)
    }

    /// Shared by the open panel and by files opened from Finder or AirDrop.
    func importFile(at url: URL) {
        guard !isImporting else {
            NSSound.beep()
            return
        }
        isImporting = true
        // The toast and the conflict sheet both need the main window.
        MainWindowOpener.activate()

        let media = media
        Task {
            defer { isImporting = false }
            do {
                let archive = try SnippetArchive.decode(try Self.read(url))
                let importer = SnippetImporter(
                    writeMedia: { data, ext in try media.storeImported(data, fileExtension: ext) },
                    removeMedia: { name in media.deleteFile(named: name) },
                    forgetTrust: { [self] id in previewTrust?.forget(id) }
                )
                let summary = try await importer.apply(archive, to: context) { [self] conflict in
                    await ask(conflict)
                }
                notice = Notice(message: summary.message)
            } catch {
                report(error, doing: "import")
            }
        }
    }

    private static func read(_ url: URL) throws -> Data {
        // Files opened from Finder arrive security-scoped in the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= SnippetArchive.maxByteCount else { throw SnippetArchive.ReadError.tooLarge }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Finder's "an item named … already exists" prompt. Skip is the default
    /// (Return) because it is the one choice that cannot lose anything;
    /// Escape stops.
    private func ask(_ conflict: ImportConflict) async -> ConflictResolution {
        let alert = NSAlert()
        let title = conflict.title.isEmpty ? "Untitled" : conflict.title
        alert.messageText = "A snippet named “\(title)” already exists in your library."
        alert.informativeText = conflict.isInTrash
            ? "It's in Recently Deleted. Replacing it puts the imported version back in your library."
            : "Replacing it overwrites your copy with the imported one."
        alert.addButton(withTitle: "Skip")
        let replace = alert.addButton(withTitle: "Replace")
        replace.hasDestructiveAction = true
        let stop = alert.addButton(withTitle: "Stop")
        stop.keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Apply to all"

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        let choice: ConflictChoice = switch response {
        case .alertFirstButtonReturn: .skip
        case .alertSecondButtonReturn: .replace
        default: .stop
        }
        return ConflictResolution(choice: choice, applyToAll: alert.suppressionButton?.state == .on)
    }

    private func report(_ error: Error, doing action: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = action == "import" ? "Couldn't import snippets" : "Couldn't export snippets"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
```

- [ ] **Step 4: File menu** — `Sources/Snippets/App/TransferCommands.swift`

```swift
import SwiftUI

/// File ▸ Import Snippets… / Export Library…
struct TransferCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Button("Import Snippets…") { SnippetTransferController.shared.importWithPanel() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export Library…") { SnippetTransferController.shared.exportLibrary() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}
```

- [ ] **Step 5: `SnippetsApp.swift`**

(a) Hand the live trust store to the controller. Replace

```swift
    @State private var previewTrust = PreviewTrust()
```

with

```swift
    @State private var previewTrust: PreviewTrust

    init() {
        let trust = PreviewTrust()
        _previewTrust = State(initialValue: trust)
        SnippetTransferController.shared.previewTrust = trust
    }
```

(b) In `.commands { … }`, after `HelpCommands()` add:

```swift
            TransferCommands()
```

(c) In `AppDelegate`, after `applicationShouldTerminateAfterLastWindowClosed`, add:

```swift
    /// A `.snippets` file opened from Finder, AirDrop or the Dock icon.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { $0.pathExtension.lowercased() == "snippets" }) else { return }
        SnippetTransferController.shared.importFile(at: url)
    }
```

- [ ] **Step 6: Toast** — in `Sources/Snippets/Views/ContentView.swift`, directly above `.onChange(of: searchText) { _, newValue in`, add:

```swift
        .onChange(of: SnippetTransferController.shared.notice, initial: true) { _, notice in
            guard let notice else { return }
            showToast(notice.message)
            SnippetTransferController.shared.clearNotice()
        }
```

- [ ] **Step 7: Snippet context menu and select-mode bar** — `Sources/Snippets/Views/SnippetGalleryView.swift`

(a) In the card `.contextMenu`, non-trash branch, insert immediately before its `Divider()`:

```swift
                            Button { SnippetTransferController.shared.exportSnippets([snippet]) } label: {
                                Label("Export…", systemImage: "square.and.arrow.up")
                            }
```

(b) In the select-mode bar, after the closing `}` of the `if !isTrashMode { FilterTag(label: "move (…)" … }` block, add:

```swift
                            if !isTrashMode {
                                FilterTag(
                                    label: "export (\(viewModel.selectedForAction.count))",
                                    icon: "square.and.arrow.up",
                                    accent: theme.accent,
                                    isSelected: false
                                ) {
                                    SnippetTransferController.shared.exportSnippets(
                                        viewModel.selectedSnippets(from: displaySnippets),
                                        collections: viewModel.selectedCollections(from: subcollections)
                                    )
                                }
                                .disabled(viewModel.selectedForAction.isEmpty)
                                .opacity(viewModel.selectedForAction.isEmpty ? 0.5 : 1.0)
                                .transition(.opacity)
                            }
```

- [ ] **Step 8: Collection context menu** — `Sources/Snippets/Views/Sidebar/ModernSidebar.swift`, in `CollectionTreeRow`'s `.contextMenu` (the one with "Edit collection" / "Delete collection"), insert between them:

```swift
                Button { SnippetTransferController.shared.exportCollection(collection) } label: { Label("Export collection…", systemImage: "square.and.arrow.up") }
```

- [ ] **Step 9: File type, document type, sandbox**

Replace `Snippets-Info.plist` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleIconFile</key>
	<string>SnippetsIcon</string>
	<key>ITSAppUsesNonExemptEncryption</key>
	<false/>
	<key>UTExportedTypeDeclarations</key>
	<array>
		<dict>
			<key>UTTypeIdentifier</key>
			<string>com.halilbagosi.snippets</string>
			<key>UTTypeDescription</key>
			<string>Snippets Export</string>
			<key>UTTypeConformsTo</key>
			<array>
				<string>public.json</string>
			</array>
			<key>UTTypeTagSpecification</key>
			<dict>
				<key>public.filename-extension</key>
				<array>
					<string>snippets</string>
				</array>
			</dict>
		</dict>
	</array>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>
			<string>Snippets Export</string>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>LSHandlerRank</key>
			<string>Owner</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>com.halilbagosi.snippets</string>
			</array>
		</dict>
	</array>
</dict>
</plist>
```

In `Snippets-AppStore.entitlements` change `com.apple.security.files.user-selected.read-only` to `com.apple.security.files.user-selected.read-write`.

Run: `plutil -lint Snippets-Info.plist Snippets-AppStore.entitlements` → both OK.

- [ ] **Step 10: Build both configurations, run both suites**

```bash
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcodebuild -project Snippets.xcodeproj -scheme Snippets -destination 'platform=macOS' -configuration AppStore build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
```
Then the Debug and AppStore suite commands.
Expected: both `BUILD SUCCEEDED`; Debug `Executed 418 tests, with 0 failures` (393 + 25); AppStore `Executed 389 tests, with 0 failures` (364 + 25).

- [ ] **Step 11: Runtime verification (use the `verify` skill)**

Debug build (your real library):
1. File menu shows Import Snippets… ⇧⌘I and Export Library… ⇧⌘E.
2. Export Library… → save `~/Desktop/Snippets Library.snippets` → toast "Exported N snippets". `python3 -m json.tool` on the file succeeds; it contains no `deletedAt`, `cdnGrants` or `autoRun`.
3. Right-click a snippet → Export… and a sidebar collection → Export collection… each save a file.
4. Select mode → select 2 items → export (2) saves a file.
5. Import the library file back → the conflict alert appears; Skip + Apply to all → toast "Imported 0 snippets · N skipped"; snippet count unchanged.

AppStore build (sandboxed, empty container):
6. Import the Desktop file → toast "Imported N snippets"; collections nested, media visible, connections and saved preview configs present.
7. Re-import → Replace on one, Stop on the next → toast "Import stopped after 0 snippets · …"; nothing duplicated.
8. Double-click a `.snippets` file in Finder while the app runs → it imports. Confirm no extra empty window appears; if one does, add `.handlesExternalEvents(matching: [])` to the main `WindowGroup` and re-check.
9. Export from the AppStore build to the Desktop succeeds (read-write entitlement).

- [ ] **Step 12: Docs**

In `README.md`, after the "Clipboard capture" section, add:

```markdown
### Import and export

File ▸ Export Library… (⇧⌘E) writes every snippet outside Trash to one
`.snippets` file — collections, connections, saved preview configs and media
included. Export collection… (sidebar), Export… (snippet menu) and export in
select mode write just those. File ▸ Import Snippets… (⇧⌘I), or opening a
`.snippets` file, brings one in; a snippet already in the library asks Skip,
Replace or Stop, with Apply to all. Preview permissions are never exported,
and a replaced snippet loses its own. This is also how to move a library into
the sandboxed App Store build, whose container starts empty.
```

In `plans/017-snippet-import-export-design.md`: under Architecture, replace the `SnippetImporter.swift` row's text with `apply(_:to:resolve:) async throws -> ImportSummary` (planning folded into apply); replace the `Views/Transfer/ImportConflictDialog.swift` row with "conflict prompt: an `NSAlert` in `SnippetTransferController` (suppression checkbox = Apply to all; Skip default, Escape = Stop)"; change "registered as an Editor document type" to "registered as a Viewer document type"; mark Status "implemented".

- [ ] **Step 13: Commit**

```bash
git add Sources Snippets-Info.plist Snippets-AppStore.entitlements Snippets.xcodeproj README.md plans/017-snippet-import-export-design.md
git commit -m "Add import and export to menus, context menus and Finder open

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

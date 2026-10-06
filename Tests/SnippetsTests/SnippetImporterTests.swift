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

    // MARK: Atomicity

    private struct DiskFull: Error {}

    private func png(_ byte: UInt8 = 1) -> SnippetArchive.MediaRecord {
        .init(kind: "image", fileExtension: "png", addedAt: t, data: Data([byte]))
    }

    func test_replace_whoseMediaWriteFails_throws_andLeavesTheLibraryAsItWas() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let id = UUID(); let forgotten = Recorder<UUID>()
        let local = seed(context, media, id: id)
        let oldFile = local.mediaItems[0].fileName
        try context.save()
        let failing = SnippetImporter(
            writeMedia: { _, _ in throw DiskFull() },
            removeMedia: { name in media.removed.append(name); media.files[name] = nil },
            forgetTrust: { forgotten.values.append($0) }
        )

        do {
            _ = try await failing.apply(archive([record(id, media: [png()])]), to: context) { _ in
                ConflictResolution(choice: .replace, applyToAll: false)
            }
            XCTFail("the write error must abort the import")
        } catch is DiskFull {}

        XCTAssertEqual(local.title, "Local")
        XCTAssertEqual(local.code, "local")
        XCTAssertEqual(local.mediaItems.map(\.fileName), [oldFile])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 1)
        XCTAssertNotNil(media.files[oldFile])
        XCTAssertTrue(media.removed.isEmpty, "nothing was written, and old files are never removed before a save")
        XCTAssertTrue(forgotten.values.isEmpty, "trust is only dropped once the replacement is saved")
    }

    func test_laterWriteFailure_removesEarlierFiles_andDropsEarlierSnippets() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let forgotten = Recorder<UUID>()
        let calls = Recorder<String>()
        let flaky = SnippetImporter(
            writeMedia: { data, ext in
                if !calls.values.isEmpty { throw DiskFull() }
                let name = media.write(data, ext: ext)
                calls.values.append(name)
                return name
            },
            removeMedia: { name in media.removed.append(name); media.files[name] = nil },
            forgetTrust: { forgotten.values.append($0) }
        )

        do {
            _ = try await flaky.apply(
                archive([record(title: "first", media: [png(1)]), record(title: "second", media: [png(2)])]),
                to: context, resolve: never)
            XCTFail("the write error must abort the import")
        } catch is DiskFull {}

        XCTAssertEqual(calls.values.count, 1)
        XCTAssertEqual(media.removed, calls.values, "the file written for the first snippet is cleaned up")
        XCTAssertTrue(media.files.isEmpty)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Snippet>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<MediaItem>()), 0)
    }

    func test_autosaveIsOffWhileResolving_andRestoredAfter() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let id = UUID()
        seed(context, media, id: id)
        try context.save()
        context.autosaveEnabled = true
        let during = Recorder<Bool>()

        _ = try await importer(media).apply(archive([record(id)]), to: context) { _ in
            during.values.append(context.autosaveEnabled)
            return ConflictResolution(choice: .skip, applyToAll: false)
        }

        XCTAssertEqual(during.values, [false])
        XCTAssertTrue(context.autosaveEnabled)
    }

    func test_forgetTrust_isOnlyCalledForReplacedSnippets() async throws {
        let container = try makeContainer(); let context = container.mainContext
        let media = MediaStore(); let skippedID = UUID(); let replacedID = UUID()
        let forgotten = Recorder<UUID>()
        seed(context, media, id: skippedID); seed(context, media, id: replacedID)
        try context.save()

        _ = try await importer(media, forgotten: forgotten).apply(
            archive([record(title: "new"), record(skippedID), record(replacedID)]), to: context
        ) { conflict in
            ConflictResolution(choice: conflict.id == replacedID ? .replace : .skip, applyToAll: false)
        }

        XCTAssertEqual(forgotten.values, [replacedID])
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

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

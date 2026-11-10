import SwiftData
import XCTest
@testable import Snippets

/// A store written by an earlier build must still open. `Fixtures/store-v1`
/// was written at commit 7ee6c483; if a model change makes this fail, the
/// change needs a migration before it can ship — existing users' libraries
/// would not open either.
@MainActor
final class StoreMigrationTests: XCTestCase {
    private static var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/store-v1")
    }

    private static let schema = Schema([Snippet.self, MediaItem.self, SnippetCollection.self])

    private static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 700_000_000 + seconds)
    }

    /// Run once by hand to (re)write the fixture; skipped otherwise.
    func test_writeFixture() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SNIPPETS_WRITE_STORE_FIXTURE"] == "1")
        let directory = Self.fixtureDirectory
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let container = try Self.container(at: directory.appending(path: "Snippets.store"))
        let context = container.mainContext

        let parent = SnippetCollection(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1"),
            name: "Parent", createdAt: date(1), updatedAt: date(1))
        let child = SnippetCollection(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2"),
            name: "Child", createdAt: date(2), updatedAt: date(2), parent: parent)
        let helper = Snippet(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-0000000000B1"),
            title: "Helper", language: "JavaScript", code: "export const helper = 1",
            createdAt: date(3), updatedAt: date(3))
        let entry = Snippet(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2"),
            title: "Entry", language: "React", code: "export default function Entry() { return null }",
            createdAt: date(4), updatedAt: date(4), copyCount: 3, isFavorite: true,
            mediaItems: [MediaItem(fileName: "fixture.png", kind: .image, addedAt: date(5))],
            collections: [child])
        let trashed = Snippet(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-0000000000B3"),
            title: "Trashed", language: "JavaScript", code: "// gone",
            createdAt: date(6), updatedAt: date(6), deletedAt: date(7))

        context.insert(parent)
        context.insert(child)
        context.insert(helper)
        context.insert(entry)
        context.insert(trashed)
        entry.dependencies = [helper]
        try context.save()
    }

    func test_fixtureFromEarlierBuild_opensWithCurrentModels() throws {
        let fm = FileManager.default
        let copy = fm.temporaryDirectory.appending(path: "store-v1-\(UUID().uuidString)")
        try fm.createDirectory(at: copy, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: copy) }
        // Never open the committed files in place — opening mutates them.
        for name in try fm.contentsOfDirectory(atPath: Self.fixtureDirectory.path) {
            try fm.copyItem(at: Self.fixtureDirectory.appending(path: name), to: copy.appending(path: name))
        }

        let container = try Self.container(at: copy.appending(path: "Snippets.store"))
        let context = container.mainContext
        let snippets = try context.fetch(FetchDescriptor<Snippet>())
        let collections = try context.fetch(FetchDescriptor<SnippetCollection>())
        let media = try context.fetch(FetchDescriptor<MediaItem>())
        XCTAssertEqual(snippets.count, 3)
        XCTAssertEqual(collections.count, 2)
        XCTAssertEqual(media.count, 1)

        let entry = try XCTUnwrap(snippets.first { $0.title == "Entry" })
        XCTAssertEqual(entry.dependencies.map(\.title), ["Helper"])
        XCTAssertTrue(entry.isFavorite)
        XCTAssertEqual(entry.copyCount, 3)
        XCTAssertEqual(entry.collections.map(\.name), ["Child"])
        XCTAssertEqual(entry.collections.first?.parent?.name, "Parent")
        let trashed = try XCTUnwrap(snippets.first { $0.title == "Trashed" })
        XCTAssertNotNil(trashed.deletedAt)
    }
}

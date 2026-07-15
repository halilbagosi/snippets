import SwiftData
import XCTest
@testable import Snippets

@MainActor
final class TrashLifecycleTests: XCTestCase {
    // Returns the container: the context alone does not keep it alive, and
    // inserting into a context whose container was deallocated traps.
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: .now)!
    }

    private var cutoff: Date { daysAgo(30) }

    func test_cleanup_purgesExpiredSnippet_keepsRecentOne() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = Snippet(title: "Old", code: "a", deletedAt: daysAgo(31))
        let recent = Snippet(title: "New", code: "b", deletedAt: daysAgo(29))
        context.insert(expired)
        context.insert(recent)
        try context.save()

        try TrashLifecycle.cleanup(snippets: [expired, recent], collections: [], cutoff: cutoff, context: context)

        let remaining = try context.fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(remaining.map(\.title), ["New"])
    }

    func test_cleanup_purgesExpiredCollection_keepsRecentOne() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = SnippetCollection(name: "Old", deletedAt: daysAgo(31))
        let recent = SnippetCollection(name: "New", deletedAt: daysAgo(29))
        context.insert(expired)
        context.insert(recent)
        try context.save()

        try TrashLifecycle.cleanup(snippets: [], collections: [expired, recent], cutoff: cutoff, context: context)

        let remaining = try context.fetch(FetchDescriptor<SnippetCollection>())
        XCTAssertEqual(remaining.map(\.name), ["New"])
    }

    func test_cleanup_expiredCollection_keepsLiveMemberSnippets_andUnlinksThem() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = SnippetCollection(name: "Old", deletedAt: daysAgo(31))
        let member = Snippet(title: "Live", code: "a")
        context.insert(expired)
        context.insert(member)
        member.collections = [expired]
        try context.save()

        try TrashLifecycle.cleanup(snippets: [], collections: [expired], cutoff: cutoff, context: context)

        let snippets = try context.fetch(FetchDescriptor<Snippet>())
        XCTAssertEqual(snippets.map(\.title), ["Live"])
        XCTAssertTrue(snippets[0].collections.isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<SnippetCollection>()).isEmpty)
    }

    func test_purgeSnippet_removesModel() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let snippet = Snippet(title: "Gone", code: "a", deletedAt: daysAgo(31))
        context.insert(snippet)
        try context.save()

        // MediaManager file deletion is a static call and not injectable, so
        // disk-side effects are not asserted here.
        TrashLifecycle.purgeSnippet(snippet, context: context)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<Snippet>()).isEmpty)
    }

    // A failing save is hard to trigger with an in-memory store; error
    // propagation is covered by `cleanup`'s throwing signature (`try
    // context.save()` is rethrown to the caller, verified at compile time).
    func test_cleanup_withNothingExpired_savesWithoutError() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let recent = Snippet(title: "New", code: "b", deletedAt: daysAgo(1))
        context.insert(recent)
        try context.save()

        XCTAssertNoThrow(
            try TrashLifecycle.cleanup(snippets: [recent], collections: [], cutoff: cutoff, context: context)
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<Snippet>()).count, 1)
    }
}

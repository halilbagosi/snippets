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

    // `PreviewTrust` persists CDN grants to real user defaults, so a test that
    // grants one must clear it or it leaks into the next suite.
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "settings.preview.cdnGrants")
        super.tearDown()
    }

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

    // MARK: Preview consent

    /// The expiry sweep must drop preview consent for exactly the snippets it
    /// purged — and for no one else, or a survivor silently loses a grant.
    func test_cleanup_forgetsTrustForPurgedSnippetOnly() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = Snippet(title: "Old", code: "a", deletedAt: daysAgo(31))
        let recent = Snippet(title: "New", code: "b", deletedAt: daysAgo(29))
        context.insert(expired)
        context.insert(recent)
        try context.save()
        let expiredID = expired.uuid
        XCTAssertNotNil(expiredID)

        var forgotten: [UUID?] = []
        try TrashLifecycle.cleanup(
            snippets: [expired, recent],
            collections: [],
            cutoff: cutoff,
            context: context,
            forgetTrust: { forgotten.append($0) }
        )

        XCTAssertEqual(forgotten.count, 1)
        XCTAssertEqual(forgotten.first ?? nil, expiredID)
    }

    /// The permanent-collection-delete path goes through `purgeSnippet`
    /// directly, so it needs its own coverage.
    func test_purgeSnippet_forgetsTrustForThatSnippet() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let snippet = Snippet(title: "Gone", code: "a")
        context.insert(snippet)
        try context.save()
        let id = snippet.uuid

        var forgotten: [UUID?] = []
        TrashLifecycle.purgeSnippet(snippet, context: context, forgetTrust: { forgotten.append($0) })
        try context.save()

        XCTAssertEqual(forgotten, [id])
        XCTAssertTrue(try context.fetch(FetchDescriptor<Snippet>()).isEmpty)
    }

    /// End to end with the real consent object: the point of the callback is
    /// that a purged snippet stops being allowed to reach the network.
    func test_cleanup_withPreviewTrust_dropsPersistedCDNGrant() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let expired = Snippet(title: "Old", code: "a", deletedAt: daysAgo(31))
        context.insert(expired)
        try context.save()
        let id = expired.uuid

        let trust = PreviewTrust()
        trust.setCDNModulesAllowed(true, for: id)
        XCTAssertTrue(trust.allowsCDNModules(id))

        try TrashLifecycle.cleanup(
            snippets: [expired],
            collections: [],
            cutoff: cutoff,
            context: context,
            forgetTrust: { trust.forget($0) }
        )

        XCTAssertFalse(trust.allowsCDNModules(id))
        XCTAssertFalse(PreviewTrust().allowsCDNModules(id))
    }
}

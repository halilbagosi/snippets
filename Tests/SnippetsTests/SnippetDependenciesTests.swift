import XCTest
import SwiftData
@testable import Snippets

final class SnippetDependenciesTests: XCTestCase {
    @MainActor
    func test_dependenciesRelationship_persistsAndInverses() throws {
        let container = try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let css = Snippet(title: "Theme", language: "CSS", code: ".a{}")
        let entry = Snippet(title: "Card", language: "React", code: "export default function App(){}")
        context.insert(css)
        context.insert(entry)
        entry.dependencies = [css]
        try context.save()

        XCTAssertEqual(entry.dependencies.map(\.title), ["Theme"])
        XCTAssertEqual(css.dependents.map(\.title), ["Card"])
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @MainActor
    func test_uuidsRunningThisCode_selfFirst_thenAllDependentsAtAnyDepth() throws {
        let container = try makeContainer(); let context = container.mainContext
        let c = Snippet(uuid: UUID(), title: "C"), b = Snippet(uuid: UUID(), title: "B")
        let a = Snippet(uuid: UUID(), title: "A"), unrelated = Snippet(uuid: UUID(), title: "U")
        [c, b, a, unrelated].forEach(context.insert)
        b.dependencies = [c]; a.dependencies = [b]
        try context.save()

        let ids = c.uuidsRunningThisCode
        XCTAssertEqual(ids.first, c.uuid)
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids), [c.uuid!, b.uuid!, a.uuid!])
        XCTAssertFalse(ids.contains(unrelated.uuid!))
    }

    @MainActor
    func test_uuidsRunningThisCode_cycle_terminates_eachOnce() throws {
        let container = try makeContainer(); let context = container.mainContext
        let a = Snippet(uuid: UUID(), title: "A"), b = Snippet(uuid: UUID(), title: "B")
        [a, b].forEach(context.insert)
        a.dependencies = [b]; b.dependencies = [a]
        try context.save()

        XCTAssertEqual(a.uuidsRunningThisCode.count, 2)
    }

    @MainActor
    func test_uuidsRunningThisCode_includesAndWalksThroughTrashed() throws {
        let container = try makeContainer(); let context = container.mainContext
        let c = Snippet(uuid: UUID(), title: "C")
        let b = Snippet(uuid: UUID(), title: "B", deletedAt: Date())
        let a = Snippet(uuid: UUID(), title: "A")
        [c, b, a].forEach(context.insert)
        b.dependencies = [c]; a.dependencies = [b]
        try context.save()

        XCTAssertEqual(Set(c.uuidsRunningThisCode), [c.uuid!, b.uuid!, a.uuid!])
    }

    @MainActor
    func test_uuidsRunningThisCode_withoutUUID_skipsOnlyThatSnippet() throws {
        let container = try makeContainer(); let context = container.mainContext
        let c = Snippet(uuid: UUID(), title: "C")
        let b = Snippet(uuid: nil, title: "B")
        let a = Snippet(uuid: UUID(), title: "A")
        [c, b, a].forEach(context.insert)
        b.dependencies = [c]; a.dependencies = [b]
        try context.save()

        XCTAssertEqual(Set(c.uuidsRunningThisCode), [c.uuid!, a.uuid!])
    }
}

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

    // MARK: - Connection groups

    @MainActor
    func test_connectionsOfOneSnippet_haveAccessToEachOther() throws {
        let container = try makeContainer(); let context = container.mainContext
        let app = Snippet(title: "App", language: "React"), button = Snippet(title: "Button", language: "React")
        let theme = Snippet(title: "Theme", language: "CSS"), unrelated = Snippet(title: "U", language: "CSS")
        [app, button, theme, unrelated].forEach(context.insert)
        app.dependencies = [button, theme]
        try context.save()

        XCTAssertEqual(button.effectiveConnections.map(\.title), ["Theme"])
        XCTAssertEqual(theme.effectiveConnections.map(\.title), ["Button"])
        // SwiftData does not keep to-many order, so compare as a set.
        XCTAssertEqual(Set(app.effectiveConnections.map(\.title)), ["Button", "Theme"])
        // Button's combined preview now carries Theme as a helper.
        XCTAssertEqual(SnippetLinker.resolve(entry: button).sources.map(\.language), [.css, .react])
        XCTAssertTrue(unrelated.effectiveConnections.isEmpty)
    }

    @MainActor
    func test_siblings_skipTrashedParentsAndSiblings() throws {
        let container = try makeContainer(); let context = container.mainContext
        let parent = Snippet(title: "P"), a = Snippet(title: "A"), b = Snippet(title: "B")
        let trashedSibling = Snippet(title: "T", deletedAt: .now)
        [parent, a, b, trashedSibling].forEach(context.insert)
        parent.dependencies = [a, b, trashedSibling]
        try context.save()

        XCTAssertEqual(a.siblingConnections().map(\.title), ["B"])
        parent.deletedAt = .now
        XCTAssertTrue(a.siblingConnections().isEmpty)
        XCTAssertEqual(Set(a.siblingConnections(includingTrashed: true).map(\.title)), ["B", "T"])
    }

    @MainActor
    func test_uuidsRunningThisCode_includesSiblings() throws {
        let container = try makeContainer(); let context = container.mainContext
        let parent = Snippet(uuid: UUID(), title: "P"), a = Snippet(uuid: UUID(), title: "A")
        let b = Snippet(uuid: UUID(), title: "B")
        [parent, a, b].forEach(context.insert)
        parent.dependencies = [a, b]
        try context.save()

        XCTAssertEqual(Set(a.uuidsRunningThisCode), [a.uuid!, parent.uuid!, b.uuid!])
    }

    @MainActor
    func test_connectedClosure_isLiveAndExcludesSelf() throws {
        let container = try makeContainer(); let context = container.mainContext
        let entry = Snippet(title: "E"), helper = Snippet(title: "H"), deep = Snippet(title: "D")
        let trashed = Snippet(title: "T", deletedAt: .now)
        [entry, helper, deep, trashed].forEach(context.insert)
        entry.dependencies = [helper, trashed]
        helper.dependencies = [deep]
        try context.save()

        XCTAssertEqual(Set(entry.connectedClosure.map(\.title)), ["H", "D"])
        XCTAssertEqual(Set(ContentView.withConnections([entry]).map(\.title)), ["E", "H", "D"])
    }

    @MainActor
    func test_editorSave_putsConnectionsInNewlyAddedCollections() throws {
        let container = try makeContainer(); let context = container.mainContext
        let entry = Snippet(title: "E"), helper = Snippet(title: "H")
        let folder = SnippetCollection(name: "Folder")
        [entry, helper].forEach(context.insert); context.insert(folder)
        entry.dependencies = [helper]
        try context.save()

        SnippetEditorViewModel.placeConnections(of: entry, in: [folder])
        XCTAssertEqual(helper.collections.map(\.name), ["Folder"])
        SnippetEditorViewModel.placeConnections(of: entry, in: [folder])
        XCTAssertEqual(helper.collections.count, 1)
    }
}

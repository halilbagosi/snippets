import SwiftData
import XCTest
@testable import Snippets

@MainActor
final class SnippetEditorViewModelTests: XCTestCase {
    func test_canSave_whenRequiredFieldsAreMissing_returnsFalse() {
        let sut = SnippetEditorViewModel()

        XCTAssertFalse(sut.canSave)

        sut.title = "Parser"
        XCTAssertFalse(sut.canSave)

        sut.code = "func parse() {}"
        XCTAssertTrue(sut.canSave)
    }

    func test_headerFilename_whenTitleAndLanguageAreSet_returnsSanitizedFilename() {
        let sut = SnippetEditorViewModel()
        sut.title = "Hello Swift!"
        sut.selectManualLanguage(.swift)

        XCTAssertEqual(sut.headerFilename(isEditing: false), "hello-swift.swift")
    }

    // Returns the container: the context alone does not keep it alive, and
    // inserting into a context whose container was deallocated traps.
    private func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Snippet.self, MediaItem.self, SnippetCollection.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    func test_load_editMode_populatesDependencies() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let theme = Snippet(title: "Theme", language: "CSS", code: ".a{}")
        let entry = Snippet(title: "Card", language: "React", code: "c")
        context.insert(theme)
        context.insert(entry)
        entry.dependencies = [theme]
        try context.save()

        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(entry))

        XCTAssertEqual(sut.dependencies.map(\.title), ["Theme"])
    }

    func test_save_editMode_persistsDependencyChanges() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let theme = Snippet(title: "Theme", language: "CSS", code: ".a{}")
        let entry = Snippet(title: "Card", language: "React", code: "c")
        context.insert(theme)
        context.insert(entry)
        try context.save()

        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(entry))
        sut.addDependency(theme)
        XCTAssertTrue(sut.save(mode: .edit(entry), availableCollections: [], modelContext: context, onSave: { _ in }))

        XCTAssertEqual(entry.dependencies.map(\.title), ["Theme"])

        sut.removeDependency(theme)
        XCTAssertTrue(sut.save(mode: .edit(entry), availableCollections: [], modelContext: context, onSave: { _ in }))
        XCTAssertTrue(entry.dependencies.isEmpty)
    }

    func test_isDependencyCandidate_excludesSelfAndExisting() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let entry = Snippet(title: "Card", language: "React", code: "c")
        let dep = Snippet(title: "Theme", language: "CSS", code: ".a{}")
        let other = Snippet(title: "Utils", language: "JavaScript", code: "u")
        context.insert(entry)
        context.insert(dep)
        context.insert(other)
        try context.save()

        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(entry))
        sut.addDependency(dep)

        XCTAssertFalse(sut.isDependencyCandidate(entry, mode: .edit(entry)))
        XCTAssertFalse(sut.isDependencyCandidate(dep, mode: .edit(entry)))
        XCTAssertTrue(sut.isDependencyCandidate(other, mode: .edit(entry)))
    }

    func test_load_whenEditingSnippet_populatesFormState() {
        let snippet = Snippet(
            title: "Python Helper",
            snippetDescription: "Small helper",
            language: SupportedLanguage.python.rawValue,
            code: "print('hello')"
        )
        let sut = SnippetEditorViewModel()

        sut.load(mode: .edit(snippet))

        XCTAssertEqual(sut.title, "Python Helper")
        XCTAssertEqual(sut.snippetDescription, "Small helper")
        XCTAssertEqual(sut.code, "print('hello')")
        XCTAssertEqual(sut.effectiveLanguage, .python)
    }

    func test_toggleCollection_whenCollectionIsUnselected_selectsIt() {
        let collection = SnippetCollection(name: "Utilities")
        let sut = SnippetEditorViewModel()

        sut.toggleCollection(collection)

        XCTAssertTrue(sut.selectedCollectionIDs.contains(collection.persistentModelID))
    }
}

import SwiftData
import UniformTypeIdentifiers
import XCTest
@testable import Snippets

private final class FakeMediaManager: MediaManaging {
    var toImport: [MediaItem] = []
    private(set) var deleted: [String] = []
    var allowedTypes: [UTType] { [] }
    func resolvedURL(for fileName: String) -> URL { URL(fileURLWithPath: "/dev/null/\(fileName)") }
    func kind(for url: URL) -> MediaKind { .image }
    func pickAndImport() -> [MediaItem] { toImport }
    func deleteFile(for item: MediaItem) { deleted.append(item.fileName) }
}

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

    // MARK: - Attachment changes apply on save

    private func makeSnippetWithSavedMedia(
        in context: ModelContext
    ) throws -> (snippet: Snippet, media: MediaItem) {
        let snippet = Snippet(title: "Card", language: "React", code: "c")
        let media = MediaItem(fileName: "saved.png", kind: .image)
        context.insert(snippet)
        context.insert(media)
        media.snippet = snippet
        snippet.mediaItems = [media]
        try context.save()
        return (snippet, media)
    }

    func test_removeSavedAttachment_thenDiscard_deletesNoFile() throws {
        let container = try makeInMemoryContainer()
        let (snippet, media) = try makeSnippetWithSavedMedia(in: container.mainContext)
        let fake = FakeMediaManager()
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))

        sut.removeMediaItem(media, using: fake)
        sut.discardMediaChanges(using: fake)

        XCTAssertTrue(fake.deleted.isEmpty)
    }

    func test_removeSavedAttachment_thenSaveAndCommit_deletesItsFile() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (snippet, media) = try makeSnippetWithSavedMedia(in: context)
        let name = media.fileName
        let fake = FakeMediaManager()
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))

        sut.removeMediaItem(media, using: fake)
        XCTAssertTrue(sut.save(mode: .edit(snippet), availableCollections: [], modelContext: context, onSave: { _ in }))
        sut.commitMediaChanges(using: fake)

        XCTAssertEqual(fake.deleted, [name])
    }

    func test_removeSavedAttachment_beforeCommit_deletesNoFile() throws {
        let container = try makeInMemoryContainer()
        let (snippet, media) = try makeSnippetWithSavedMedia(in: container.mainContext)
        let fake = FakeMediaManager()
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))

        sut.removeMediaItem(media, using: fake)

        XCTAssertTrue(fake.deleted.isEmpty)
    }

    func test_attach_thenDiscard_deletesTheNewFile() throws {
        let container = try makeInMemoryContainer()
        let (snippet, _) = try makeSnippetWithSavedMedia(in: container.mainContext)
        let fake = FakeMediaManager()
        fake.toImport = [MediaItem(fileName: "new.png", kind: .image)]
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))

        sut.attachMedia(using: fake)
        sut.discardMediaChanges(using: fake)

        XCTAssertEqual(fake.deleted, ["new.png"])
    }

    func test_attach_thenRemove_deletesTheNewFileOnce_andDiscardDeletesNothingMore() throws {
        let container = try makeInMemoryContainer()
        let (snippet, _) = try makeSnippetWithSavedMedia(in: container.mainContext)
        let fake = FakeMediaManager()
        let added = MediaItem(fileName: "new.png", kind: .image)
        fake.toImport = [added]
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))

        sut.attachMedia(using: fake)
        sut.removeMediaItem(added, using: fake)
        XCTAssertEqual(fake.deleted, ["new.png"])

        sut.discardMediaChanges(using: fake)
        XCTAssertEqual(fake.deleted, ["new.png"])
    }

    func test_attach_thenSaveAndCommit_keepsTheNewFile() throws {
        let container = try makeInMemoryContainer()
        let context = container.mainContext
        let (snippet, _) = try makeSnippetWithSavedMedia(in: context)
        let fake = FakeMediaManager()
        fake.toImport = [MediaItem(fileName: "new.png", kind: .image)]
        let sut = SnippetEditorViewModel()
        sut.load(mode: .edit(snippet))

        sut.attachMedia(using: fake)
        XCTAssertTrue(sut.save(mode: .edit(snippet), availableCollections: [], modelContext: context, onSave: { _ in }))
        sut.commitMediaChanges(using: fake)
        sut.discardMediaChanges(using: fake)

        XCTAssertTrue(fake.deleted.isEmpty)
        XCTAssertEqual(snippet.mediaItems.map(\.fileName).sorted(), ["new.png", "saved.png"])
    }
}

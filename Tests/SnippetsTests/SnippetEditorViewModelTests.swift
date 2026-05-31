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

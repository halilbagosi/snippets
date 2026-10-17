import XCTest
@testable import Snippets

/// The plain-text EULA and third-party notices, parsed into the blocks their
/// windows typeset.
final class LegalDocumentTests: XCTestCase {

    private func bundled(_ name: String) throws -> String {
        let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "txt"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: LegalDocument

    func test_parsesTitleHeadingsParagraphsAndLists() {
        let document = LegalDocument(text: """
            SOME AGREEMENT

            Copyright (c) 2026 Someone.

            1. YOUR CODE AND CONTENT

            You may not, except where
            the law permits it:

              a. copy the App;
              b. modify, translate or create
                 derivative works of the App;

            Sharing a link is
            always allowed.
            """)

        XCTAssertEqual(document.title, "Some Agreement")
        XCTAssertEqual(document.blocks, [
            .copyright("Copyright (c) 2026 Someone."),
            .heading("1. Your Code and Content"),
            .paragraph("You may not, except where the law permits it:"),
            .listItem(marker: "a.", text: "copy the App;"),
            .listItem(marker: "b.", text: "modify, translate or create derivative works of the App;"),
            .paragraph("Sharing a link is always allowed."),
        ])
    }

    func test_titleCasing_keepsMinorWordsLowerAndMixedCaseUntouched() {
        XCTAssertEqual(LegalDocument.titleCased("THIRD-PARTY COMPONENTS AND PACKAGES"), "Third-Party Components and Packages")
        XCTAssertEqual(LegalDocument.titleCased("THE END"), "The End")
        XCTAssertEqual(LegalDocument.titleCased("Already Mixed"), "Already Mixed")
    }

    func test_bundledEULA_hasElevenSectionsAndNoHardWraps() throws {
        let document = LegalDocument(text: try bundled("EULA"))

        XCTAssertEqual(document.title, "Snippets End User License Agreement")
        let headings = document.blocks.compactMap { if case .heading(let text) = $0 { text } else { nil } }
        XCTAssertEqual(headings.count, 11)
        XCTAssertEqual(headings.first, "1. Licence")
        XCTAssertEqual(document.blocks.filter { if case .listItem = $0 { true } else { false } }.count, 5)
        for block in document.blocks {
            if case .paragraph(let text) = block { XCTAssertFalse(text.contains("\n")) }
        }
    }

    // MARK: ThirdPartyNotices

    func test_bundledNotices_splitIntoComponents() throws {
        let notices = ThirdPartyNotices(text: try bundled("ThirdPartyNotices"))

        XCTAssertEqual(notices.introduction.title, "Third-Party Notices")
        XCTAssertFalse(notices.introduction.blocks.isEmpty)
        XCTAssertEqual(notices.components.count, 6)
        for component in notices.components {
            XCTAssertNotNil(component.url, component.name)
            XCTAssertFalse(component.copyright.isEmpty, component.name)
            XCTAssertEqual(component.licenseName, "MIT License", component.name)
            XCTAssertEqual(component.licenseParagraphs.count, 3, component.name)
        }

        let popper = try XCTUnwrap(notices.components.last)
        XCTAssertEqual(popper.name, "Popper 2")
        XCTAssertEqual(popper.note, "Included in bootstrap.bundle.min.js")
        XCTAssertEqual(popper.url, URL(string: "https://github.com/floating-ui/floating-ui"))
        XCTAssertEqual(popper.copyright, ["Copyright (c) 2019 Federico Zivolo"])
    }

    func test_splitNote_leavesNamesWithoutParentheticalAlone() {
        XCTAssertEqual(ThirdPartyNotices.splitNote("Bootstrap 5.3.8").0, "Bootstrap 5.3.8")
        XCTAssertNil(ThirdPartyNotices.splitNote("Bootstrap 5.3.8").1)
    }
}

import XCTest
@testable import Snippets

final class SwiftPreviewHarnessTests: XCTestCase {
    func test_picksFirstViewStruct() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Helper {}
        struct Badge: View { var body: some View { Text("hi") } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Badge())"))
    }

    func test_prefersContentViewOverOtherViewStructs() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Badge: View { var body: some View { Text("b") } }
        struct ContentView: View { var body: some View { Badge() } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: ContentView())"))
    }

    func test_prefersPreviewAboveAll() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct ContentView: View { var body: some View { Text("c") } }
        struct Preview: View { var body: some View { ContentView() } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Preview())"))
    }

    func test_handlesViewAmongMultipleConformances() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Badge : Equatable, View { var body: some View { Text("b") } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Badge())"))
    }

    func test_injectsImportsWhenMissing() throws {
        let harness = try SwiftPreviewHarness.make(
            code: "struct A: View { var body: some View { Text(\"a\") } }"
        )
        XCTAssertTrue(harness.source.contains("import SwiftUI"))
        XCTAssertTrue(harness.source.contains("import AppKit"))
    }

    func test_doesNotDuplicateExistingImport() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        import SwiftUI
        struct A: View { var body: some View { Text("a") } }
        """)
        XCTAssertEqual(harness.source.components(separatedBy: "import SwiftUI").count - 1, 1)
    }

    func test_symbolNameIsHashSuffixedAndDeterministic() throws {
        let code = "struct A: View { var body: some View { Text(\"a\") } }"
        let first = try SwiftPreviewHarness.make(code: code)
        let second = try SwiftPreviewHarness.make(code: code)
        let other = try SwiftPreviewHarness.make(
            code: "struct B: View { var body: some View { Text(\"b\") } }"
        )
        XCTAssertEqual(first.symbolName, second.symbolName)
        XCTAssertNotEqual(first.symbolName, other.symbolName)
        XCTAssertTrue(first.symbolName.range(of: #"^snippet_make_view_[0-9a-f]{8}$"#, options: .regularExpression) != nil)
        XCTAssertTrue(first.source.contains("@_cdecl(\"\(first.symbolName)\")"))
    }

    func test_helpers_areConcatenatedBeforeEntry_andRootComesFromEntry() throws {
        let harness = try SwiftPreviewHarness.make(
            entry: "struct Card: View { var body: some View { Text(Model.name) } }",
            helpers: ["struct ContentView: View { var body: some View { Text(\"helper\") } }",
                      "enum Model { static let name = \"m\" }"]
        )
        // Root selection must ignore the helper's ContentView.
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Card())"))
        XCTAssertLessThan(harness.source.range(of: "enum Model")!.lowerBound,
                          harness.source.range(of: "struct Card")!.lowerBound)
    }

    func test_helpers_changeTheHashAndSymbol() throws {
        let entry = "struct A: View { var body: some View { Text(\"a\") } }"
        let alone = try SwiftPreviewHarness.make(entry: entry, helpers: [])
        let with = try SwiftPreviewHarness.make(entry: entry, helpers: ["enum K {}"])
        XCTAssertNotEqual(alone.symbolName, with.symbolName)
    }

    func test_codeWithoutViewStruct_throwsDescriptiveError() {
        XCTAssertThrowsError(try SwiftPreviewHarness.make(code: "let x = 42")) { error in
            XCTAssertTrue(error.localizedDescription.contains("View"))
        }
    }
}

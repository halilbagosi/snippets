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

    func test_findsGenericViewStruct() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Marquee<Content: View>: View {
            var body: some View { Text("m") }
        }
        struct Preview: View { var body: some View { Marquee<Text>() } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Preview())"))
    }

    func test_genericOnlyView_throwsActionableWrapperGuidance() {
        // `Badge()` can't infer S, so picking it would fail with an opaque
        // compiler diagnostic — the harness must explain the wrapper pattern.
        XCTAssertThrowsError(try SwiftPreviewHarness.make(code: """
        struct Badge<S: StringProtocol>: View { var body: some View { Text("b") } }
        """)) { error in
            XCTAssertTrue(error.localizedDescription.contains("generic"))
            XCTAssertTrue(error.localizedDescription.contains("Badge"))
        }
    }

    func test_findsViewConformanceDeclaredInExtension() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Gauge { let value: Double = 0.5 }
        extension Gauge: View { var body: some View { Text("g") } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Gauge())"))
    }

    func test_prefersUnreferencedViewOverInstantiatedSubcomponent() throws {
        // Row needs init arguments; the composed List below is the real root.
        let harness = try SwiftPreviewHarness.make(code: """
        struct Row: View {
            let title: String
            var body: some View { Text(title) }
        }
        struct DemoList: View { var body: some View { Row(title: "a") } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: DemoList())"))
    }

    func test_entryWithoutView_fallsBackToHelperView() throws {
        let harness = try SwiftPreviewHarness.make(
            entry: "extension Color { static let brand = Color.red }",
            helpers: ["struct Swatch: View { var body: some View { Color.brand } }"]
        )
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Swatch())"))
    }

    // MARK: #Preview blocks

    func test_previewMacro_becomesSynthesizedRootWithArguments() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct PaletteCell: View {
            let paletteName: String
            let colors: [Color]
            var body: some View { Text(paletteName) }
        }

        #Preview("6 colors") {
            PaletteCell(paletteName: "Summer", colors: [.red, .orange])
                .padding()
        }
        """)
        XCTAssertFalse(harness.source.contains("#Preview"), "macro needs Xcode's plugin — must be stripped")
        XCTAssertTrue(harness.source.contains("struct __SnippetPreviewRoot: View"))
        XCTAssertTrue(harness.source.contains("PaletteCell(paletteName: \"Summer\""))
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: __SnippetPreviewRoot())"))
    }

    func test_multiplePreviewMacros_allStripped_firstBodyWins() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Cell: View {
            let n: Int
            var body: some View { Text("\\(n)") }
        }
        #Preview("first") { Cell(n: 1) }
        #Preview("second") { Cell(n: 2) }
        """)
        XCTAssertFalse(harness.source.contains("#Preview"))
        XCTAssertTrue(harness.source.contains("Cell(n: 1)"))
        XCTAssertFalse(harness.source.contains("Cell(n: 2)"))
    }

    func test_previewMacro_withNestedClosuresAndStrings_stripsBalanced() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Row: View {
            let onCopy: () -> Void
            var body: some View { Text("{not a brace}") }
        }
        #Preview {
            Row(onCopy: { print("copied {}") })
        }
        """)
        XCTAssertFalse(harness.source.contains("#Preview"))
        XCTAssertTrue(harness.source.contains("Row(onCopy: { print(\"copied {}\") })"))
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: __SnippetPreviewRoot())"))
    }

    func test_previewMacroInHelper_isStrippedButNotRoot() throws {
        let harness = try SwiftPreviewHarness.make(
            entry: "struct Card: View { var body: some View { Text(\"c\") } }",
            helpers: ["struct Badge: View { var body: some View { Text(\"b\") } }\n#Preview { Badge() }"]
        )
        XCTAssertFalse(harness.source.contains("#Preview"))
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Card())"))
    }

    func test_entryPreviewMacro_outranksNamedViews() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct ContentView: View { var body: some View { Text("c") } }
        #Preview { ContentView().padding() }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: __SnippetPreviewRoot())"))
    }

    func test_codeWithoutViewStruct_throwsDescriptiveError() {
        XCTAssertThrowsError(try SwiftPreviewHarness.make(code: "let x = 42")) { error in
            XCTAssertTrue(error.localizedDescription.contains("View"))
        }
    }
}

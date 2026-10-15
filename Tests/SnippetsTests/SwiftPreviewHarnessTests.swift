#if !APP_STORE
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

    // MARK: Console mode

    func test_codeWithoutAnythingToRender_becomesConsoleProgram() throws {
        let harness = try SwiftPreviewHarness.make(code: "let x = 42\nprint(x)")
        XCTAssertEqual(harness.mode, .console(parseAsLibrary: false))
        XCTAssertTrue(harness.source.contains("print(x)"))
        XCTAssertFalse(harness.source.contains("NSHostingView"))
        XCTAssertNil(harness.rootName)
    }

    func test_consoleProgramWithMainAttribute_parsesAsLibrary() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        @main struct Tool { static func main() { print("hi") } }
        """)
        XCTAssertEqual(harness.mode, .console(parseAsLibrary: true))
    }

    func test_modelOnlyHelper_withoutView_isConsole() throws {
        // A connected model snippet previewed on its own has nothing to draw.
        let harness = try SwiftPreviewHarness.make(code: """
        import SwiftUI
        enum Palette { static let swatches: [Color] = [.pink, .orange] }
        """)
        XCTAssertEqual(harness.mode, .console(parseAsLibrary: false))
    }

    // MARK: Roots beyond plain View

    func test_viewRepresentable_isARootView() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct ColorWell: NSViewRepresentable {
            func makeNSView(context: Context) -> NSColorWell { NSColorWell() }
            func updateNSView(_ nsView: NSColorWell, context: Context) {}
        }
        """)
        XCTAssertEqual(harness.mode, .view)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: ColorWell())"))
    }

    func test_shape_isARootView() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Wave: Shape { func path(in rect: CGRect) -> Path { Path(rect) } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Wave())"))
    }

    func test_buttonStyle_isShownOnASampleButton() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct PressableStyle: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                configuration.label.scaleEffect(configuration.isPressed ? 0.96 : 1)
            }
        }
        """)
        XCTAssertEqual(harness.mode, .view)
        XCTAssertTrue(harness.source.contains(".buttonStyle(PressableStyle())"))
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: __SnippetPreviewRoot())"))
    }

    func test_toggleStyle_getsLiveToggleState() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Switch: ToggleStyle {
            func makeBody(configuration: Configuration) -> some View { configuration.label }
        }
        """)
        XCTAssertTrue(harness.source.contains(".toggleStyle(Switch())"))
        XCTAssertTrue(harness.source.contains("    @State var isOn = true"))
        XCTAssertFalse(harness.source.contains("@Previewable"))
    }

    func test_viewModifier_isAppliedToSampleText() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Glow: ViewModifier {
            func body(content: Content) -> some View { content.shadow(radius: 4) }
        }
        """)
        XCTAssertTrue(harness.source.contains(".modifier(Glow())"))
    }

    func test_viewThatUsesAStyle_outranksTheStyle() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Pressable: ButtonStyle {
            func makeBody(configuration: Configuration) -> some View { configuration.label }
        }
        struct Demo: View { var body: some View { Button("x") {}.buttonStyle(Pressable()) } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Demo())"))
    }

    // MARK: Comments and strings are not code

    func test_previewTokenInsideString_isNotAPreviewBlock() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct ContentView: View {
            var body: some View { Text("Use #Preview { } to preview") }
        }
        """)
        XCTAssertTrue(harness.source.contains("Text(\"Use #Preview { } to preview\")"))
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: ContentView())"))
    }

    func test_viewDeclaredOnlyInComment_isIgnored() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        // struct Preview: View { }
        /* struct ContentView: View { } */
        struct Real: View { var body: some View { Text("r") } }
        """)
        XCTAssertTrue(harness.source.contains("NSHostingView(rootView: Real())"))
    }

    func test_previewBlockInComment_isNotStripped() {
        let code = "// #Preview { Old() }\nstruct A {}"
        let result = SwiftPreviewHarness.strippingPreviewBlocks(from: code)
        XCTAssertEqual(result.stripped, code)
        XCTAssertNil(result.firstPreviewBody)
    }

    func test_codeMask_blanksCommentsAndStringsButKeepsLength() {
        let code = ##"""
        let a = "x { \(f("}")) y" // }
        let b = #"raw " } \#(g) "#
        /* outer /* inner } */ still } */ let c = 1
        let d = """
          { "quoted" }
          """
        """##
        let mask = SwiftPreviewHarness.codeMask(code)
        XCTAssertEqual(mask.count, code.count)
        let masked = String(mask)
        XCTAssertFalse(masked.contains("{"))
        XCTAssertFalse(masked.contains("}"))
        XCTAssertTrue(masked.contains("let c = 1"))
        XCTAssertTrue(masked.contains("let d ="))
        XCTAssertEqual(masked.filter(\.isNewline).count, code.filter(\.isNewline).count)
    }

    // MARK: Previewable and line numbers

    func test_previewableState_becomesAStoredProperty() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Counter: View {
            @Binding var value: Int
            var body: some View { Stepper("\\(value)", value: $value) }
        }
        #Preview {
            @Previewable @State var value = 3
            Counter(value: $value)
        }
        """)
        let root = harness.source[harness.source.range(of: "struct __SnippetPreviewRoot")!.lowerBound...]
        let property = root.range(of: "@State var value = 3")!
        let body = root.range(of: "var body: some View")!
        XCTAssertLessThan(property.lowerBound, body.lowerBound, "must be a property, not a local in body")
        XCTAssertFalse(harness.source.contains("@Previewable"))
    }

    func test_strippedPreviewBlock_keepsLaterLineNumbers() {
        let code = "struct A {}\n#Preview {\n    A()\n}\nlet marker = 1"
        let stripped = SwiftPreviewHarness.strippingPreviewBlocks(from: code).stripped
        let line = stripped.components(separatedBy: "\n").firstIndex { $0.contains("marker") }
        XCTAssertEqual(line, 4)
    }

    func test_sourcesAreTaggedForDiagnostics() throws {
        let harness = try SwiftPreviewHarness.make(
            entry: "struct Card: View { var body: some View { Text(\"c\") } }",
            helpers: ["enum Model {}"]
        )
        XCTAssertTrue(harness.source.contains("#sourceLocation(file: \"connected snippet 1\", line: 1)\nenum Model {}"))
        XCTAssertTrue(harness.source.contains("#sourceLocation(file: \"snippet\", line: 1)\nstruct Card"))
        XCTAssertTrue(harness.source.contains("#sourceLocation(file: \"preview harness\", line: 1)"))
    }

    // MARK: Diagnostics

    func test_rootNeedingArguments_getsPreviewBlockHint() throws {
        let harness = try SwiftPreviewHarness.make(code: """
        struct Row: View { let name: String; var body: some View { Text(name) } }
        """)
        let message = SwiftPreviewHarness.describeCompileFailure(
            "preview harness:3:42: error: missing argument for parameter 'name' in call",
            harness: harness
        )
        XCTAssertTrue(message.hasPrefix("“Row” needs arguments"))
        XCTAssertTrue(message.contains("#Preview { Row(…) }"))
    }

    func test_unknownName_getsConnectionHint() throws {
        let harness = try SwiftPreviewHarness.make(code: "struct A: View { var body: some View { Text(Palette.name) } }")
        let message = SwiftPreviewHarness.describeCompileFailure(
            "snippet:1:45: error: cannot find 'Palette' in scope", harness: harness
        )
        XCTAssertTrue(message.contains("“Palette”"))
        XCTAssertTrue(message.contains("connections"))
    }

    func test_longDiagnostics_areCapped() throws {
        let harness = try SwiftPreviewHarness.make(code: "struct A: View { var body: some View { Text(\"a\") } }")
        let raw = (1...2000).map { "snippet:\($0):1: error: e" }.joined(separator: "\n")
        let message = SwiftPreviewHarness.describeCompileFailure(raw, harness: harness)
        XCTAssertTrue(message.hasSuffix("… 1850 more lines"))
    }
}
#endif

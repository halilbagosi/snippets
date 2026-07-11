import XCTest
@testable import Snippets

final class WebPreviewHTMLBuilderTests: XCTestCase {
    private let appearance = WebPreviewHTMLBuilder.Appearance(
        isDark: true, backgroundHex: "#0E1014", textHex: "#E6E8EC"
    )
    private let runtime = WebPreviewHTMLBuilder.ReactRuntime(
        react: "/*react-rt*/", reactDOM: "/*react-dom-rt*/", babel: "/*babel-rt*/"
    )

    private func document(_ code: String, _ flavor: WebPreviewFlavor) -> String {
        WebPreviewHTMLBuilder.document(
            code: code, flavor: flavor, appearance: appearance, runtime: runtime
        )
    }

    // MARK: HTML

    func test_htmlFragment_isWrappedInFullDocument() {
        let doc = document("<button>Tap</button>", .html)
        XCTAssertTrue(doc.contains("<!doctype html>"))
        XCTAssertTrue(doc.contains("<button>Tap</button>"))
        XCTAssertTrue(doc.contains("#0E1014"))
    }

    func test_fullHTMLDocument_passesThroughUnchanged() {
        let full = "<!DOCTYPE html><html><body><p>hi</p></body></html>"
        XCTAssertEqual(document(full, .html), full)
    }

    // MARK: CSS

    func test_css_isInjectedAsStyleWithDemoDOM() {
        let doc = document(".card { color: red; }", .css)
        XCTAssertTrue(doc.contains("<style>"))
        XCTAssertTrue(doc.contains(".card { color: red; }"))
        XCTAssertTrue(doc.contains("class=\"demo\""))
    }

    func test_cssContainingMarkup_isTreatedAsHTML() {
        let mixed = "<div class=\"chip\">hi</div>\n<style>.chip { color: red; }</style>"
        let doc = document(mixed, .css)
        XCTAssertTrue(doc.contains("<div class=\"chip\">hi</div>"))
        XCTAssertFalse(doc.contains("class=\"demo\""))
    }

    // MARK: JavaScript / TypeScript

    func test_javascript_embedsCodeAsJSONAndIncludesConsoleShim() {
        let doc = document("console.log('</script>')", .javascript)
        // Raw closing tag must never appear inside the generated script.
        XCTAssertFalse(doc.contains("console.log('</script>')"))
        XCTAssertTrue(doc.contains("console.log('<\\/script>')") || doc.contains(#"console.log('</script>')"#) || doc.contains(#"<\/script>"#))
        XCTAssertTrue(doc.contains("__snippetConsole"))
        XCTAssertFalse(doc.contains("/*babel-rt*/"))
    }

    func test_typescript_includesBabelAndTypescriptPreset() {
        let doc = document("const n: number = 1", .typescript)
        XCTAssertTrue(doc.contains("/*babel-rt*/"))
        XCTAssertTrue(doc.contains("typescript"))
        XCTAssertTrue(doc.contains("__snippetConsole"))
    }

    // MARK: React

    func test_react_includesRuntimesAndMountShim() {
        let doc = document("export default function App() { return <p>hi</p> }", .react)
        XCTAssertTrue(doc.contains("/*react-rt*/"))
        XCTAssertTrue(doc.contains("/*react-dom-rt*/"))
        XCTAssertTrue(doc.contains("/*babel-rt*/"))
        XCTAssertTrue(doc.contains("id=\"root\""))
        XCTAssertTrue(doc.contains("__snippetMount"))
    }

    func test_react_providesHookBindingsForStrippedImports() {
        // `import { useState } from "react"` is stripped; the UMD runtime only
        // exposes the React global, so hooks must be destructured in scope.
        let doc = document("export default function App() { const [n] = useState(0); return <p>{n}</p> }", .react)
        XCTAssertTrue(doc.contains("useState"))
        XCTAssertTrue(doc.contains("} = React"))
    }

    func test_react_capturesExportInsideEvaluatedSource() {
        // Babel output is strict-mode: const/function declarations inside
        // eval() never become globals, so the component must be captured from
        // within the evaluated source itself, not probed from the shim.
        let doc = document("export default function App() { return <p>hi</p> }", .react)
        XCTAssertEqual(
            doc.components(separatedBy: "window.__SnippetExport").count - 1, 2,
            "expected the capture inside the embedded source and one read in the shim"
        )
    }

    // MARK: GLSL

    func test_glsl_embedsShaderWithWebGLBoilerplateAndUniforms() {
        let shader = "void main() { fragColor = vec4(1.0); }"
        let doc = document(shader, .glsl)
        XCTAssertTrue(doc.contains("getContext(\"webgl2\")") || doc.contains("getContext('webgl2')"))
        for uniform in ["iTime", "iResolution", "iMouse"] {
            XCTAssertTrue(doc.contains(uniform), "missing uniform \(uniform)")
        }
        XCTAssertTrue(doc.contains("fragColor = vec4(1.0);"))
        XCTAssertTrue(doc.contains("snippet-glsl-header"), "fragment-only shader should get the header prelude")
        XCTAssertFalse(doc.contains("/*babel-rt*/"))
    }

    func test_glsl_fullShaderWithVersionDirective_isNotWrappedWithHeader() {
        let shader = "#version 300 es\nprecision highp float;\nout vec4 o;\nvoid main() { o = vec4(1.0); }"
        let doc = document(shader, .glsl)
        XCTAssertFalse(doc.contains("snippet-glsl-header"))
    }

    // MARK: Linked sources

    private func linkedDocument(_ linked: [LinkedSource], _ flavor: WebPreviewFlavor) -> String {
        WebPreviewHTMLBuilder.document(linked: linked, entryFlavor: flavor, appearance: appearance, runtime: runtime)
    }

    func test_linked_reactEntry_getsCSSInjectedAndHelperCodeBeforeEntry() {
        let doc = linkedDocument([
            LinkedSource(language: .css, code: ".theme { color: teal; }"),
            LinkedSource(language: .javascript, code: "function helper() { return 7 }"),
            LinkedSource(language: .react, code: "export default function App() { return <p>{helper()}</p> }")
        ], .react)
        XCTAssertTrue(doc.contains(".theme { color: teal; }"))
        let helperPos = doc.range(of: "function helper")!.lowerBound
        let entryPos = doc.range(of: "__SnippetDefault")!.lowerBound
        XCTAssertLessThan(helperPos, entryPos)
    }

    func test_linked_htmlEntry_prependsHTMLDepAndInjectsStyleAndScript() {
        let doc = linkedDocument([
            LinkedSource(language: .html, code: "<nav>menu</nav>"),
            LinkedSource(language: .css, code: ".x { margin: 0; }"),
            LinkedSource(language: .javascript, code: "console.log('wired')"),
            LinkedSource(language: .html, code: "<main>content</main>")
        ], .html)
        XCTAssertLessThan(doc.range(of: "<nav>menu</nav>")!.lowerBound,
                          doc.range(of: "<main>content</main>")!.lowerBound)
        XCTAssertTrue(doc.contains(".x { margin: 0; }"))
        XCTAssertTrue(doc.contains("__snippetConsole"))
    }

    func test_linked_glslEntry_concatenatesHelpersBeforeEntry() {
        let doc = linkedDocument([
            LinkedSource(language: .glsl, code: "float glow(float x) { return x * 2.0; }"),
            LinkedSource(language: .glsl, code: "void main() { fragColor = vec4(glow(0.4)); }")
        ], .glsl)
        XCTAssertLessThan(doc.range(of: "float glow")!.lowerBound,
                          doc.range(of: "void main()")!.lowerBound)
        XCTAssertTrue(doc.contains("snippet-glsl-header"))
    }

    func test_linked_singleSource_matchesSingleSourceDocument() {
        let code = "console.log('solo')"
        XCTAssertEqual(
            linkedDocument([LinkedSource(language: .javascript, code: code)], .javascript),
            document(code, .javascript)
        )
    }

    func test_linked_typescriptDep_forcesBabelForJavascriptEntry() {
        let doc = linkedDocument([
            LinkedSource(language: .typescript, code: "const n: number = 1"),
            LinkedSource(language: .javascript, code: "console.log(n)")
        ], .javascript)
        XCTAssertTrue(doc.contains("/*babel-rt*/"))
    }

    // MARK: Mount target detection (pure helper used by the react shim)

    func test_mountTarget_prefersDefaultExport() {
        XCTAssertEqual(
            WebPreviewHTMLBuilder.reactMountTarget(in: "function Card() {}\nexport default Card"),
            "Card"
        )
    }

    func test_mountTarget_fallsBackToApp() {
        XCTAssertEqual(
            WebPreviewHTMLBuilder.reactMountTarget(in: "function Card() {}\nfunction App() {}"),
            "App"
        )
    }

    func test_mountTarget_fallsBackToLastCapitalizedComponent() {
        let code = "const first = 1\nfunction Card() {}\nconst Badge = () => null"
        XCTAssertEqual(WebPreviewHTMLBuilder.reactMountTarget(in: code), "Badge")
    }

    func test_mountTarget_defaultExportOfAnonymousFunction() {
        XCTAssertEqual(
            WebPreviewHTMLBuilder.reactMountTarget(in: "export default function () { return null }"),
            nil
        )
    }
}

final class PreviewKindTests: XCTestCase {
    func test_webFamilyLanguages_mapToWebFlavors() {
        XCTAssertEqual(SupportedLanguage.html.previewKind, .web(.html))
        XCTAssertEqual(SupportedLanguage.css.previewKind, .web(.css))
        XCTAssertEqual(SupportedLanguage.javascript.previewKind, .web(.javascript))
        XCTAssertEqual(SupportedLanguage.typescript.previewKind, .web(.typescript))
        XCTAssertEqual(SupportedLanguage.react.previewKind, .web(.react))
        XCTAssertEqual(SupportedLanguage.glsl.previewKind, .web(.glsl))
    }

    func test_nativeEngines() {
        XCTAssertEqual(SupportedLanguage.metal.previewKind, .metal)
        XCTAssertEqual(SupportedLanguage.swift.previewKind, .swiftUI)
    }

    func test_unsupportedLanguages_haveNoPreview() {
        for language: SupportedLanguage in [.python, .rust, .go, .kotlin, .hlsl, .json, .cpp, .unknown] {
            XCTAssertNil(language.previewKind, "\(language) should not be previewable")
        }
    }
}

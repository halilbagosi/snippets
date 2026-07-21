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

    // MARK: Module-syntax stripping (ReactBits-style sources)

    func test_strip_removesMultiLineNamedImports() {
        let code = """
        import {
          useEffect,
          useRef,
        } from "react";
        import React, {
          useState,
        } from 'react';

        export default function App() { return <p>hi</p> }
        """
        let stripped = WebPreviewHTMLBuilder.stripModuleSyntax(code, rewriteDefaultExport: true)
        XCTAssertFalse(stripped.contains("from"))
        XCTAssertFalse(stripped.contains("useEffect,"))
        XCTAssertTrue(stripped.contains("const __SnippetDefault = function App()"))
    }

    func test_strip_removesSideEffectAndNamespaceImports() {
        let code = """
        import "./GradientText.css";
        import * as THREE from "three";
        function App() { return null }
        """
        let stripped = WebPreviewHTMLBuilder.stripModuleSyntax(code, rewriteDefaultExport: true)
        XCTAssertFalse(stripped.contains("import"))
        XCTAssertFalse(stripped.contains("GradientText.css"))
        XCTAssertTrue(stripped.contains("function App()"))
    }

    func test_strip_removesMultiLineExportLists() {
        let code = """
        function A() {}
        function B() {}
        export {
          A,
          B,
        };
        """
        let stripped = WebPreviewHTMLBuilder.stripModuleSyntax(code, rewriteDefaultExport: false)
        XCTAssertFalse(stripped.contains("export"))
        XCTAssertFalse(stripped.contains("A,"))
        XCTAssertTrue(stripped.contains("function A() {}"))
    }

    func test_unsupportedImports_flagsNpmPackagesOnly() {
        let code = """
        import { motion } from "framer-motion";
        import gsap from "gsap";
        import GradientText from "./GradientText";
        import { useState } from "react";
        import ReactDOM from "react-dom/client";
        """
        XCTAssertEqual(
            WebPreviewHTMLBuilder.unsupportedImports(in: code),
            ["framer-motion", "gsap"]
        )
    }

    func test_reactDocument_withNpmImport_loadsPackageFromCDN() {
        let doc = document(
            "import { motion } from \"framer-motion\";\nexport default function App() { return <p>hi</p> }",
            .react
        )
        XCTAssertTrue(doc.contains("https://esm.sh/"))
        XCTAssertTrue(doc.contains("\"framer-motion\""))
        XCTAssertTrue(doc.contains("script-src 'unsafe-inline' 'unsafe-eval' https://esm.sh;"))
    }

    func test_reactDocument_bareJSXHelper_becomesUsageComponentAfterEntry() {
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .react, code: """
                import SpecularButton from './SpecularButton';

                <SpecularButton size="lg">Get Started</SpecularButton>
                """),
                LinkedSource(language: .react, code: """
                const SpecularButton = ({ children }) => <button>{children}</button>;
                export default SpecularButton;
                """)
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("__SnippetUsage"))
        let entryIndex = doc.range(of: "__SnippetDefault = SpecularButton")!.lowerBound
        let usageIndex = doc.range(of: "const __SnippetUsage")!.lowerBound
        XCTAssertTrue(usageIndex > entryIndex, "usage wrapper must come after the entry declaration")
    }

    func test_reactDocument_declarationHelper_staysBeforeEntry() {
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .react, code: "const Helper = () => <p>helper</p>;"),
                LinkedSource(language: .react, code: "export default function App() { return <Helper/> }")
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertFalse(doc.contains("const __SnippetUsage"))
        let helperIndex = doc.range(of: "const Helper")!.lowerBound
        let entryIndex = doc.range(of: "function App()")!.lowerBound
        XCTAssertTrue(helperIndex < entryIndex)
    }

    func test_cdnImportBindings_duplicateImportsAcrossSnippetsBindOnce() {
        let bindings = WebPreviewHTMLBuilder.cdnImportBindings(in: """
        import { Renderer, Program } from "ogl";
        import gsap from "gsap";

        import { Renderer } from "ogl";
        import gsap from "gsap";
        """)
        XCTAssertEqual(bindings.components(separatedBy: "const { Renderer, Program }").count, 2)
        XCTAssertEqual(bindings.components(separatedBy: "const gsap").count, 2)
        XCTAssertFalse(bindings.contains("const { Renderer } ="))
    }

    func test_reactDocument_errorReporting_includesNameAndMessage() {
        let doc = document("export default function App() { return <p>hi</p> }", .react)
        XCTAssertTrue(doc.contains("__snippetErrorText"))
        XCTAssertTrue(doc.contains("e.message"))
    }

    func test_consoleShim_ignoresMutedCrossOriginScriptErrors() {
        let doc = document("console.log('hi')", .javascript)
        XCTAssertTrue(doc.contains("if (e.message === \"Script error.\" && !e.filename) return;"))
    }

    func test_cdnImportBindings_defaultNamespaceAndNamedClauses() {
        let bindings = WebPreviewHTMLBuilder.cdnImportBindings(in: """
        import gsap from "gsap";
        import * as THREE from "three";
        import Def, { named as alias, Renderer } from "ogl";
        import { useState } from "react";
        import Helper from "./Helper";
        """)
        XCTAssertTrue(bindings.contains("const gsap = (window.__snippetModules[\"gsap\"].default !== undefined"))
        XCTAssertTrue(bindings.contains("const THREE = window.__snippetModules[\"three\"];"))
        XCTAssertTrue(bindings.contains("const Def = (window.__snippetModules[\"ogl\"].default !== undefined"))
        XCTAssertTrue(bindings.contains("const { named: alias, Renderer } = window.__snippetModules[\"ogl\"];"))
        XCTAssertFalse(bindings.contains("react"))
        XCTAssertFalse(bindings.contains("Helper"))
    }

    // MARK: CSS entries

    func test_cssDocument_alone_usesDemoMarkup() {
        let doc = document(".card { color: red }", .css)
        XCTAssertTrue(doc.contains("class=\"demo\""))
        XCTAssertTrue(doc.contains(".card { color: red }"))
    }

    func test_cssDocument_withConnectedHTML_usesThatMarkupInsteadOfDemo() {
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .html, code: "<div class=\"card\">real markup</div>"),
                LinkedSource(language: .css, code: ".theme { --x: 1 }"),
                LinkedSource(language: .css, code: ".card { color: red }")
            ],
            entryFlavor: .css, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("real markup"))
        XCTAssertFalse(doc.contains("class=\"demo\""))
        XCTAssertTrue(doc.contains(".theme { --x: 1 }"))
        XCTAssertTrue(doc.contains(".card { color: red }"))
        // Entry CSS must come after helper CSS so it wins the cascade.
        XCTAssertLessThan(doc.range(of: ".theme")!.lowerBound, doc.range(of: ".card {")!.lowerBound)
    }

    func test_containsMarkup_ignoresTagsInsideCommentsAndStrings() {
        XCTAssertFalse(WebPreviewHTMLBuilder.containsMarkup(#"p::before { content: "<b>" } /* <div> */"#))
        XCTAssertTrue(WebPreviewHTMLBuilder.containsMarkup("<div class=\"x\">hi</div>"))
    }

    func test_cssSnippetWithTagOnlyInContentString_staysCSSPreview() {
        let doc = document(#".x::after { content: "<em>" }"#, .css)
        XCTAssertTrue(doc.contains("class=\"demo\""), "must not be misrouted to the HTML path")
    }

    func test_htmlHelperWithLeadingImports_dropsThemFromPrependedMarkup() {
        // A JSX usage snippet stored as HTML must not render its import
        // lines as literal text above the preview.
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .html, code: """
                import Strands from './Strands';
                import './Strands.css';

                <Strands amplitude={1}></Strands>
                """),
                LinkedSource(language: .react, code: "export default function App() { return <p>hi</p> }")
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertFalse(doc.contains("import Strands from"))
        XCTAssertFalse(doc.contains("./Strands.css"))
        XCTAssertTrue(doc.contains("<Strands amplitude={1}></Strands>"))
    }

    func test_strippingLeadingModuleLines_keepsScriptBlockImports() {
        let markup = """
        <div>real</div>
        <script type="module">import { x } from "https://esm.sh/x";</script>
        """
        XCTAssertEqual(WebPreviewHTMLBuilder.strippingLeadingModuleLines(fromMarkup: markup), markup)
    }

    // MARK: Full-document HTML entries with connections

    func test_fullHTMLDocumentWithConnectedCSS_injectsIntoHeadInsteadOfNesting() {
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .css, code: ".injected { color: red }"),
                LinkedSource(language: .html, code: "<html><head><title>t</title></head><body><p>hi</p></body></html>")
            ],
            entryFlavor: .html, appearance: appearance, runtime: runtime
        )
        XCTAssertEqual(doc.components(separatedBy: "<html").count - 1, 1, "must not nest documents")
        XCTAssertTrue(doc.contains(".injected { color: red }"))
        XCTAssertLessThan(doc.range(of: ".injected")!.lowerBound, doc.range(of: "</head>")!.lowerBound)
    }

    func test_fullHTMLDocumentWithConnectedScript_runsBeforeBodyClose() {
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .javascript, code: "console.log('helper')"),
                LinkedSource(language: .html, code: "<html><body><p>hi</p></body></html>")
            ],
            entryFlavor: .html, appearance: appearance, runtime: runtime
        )
        XCTAssertEqual(doc.components(separatedBy: "<html").count - 1, 1)
        XCTAssertTrue(doc.contains("console.log('helper')"))
        XCTAssertLessThan(doc.range(of: "<p>hi</p>")!.lowerBound, doc.range(of: "console.log")!.lowerBound)
    }

    func test_fullHTMLDocumentWithoutConnections_passesThroughUntouched() {
        let code = "<html><body><p>hi</p></body></html>"
        XCTAssertEqual(document(code, .html), code)
    }

    func test_reactDocument_withOnlyReactAndRelativeImports_hasNoCDNReference() {
        let doc = document(
            """
            import { useState } from "react";
            import Helper from "./Helper";
            export default function App() { return <p>hi</p> }
            """,
            .react
        )
        XCTAssertFalse(doc.contains("esm.sh"))
    }

    // MARK: Incremental updates

    func test_themeUpdateScript_setsCustomPropertiesWithEscapedValues() {
        let script = WebPreviewHTMLBuilder.themeUpdateScript(appearance: appearance)
        XCTAssertTrue(script.contains("--preview-bg"))
        XCTAssertTrue(script.contains("--preview-text"))
        XCTAssertTrue(script.contains("\"#0E1014\""))
        XCTAssertTrue(script.contains("\"#E6E8EC\""))
    }

    func test_sourceUpdateScript_javascript_containsCodeAndGenerationGuard() {
        let script = WebPreviewHTMLBuilder.sourceUpdateScript(
            linked: [LinkedSource(language: .javascript, code: "console.log(42)")],
            entryFlavor: .javascript
        )
        XCTAssertNotNil(script)
        XCTAssertTrue(script!.contains("console.log(42)"))
        XCTAssertTrue(script!.contains("__previewGeneration"))
    }

    func test_sourceUpdateScript_returnsNilForHTMLPassthrough() {
        let full = "<!DOCTYPE html><html><body><p>hi</p></body></html>"
        XCTAssertNil(WebPreviewHTMLBuilder.sourceUpdateScript(
            linked: [LinkedSource(language: .html, code: full)],
            entryFlavor: .html
        ))
    }

    func test_sourceUpdateScript_react_routesThroughBabelTransform() {
        let script = WebPreviewHTMLBuilder.sourceUpdateScript(
            linked: [LinkedSource(language: .react, code: "export default function App() { return <p>hi</p> }")],
            entryFlavor: .react
        )
        XCTAssertNotNil(script)
        XCTAssertTrue(script!.contains("Babel.transform"))
        XCTAssertTrue(script!.contains("__snippetMount"))
    }

    func test_documentAndUpdateScript_embedSameUserProgramPayload() {
        let code = "export default function App() { return <p>shared-marker-xyz</p> }"
        let doc = document(code, .react)
        let update = WebPreviewHTMLBuilder.sourceUpdateScript(
            linked: [LinkedSource(language: .react, code: code)],
            entryFlavor: .react
        )!
        // Both paths embed the payload via the shared reactSource/reactProgram
        // functions — the JSON-escaped source literal must match exactly.
        let payload = doc.range(of: "const __snippetSource = ").flatMap { r in
            doc[r.upperBound...].split(separator: "\n").first.map(String.init)
        }
        XCTAssertNotNil(payload)
        XCTAssertTrue(update.contains(payload!))
        XCTAssertTrue(payload!.contains("shared-marker-xyz"))
    }

    // MARK: Content-Security-Policy

    func test_allFlavors_includeRestrictiveCSP() {
        let samples: [(String, WebPreviewFlavor)] = [
            ("<button>Tap</button>", .html),
            (".card { color: red; }", .css),
            ("console.log(1)", .javascript),
            ("const n: number = 1", .typescript),
            ("export default function App() { return <p>hi</p> }", .react),
        ]
        for (code, flavor) in samples {
            let doc = document(code, flavor)
            XCTAssertTrue(doc.contains("Content-Security-Policy"), "\(flavor) missing CSP meta")
            XCTAssertTrue(doc.contains("connect-src 'none'"), "\(flavor) missing connect-src 'none'")
        }
    }

    func test_csp_appearsBeforeFirstStyleTag() {
        let doc = document("<button>Tap</button>", .html)
        let csp = doc.range(of: "Content-Security-Policy")
        let style = doc.range(of: "<style")
        XCTAssertNotNil(csp)
        XCTAssertNotNil(style)
        XCTAssertTrue(csp!.lowerBound < style!.lowerBound)
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

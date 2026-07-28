import XCTest
@testable import Snippets

final class WebPreviewHTMLBuilderTests: XCTestCase {
    private let appearance = WebPreviewHTMLBuilder.Appearance(
        isDark: true, backgroundHex: "#0E1014", textHex: "#E6E8EC"
    )
    private let runtime = WebPreviewHTMLBuilder.PreviewRuntime(
        react: "/*react-rt*/", reactDOM: "/*react-dom-rt*/", babel: "/*babel-rt*/",
        tailwind: "/*tailwind-rt*/",
        bootstrapCSS: "@charset \"UTF-8\";/*bootstrap-css*/", bootstrapJS: "/*bootstrap-js*/"
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
        XCTAssertTrue(stripped.contains("function App() { return <p>hi</p> }"))
        XCTAssertTrue(stripped.contains("const __SnippetDefault = App;"))
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

    private static let npmImportSnippet =
        "import { motion } from \"framer-motion\";\nexport default function App() { return <p>hi</p> }"

    func test_reactDocument_withNpmImport_grantedPolicy_loadsPackageFromCDN() {
        let doc = WebPreviewHTMLBuilder.document(
            code: Self.npmImportSnippet, flavor: .react, appearance: appearance,
            runtime: runtime, policy: .init(allowsCDNModules: true)
        )
        XCTAssertTrue(doc.contains("https://esm.sh/"))
        XCTAssertTrue(doc.contains("\"framer-motion\""))
        XCTAssertTrue(doc.contains("script-src 'unsafe-inline' 'unsafe-eval' https://esm.sh;"))
    }

    /// The default. An unapproved snippet neither fetches nor gets a CSP that
    /// would let it: the loader is absent *and* esm.sh stays out of script-src.
    func test_reactDocument_withNpmImport_deniedByDefault() {
        let doc = document(Self.npmImportSnippet, .react)
        // The domain still appears — in the console message telling the user
        // how to allow it. What must be absent is any way to actually reach it.
        XCTAssertFalse(doc.contains("https://esm.sh/"))
        XCTAssertTrue(doc.contains("script-src 'unsafe-inline' 'unsafe-eval';"))
        XCTAssertTrue(doc.contains("Blocked npm import(s): framer-motion"))
    }

    /// Denying the fetch must also drop the bindings that would read the
    /// modules back out — otherwise the failure surfaces as an unrelated
    /// TypeError deep inside the snippet instead of the console message.
    func test_reactDocument_deniedCDN_omitsModuleBindings() {
        let doc = document(Self.npmImportSnippet, .react)
        XCTAssertFalse(doc.contains("__snippetModules"))
    }

    func test_cdnSpecifiers_reportsWhatNeedsApproval() {
        XCTAssertEqual(
            WebPreviewHTMLBuilder.cdnSpecifiers(
                linked: [LinkedSource(language: .react, code: Self.npmImportSnippet)],
                entryFlavor: .react
            ),
            ["framer-motion"]
        )
    }

    /// Only React resolves npm specifiers, so nothing else can ever prompt.
    func test_cdnSpecifiers_isEmptyForNonReactFlavors() {
        XCTAssertTrue(
            WebPreviewHTMLBuilder.cdnSpecifiers(
                linked: [LinkedSource(language: .html, code: "import x from \"gsap\";")],
                entryFlavor: .html
            ).isEmpty
        )
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

    func test_jsxUsageStoredAsHTML_becomesMountTargetNotMarkup() {
        // Stored as HTML it would be pasted into the body, where the browser
        // renders an unknown empty element and the entry mounts with its own
        // defaults — the demonstrated props silently lost.
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
        // Never in the body as markup...
        XCTAssertFalse(doc.contains("<Strands amplitude={1}></Strands>\n<div id=\"root\">"))
        // ...but wrapped as the usage component the shim renders.
        XCTAssertTrue(doc.contains("__SnippetUsage"))
    }

    func test_defaultExportedFunctionDeclaration_keepsItsNameInScope() {
        // `const __SnippetDefault = function Strands() {}` is a named function
        // *expression*: `Strands` binds only inside its own body, so a usage
        // snippet's `<Strands />` dies with "Strands is not defined".
        let stripped = WebPreviewHTMLBuilder.stripModuleSyntax(
            "export default function Strands({ count = 3 }) { return null }",
            rewriteDefaultExport: true
        )
        XCTAssertTrue(stripped.contains("function Strands({ count = 3 })"))
        XCTAssertFalse(stripped.contains("const __SnippetDefault = function Strands"))
        XCTAssertTrue(stripped.contains("const __SnippetDefault = Strands;"))
    }

    func test_defaultExportedClass_keepsItsNameInScope() {
        let stripped = WebPreviewHTMLBuilder.stripModuleSyntax(
            "export default class Widget extends React.Component {}", rewriteDefaultExport: true
        )
        XCTAssertTrue(stripped.contains("class Widget extends React.Component"))
        XCTAssertTrue(stripped.contains("const __SnippetDefault = Widget;"))
    }

    func test_anonymousDefaultExport_stillBindsSnippetDefault() {
        let stripped = WebPreviewHTMLBuilder.stripModuleSyntax(
            "export default function () { return null }", rewriteDefaultExport: true
        )
        XCTAssertTrue(stripped.contains("const __SnippetDefault = function ()"))
    }

    func test_usageSnippet_rendersComponentDeclaredAsDefaultExportedFunction() {
        // End to end: the pairing that broke Strands — a usage helper naming a
        // component whose entry declares it via `export default function`.
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .html, code: "<Strands count={3} />"),
                LinkedSource(language: .react, code: "export default function Strands({ count = 3 }) { return null }")
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("function Strands({ count = 3 })"))
        XCTAssertTrue(doc.contains("const __SnippetDefault = Strands;"))
        XCTAssertTrue(doc.contains("__SnippetUsage"))
    }

    func test_usageSnippet_forwardsPropOverridesToTheComponent() {
        // Without this the usage snippet's hard-coded props win and every
        // parameter control is a no-op: the shim hands overrides to the mount
        // target, which is the usage wrapper rather than the component.
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .react, code: "<OptionWheel fontSize={3} />"),
                LinkedSource(language: .react, code: """
                const OptionWheel = ({ fontSize = 3 }) => <p>{fontSize}</p>;
                export default OptionWheel;
                """)
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("window.__snippetOverride = "))
        XCTAssertTrue(doc.contains("const __SnippetUsage = (__props) => window.__snippetOverride("))
        XCTAssertTrue(doc.contains(#"(typeof OptionWheel !== \"undefined\" ? OptionWheel : null), __props)"#))
    }

    func test_isJSXUsage_separatesComponentUsageFromPlainMarkup() {
        XCTAssertTrue(WebPreviewHTMLBuilder.isJSXUsage("<Strands amplitude={1} />"))
        XCTAssertTrue(WebPreviewHTMLBuilder.isJSXUsage("""
        import CursorGrid from './CursorGrid';

        <div style={{ height: '600px' }}><CursorGrid cellSize={70} /></div>
        """))
        XCTAssertFalse(WebPreviewHTMLBuilder.isJSXUsage("<div class=\"card\">hi</div>"))
        XCTAssertFalse(WebPreviewHTMLBuilder.isJSXUsage("<svg><linearGradient /></svg>"))
        XCTAssertFalse(WebPreviewHTMLBuilder.isJSXUsage("plain text <Strands />"))
    }

    func test_plainHTMLHelper_staysPrependedMarkupForReactEntry() {
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .html, code: "<div class=\"banner\">hello</div>"),
                LinkedSource(language: .react, code: "export default function App() { return <p>hi</p> }")
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("<div class=\"banner\">hello</div>"))
    }

    // MARK: Tailwind (ReactBits ships every component in a Tailwind variant)

    func test_reactDocument_inlinesTailwindAndSkipsPreflight() {
        let doc = document("export default function App() { return <p className=\"h-full\">hi</p> }", .react)
        XCTAssertTrue(doc.contains("/*tailwind-rt*/"))
        XCTAssertTrue(doc.contains("<style type=\"text/tailwindcss\">"))
        XCTAssertTrue(doc.contains(#"@import "tailwindcss/utilities" layer(utilities);"#))
        // The umbrella import would drag in Preflight and strip the native
        // look off every <h2>/<button> in non-Tailwind React snippets.
        XCTAssertFalse(doc.contains(#"@import "tailwindcss";"#))
        XCTAssertTrue(doc.contains("box-sizing: border-box;"))
    }

    func test_nonReactDocuments_carryNoTailwind() {
        for flavor in [WebPreviewFlavor.html, .css, .javascript, .glsl] {
            XCTAssertFalse(
                document("body { color: red }", flavor).contains("/*tailwind-rt*/"),
                "\(flavor) should not inline Tailwind"
            )
        }
    }

    func test_reactMount_settlesLayoutWithoutBlockingOnTailwind() {
        let doc = document("export default function App() { return <p>hi</p> }", .react)
        XCTAssertTrue(doc.contains("__snippetSettleLayout();"))
        // Blocking the mount on Tailwind's compile (or on rAF, throttled to a
        // crawl in a background window) leaves the preview empty meanwhile.
        XCTAssertFalse(doc.contains("await __snippetStylesReady"))
        // The nudge watches <head>; watching the whole document would let a
        // component's own resize-driven DOM writes retrigger it in a loop.
        XCTAssertTrue(doc.contains("observer.observe(document.head,"))
    }

    // MARK: Bootstrap

    func test_usesBootstrap_recognisesBootstrapMarkup() {
        let samples = [
            #"<button class="btn btn-primary">Go</button>"#,
            #"<div class="card"><div class="card-body">hi</div></div>"#,
            #"<nav class="navbar navbar-expand-lg"></nav>"#,
            ##"<button data-bs-toggle="modal" data-bs-target="#m">Open</button>"##,
            #"<div class="col-md-6"></div>"#,
            #"<div class="d-flex justify-content-center"></div>"#,
            #"<input class="form-control">"#,
            #"<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css" rel="stylesheet">"#
        ]
        for s in samples {
            XCTAssertTrue(WebPreviewHTMLBuilder.usesBootstrap(s), "should detect Bootstrap in: \(s)")
        }
    }

    func test_usesBootstrap_doesNotFireOnTailwindOrPlainMarkup() {
        // Reboot would restyle every bare <h2>/<button>, so a false positive
        // here silently rewrites unrelated previews.
        let samples = [
            #"<div class="absolute top-1/2 h-full w-full overflow-hidden"></div>"#,
            #"<div class="flex items-center justify-center gap-2 rounded-2xl"></div>"#,
            #"<button class="px-[22px] py-[10px] text-[1rem] font-medium"></button>"#,
            #"<div class="card">plain markup that happens to use .card</div>"#,
            #"<h2>Hello</h2><p>Just text</p>"#
        ]
        for s in samples {
            XCTAssertFalse(WebPreviewHTMLBuilder.usesBootstrap(s), "should NOT detect Bootstrap in: \(s)")
        }
    }

    func test_bootstrapDocument_inlinesStylesheetAndBundle_andDropsCharset() {
        let doc = document(#"<button class="btn btn-primary" data-bs-toggle="tooltip">Go</button>"#, .html)
        XCTAssertTrue(doc.contains("/*bootstrap-css*/"))
        XCTAssertTrue(doc.contains("/*bootstrap-js*/"))
        // @charset is only valid at the head of an external stylesheet.
        XCTAssertFalse(doc.contains("@charset"))
    }

    func test_nonBootstrapDocument_carriesNoBootstrap() {
        for (code, flavor) in [
            ("<h2>plain</h2>", WebPreviewFlavor.html),
            (".a { color: red }", .css),
            ("console.log(1)", .javascript),
            ("export default function App() { return <p className=\"flex\">hi</p> }", .react)
        ] {
            let doc = document(code, flavor)
            XCTAssertFalse(doc.contains("/*bootstrap-css*/"), "\(flavor) should not inline Bootstrap")
            XCTAssertFalse(doc.contains("/*bootstrap-js*/"), "\(flavor) should not inline Bootstrap")
        }
    }

    func test_bootstrapInConnectedSnippet_reachesTheEntryDocument() {
        // Markup and its stylesheet routinely arrive as two linked snippets.
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .html, code: #"<div class="alert alert-danger">!</div>"#),
                LinkedSource(language: .css, code: ".mine { color: red }")
            ],
            entryFlavor: .css, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("/*bootstrap-css*/"))
    }

    func test_bootstrapFullDocument_injectsIntoHeadAndBody() {
        let doc = document("""
        <html><head>
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.8/dist/css/bootstrap.min.css" rel="stylesheet">
        </head><body><button class="btn btn-primary">Go</button></body></html>
        """, .html)
        XCTAssertTrue(doc.contains("/*bootstrap-css*/"))
        XCTAssertTrue(doc.contains("/*bootstrap-js*/"))
        XCTAssertTrue(
            doc.range(of: "/*bootstrap-css*/")!.lowerBound < doc.range(of: "</head>")!.lowerBound,
            "stylesheet must land in <head>"
        )
    }

    // MARK: Skeleton layout

    func test_skeleton_centersMountRootAndBoundsConsole() {
        let doc = document("export default function App() { return <p>hi</p> }", .react)
        XCTAssertTrue(doc.contains("#root {"))
        XCTAssertTrue(doc.contains("justify-content: center;"))
        // An untouched console reserves no space; a chatty one cannot push
        // the preview off screen.
        XCTAssertTrue(doc.contains(".snippet-console:empty { display: none; }"))
        XCTAssertTrue(doc.contains("#root ~ .snippet-console { max-height: 33%; }"))
    }

    func test_consoleShim_capsRetainedLines() {
        let doc = document("console.log('x')", .javascript)
        XCTAssertTrue(doc.contains("childElementCount > this.limit"))
        XCTAssertTrue(doc.contains("scrollTop = this.el.scrollHeight"))
    }

    func test_reactConsole_showsErrorsOnly_scriptConsoleShowsEverything() {
        // A ReactBits component wired to `onChange={(i, x) => console.log(i, x)}`
        // otherwise paints a running list of its own options over the demo.
        XCTAssertTrue(
            document("export default function App() { return <p>hi</p> }", .react)
                .contains("errorsOnly: true")
        )
        // For a JS snippet the console *is* the output.
        XCTAssertTrue(document("console.log('x')", .javascript).contains("errorsOnly: false"))
        XCTAssertTrue(document("<p>hi</p>", .html).contains("errorsOnly: false") || !document("<p>hi</p>", .html).contains("errorsOnly"))
    }

    func test_skeleton_capsMountedContentToThePane() {
        // A usage snippet framing its demo at `height: 600px` must shrink to
        // fit rather than overflow and get clipped — which cut the top and
        // bottom off a glass orb.
        let doc = document("export default function App() { return <p>hi</p> }", .react)
        XCTAssertTrue(doc.contains("#root > * { max-width: 100%; max-height: 100%; }"))
        XCTAssertTrue(doc.contains("overflow: hidden;"))
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

    func test_fullHTMLDocumentWithoutConnections_keepsMarkupAndAddsOnlyCSP() {
        let code = "<html><body><p>hi</p></body></html>"
        let doc = document(code, .html)
        XCTAssertTrue(doc.contains("<body><p>hi</p></body>"))
        // Nothing but the policy is injected when there is nothing to connect.
        XCTAssertFalse(doc.contains("<style"))
        XCTAssertFalse(doc.contains("<script"))
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

    /// Passthrough keeps the author's markup intact — but never unpoliced. The
    /// CSP is the one thing added, because a complete document that skipped the
    /// skeleton used to run with no policy at all and could beacon out through
    /// subresource loads the navigation delegate never sees.
    func test_fullHTMLDocument_passesThroughWithCSPAdded() {
        let full = "<!DOCTYPE html><html><body><p>hi</p></body></html>"
        let doc = document(full, .html)
        XCTAssertTrue(doc.contains("<body><p>hi</p></body>"))
        XCTAssertTrue(doc.contains("connect-src 'none'"))
        XCTAssertEqual(doc.components(separatedBy: "Content-Security-Policy").count - 1, 1)
    }

    /// Position matters: WebKit enforces a meta CSP only from where it parses
    /// it, so a policy landing after a `<script src>` would not cover it.
    func test_fullHTMLDocument_cspPrecedesDocumentContent() {
        let full = "<html><head><script src=\"https://evil.test/x.js\"></script></head><body></body></html>"
        let doc = document(full, .html)
        let csp = doc.range(of: "Content-Security-Policy")!
        let script = doc.range(of: "evil.test")!
        XCTAssertLessThan(csp.lowerBound, script.lowerBound)
    }

    /// A bare `<html>` with no head still has to be covered.
    func test_fullHTMLDocumentWithoutHead_stillGetsCSP() {
        let doc = document("<html><body><p>hi</p></body></html>", .html)
        XCTAssertTrue(doc.contains("connect-src 'none'"))
        XCTAssertLessThan(
            doc.range(of: "Content-Security-Policy")!.lowerBound,
            doc.range(of: "<p>hi</p>")!.lowerBound
        )
    }

    /// Passthrough documents are never the CDN-grant path (that is React-only),
    /// so their policy stays closed even when a grant exists elsewhere.
    func test_fullHTMLDocument_cspNeverAllowsCDN() {
        let doc = WebPreviewHTMLBuilder.document(
            code: "<html><body><p>hi</p></body></html>", flavor: .html,
            appearance: appearance, runtime: runtime,
            policy: .init(allowsCDNModules: true)
        )
        XCTAssertFalse(doc.contains("esm.sh"))
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

extension WebPreviewHTMLBuilderTests {
    /// ReactBits usage blocks often demonstrate several presets of the same
    /// component. The site's live demo shows one; mounting the whole block
    /// rendered every preset at once (two inputs for Curved Input), plus the
    /// `// …` label between them as literal JSX text.
    func test_usageWithSeveralPresets_mountsOnlyTheFirst() {
        let usage = """
        import CurvedInput from './CurvedInput'

        <CurvedInput
          placeholder="david@reactbits.dev"
          bend={28}
          onSubmit={value => console.log(value)}
        />

        // Light preset, flat, no button
        <CurvedInput
          showButton
          placeholder="Search components..."
          cornerRadius={18}
        />
        """
        let doc = WebPreviewHTMLBuilder.document(
            linked: [
                LinkedSource(language: .react, code: usage),
                LinkedSource(language: .react, code: """
                const CurvedInput = ({ bend = 28 }) => null;
                export default CurvedInput;
                """)
            ],
            entryFlavor: .react, appearance: appearance, runtime: runtime
        )
        XCTAssertTrue(doc.contains("david@reactbits.dev"))
        XCTAssertFalse(doc.contains("Search components..."), "second preset must not be mounted")
        XCTAssertFalse(doc.contains("Light preset"), "the label must not render as JSX text")
    }

    func test_firstJSXElement_keepsAWrapperWhole() {
        // A usage that wraps the component in a sized frame is ONE element.
        let usage = """
        <div style={{ width: '100%', height: '600px' }}>
          <CursorGrid cellSize={70} />
        </div>
        """
        let first = WebPreviewHTMLBuilder.firstJSXElement(in: usage)
        XCTAssertEqual(first.map { String(usage[$0]) }, usage)
    }

    func test_firstJSXElement_handlesSelfClosingAndNestedSameTag() {
        let selfClosing = "<A x={1} />\n<A x={2} />"
        XCTAssertEqual(
            WebPreviewHTMLBuilder.firstJSXElement(in: selfClosing).map { String(selfClosing[$0]) },
            "<A x={1} />"
        )
        let nested = "<A><A>inner</A></A>\n<A>second</A>"
        XCTAssertEqual(
            WebPreviewHTMLBuilder.firstJSXElement(in: nested).map { String(nested[$0]) },
            "<A><A>inner</A></A>"
        )
    }
}

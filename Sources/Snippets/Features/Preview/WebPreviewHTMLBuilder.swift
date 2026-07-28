import Foundation

/// Builds self-contained HTML documents for the WKWebView preview engine.
/// Pure string → string; no WebKit dependency so it stays unit-testable.
enum WebPreviewHTMLBuilder {
    struct Appearance {
        let isDark: Bool
        let backgroundHex: String
        let textHex: String
    }

    /// What a snippet's preview is permitted to do beyond running offline in a
    /// closed frame. Every field defaults to denied: a capability is granted
    /// only where the user has explicitly granted it, for that one snippet.
    struct Policy: Equatable {
        /// Whether this snippet may pull npm modules from esm.sh.
        ///
        /// Granting it widens `script-src` to include the CDN, which hands the
        /// snippet both third-party code execution and — because `import()`
        /// answers to script-src rather than connect-src — a way out through
        /// the specifier it requests. Nothing else in the preview can reach the
        /// network, so this flag is the whole egress decision.
        var allowsCDNModules: Bool = false

        /// The default for anything that has not been granted anything.
        static let denied = Policy()
    }

    /// The npm specifiers a React snippet declared, split by what the policy
    /// lets the preview actually do with them.
    struct CDNModules: Equatable {
        /// Fetched from esm.sh before the snippet evaluates.
        let allowed: [String]
        /// Detected but refused; reported in the preview console.
        let blocked: [String]

        init(detected: [String], policy: Policy) {
            if policy.allowsCDNModules {
                allowed = detected
                blocked = []
            } else {
                allowed = []
                blocked = detected
            }
        }
    }

    /// Vendored runtime scripts, inlined into the document so previews work
    /// offline and never depend on file-URL resource loading.
    struct PreviewRuntime {
        let react: String
        let reactDOM: String
        let babel: String
        /// Tailwind's browser build. ReactBits ships every component in a
        /// Tailwind variant whose entire layout lives in utility classes
        /// (`absolute top-1/2`, `[font-size:var(--x)]`), so without it those
        /// previews collapse into an unstyled stack of their own children.
        let tailwind: String
        /// Bootstrap's stylesheet and its JS bundle (Popper included). Unlike
        /// Tailwind these are injected only into documents that actually look
        /// like Bootstrap — its Reboot reset restyles every bare `<h2>` and
        /// `<button>`, which would rewrite unrelated HTML previews.
        let bootstrapCSS: String
        let bootstrapJS: String

        init(
            react: String, reactDOM: String, babel: String,
            tailwind: String = "", bootstrapCSS: String = "", bootstrapJS: String = ""
        ) {
            self.react = react
            self.reactDOM = reactDOM
            self.babel = babel
            self.tailwind = tailwind
            self.bootstrapCSS = bootstrapCSS
            self.bootstrapJS = bootstrapJS
        }
    }

    static func document(
        code: String,
        flavor: WebPreviewFlavor,
        appearance: Appearance,
        runtime: PreviewRuntime,
        policy: Policy = .denied
    ) -> String {
        document(
            linked: [LinkedSource(language: language(for: flavor), code: code)],
            entryFlavor: flavor,
            appearance: appearance,
            runtime: runtime,
            policy: policy
        )
    }

    /// The npm specifiers `linked` would need from the CDN — what the preview
    /// asks the user to approve. Empty for every flavor but React, and for
    /// React snippets that import nothing beyond the bundled runtimes.
    static func cdnSpecifiers(linked: [LinkedSource], entryFlavor: WebPreviewFlavor) -> [String] {
        guard entryFlavor == .react, let entry = linked.last else { return [] }
        let helperScript = helperRoles(in: linked, entryFlavor: entryFlavor)
            .script.map(\.code).joined(separator: "\n\n")
        return unsupportedImports(in: helperScript + "\n" + entry.code)
    }

    /// Combined document for a snippet plus its resolved dependencies
    /// (helpers first, entry last — see `SnippetLinker`). Dependency CSS is
    /// injected as a style block, dependency HTML is prepended above the
    /// entry markup, and dependency JS/TS/React runs before the entry code.
    static func document(
        linked: [LinkedSource],
        entryFlavor: WebPreviewFlavor,
        appearance: Appearance,
        runtime: PreviewRuntime,
        policy: Policy = .denied
    ) -> String {
        guard let entry = linked.last else {
            return skeleton(appearance: appearance, body: "")
        }
        let helpers = helperRoles(in: linked, entryFlavor: entryFlavor)
        let css = helpers.css.map(\.code).joined(separator: "\n\n")
        let html = helpers.markup
            .map { strippingLeadingModuleLines(fromMarkup: $0.code) }
            .joined(separator: "\n")
        let helperScript = helpers.script.map(\.code).joined(separator: "\n\n")
        let helpersNeedBabel = helpers.script.contains { $0.language != .javascript }
        // Decided across every linked source: a Bootstrap component's markup
        // and its stylesheet routinely arrive as two connected snippets.
        let bootstrap = linked.contains { usesBootstrap($0.code) }

        switch entryFlavor {
        case .html:
            return htmlDocument(
                code: entry.code, appearance: appearance,
                prependedHTML: html, extraCSS: css,
                helperScript: helperScript, needsBabel: helpersNeedBabel,
                runtime: runtime, bootstrap: bootstrap
            )
        case .css:
            return cssDocument(
                code: (helpers.css.map(\.code) + [entry.code]).joined(separator: "\n\n"),
                markup: html,
                appearance: appearance,
                runtime: runtime, bootstrap: bootstrap
            )
        case .javascript, .typescript:
            let combined = helperScript.isEmpty ? entry.code : helperScript + "\n\n" + entry.code
            let useBabel = entryFlavor == .typescript || helpersNeedBabel
            return scriptDocument(
                code: combined, appearance: appearance,
                babel: useBabel ? runtime.babel : nil,
                presets: useBabel ? typescriptPresets : nil,
                prependedHTML: html, extraCSS: css,
                runtime: runtime, bootstrap: bootstrap
            )
        case .react:
            return reactDocument(
                code: entry.code, appearance: appearance, runtime: runtime,
                helperScript: helperScript, prependedHTML: html, extraCSS: css,
                bootstrap: bootstrap, policy: policy
            )
        case .glsl:
            let combined = (helpers.glsl.map(\.code) + [entry.code]).joined(separator: "\n\n")
            return glslDocument(code: combined, appearance: appearance)
        }
    }

    /// Splits a snippet's helpers by the role they play in the generated
    /// document. Language alone doesn't decide it: a JSX *usage* snippet
    /// (`<CursorGrid cellSize={70} />`) is routinely stored as HTML, because
    /// capitalized component tags read as markup to the language detector.
    /// Pasted into the body as markup it renders as an unknown empty element
    /// and — worse — the component then mounts with its own defaults instead
    /// of the props the snippet exists to demonstrate. Routed to the script
    /// side, `reactSource` turns it into the mount target, which is what the
    /// component's page on ReactBits shows.
    static func helperRoles(
        in linked: [LinkedSource], entryFlavor: WebPreviewFlavor
    ) -> (css: [LinkedSource], markup: [LinkedSource], script: [LinkedSource], glsl: [LinkedSource]) {
        var css: [LinkedSource] = []
        var markup: [LinkedSource] = []
        var script: [LinkedSource] = []
        var glsl: [LinkedSource] = []
        for helper in linked.dropLast() {
            switch helper.language {
            case .css: css.append(helper)
            case .glsl: glsl.append(helper)
            case .javascript, .typescript, .react: script.append(helper)
            case .html:
                if entryFlavor == .react, isJSXUsage(helper.code) {
                    script.append(LinkedSource(language: .react, code: helper.code))
                } else {
                    markup.append(helper)
                }
            default: break
            }
        }
        return (css, markup, script, glsl)
    }

    /// Whether a snippet is a Bootstrap component, so the preview should
    /// inline Bootstrap for it. Every token here is one Bootstrap owns and
    /// Tailwind spells differently (`d-flex` vs `flex`, `col-md-6` vs
    /// `md:w-1/2`, `justify-content-center` vs `justify-center`), because a
    /// false positive would drop Reboot on a Tailwind snippet and restyle it.
    /// `data-bs-*` is the strongest signal: it is Bootstrap's own JS API.
    static func usesBootstrap(_ code: String) -> Bool {
        let markers = [
            #"\bdata-bs-[a-z]+"#,
            #"\bbtn btn-|\bbtn-(?:outline-|group\b|close\b)"#,
            #"\bnavbar(?:-expand|-brand|-toggler|-nav)"#,
            #"\bcard-(?:body|header|footer|title|text)\b"#,
            #"\bcontainer-fluid\b|\bcol-(?:sm|md|lg|xl|xxl)-\d"#,
            #"\bform-(?:control|select|check|floating)\b|\binput-group\b"#,
            #"\blist-group(?:-item)?\b|\bmodal-(?:dialog|content|body)\b"#,
            #"\bcarousel-(?:inner|item)\b|\baccordion-(?:item|button)\b"#,
            #"\bdropdown-(?:menu|toggle|item)\b|\bprogress-bar\b"#,
            #"\bspinner-(?:border|grow)\b|\boffcanvas\b|\bpage-link\b"#,
            #"\bd-(?:flex|none|block|inline-block|grid)\b"#,
            #"\bjustify-content-(?:center|between|around|start|end)\b"#,
            #"\balign-items-(?:center|start|end|baseline)\b"#,
            #"\btext-bg-|\balert alert-|\bbadge bg-"#,
            // A Bootstrap CDN <link>/<script> the preview's CSP would block.
            #"(?:href|src)=["'][^"']*bootstrap[^"']*\.(?:css|js)"#
        ]
        return markers.contains { code.range(of: $0, options: .regularExpression) != nil }
    }

    /// The range of the first complete top-level JSX element in `code`.
    ///
    /// ReactBits usage blocks routinely list several presets of the same
    /// component one after another, with `// …` labels between them. The
    /// site's live demo shows one, and so must the preview: rendering the
    /// whole block mounted every preset at once, and the labels — which are
    /// plain text inside a JSX fragment, not comments — showed up as content.
    /// A usage that wraps its component in a sized frame is a single element
    /// and comes back whole.
    static func firstJSXElement(in code: String) -> Range<String.Index>? {
        guard let open = code.range(of: "<[A-Za-z]", options: .regularExpression) else { return nil }
        let nameStart = code.index(after: open.lowerBound)
        var cursor = nameStart
        while cursor < code.endIndex, code[cursor].isLetter || code[cursor].isNumber
                || code[cursor] == "_" || code[cursor] == "$" || code[cursor] == "." {
            cursor = code.index(after: cursor)
        }
        let tag = String(code[nameStart..<cursor])

        /// Advances past a balanced `{…}` or a quoted string at `i`.
        func skipDelimited(_ i: inout String.Index) -> Bool {
            guard i < code.endIndex else { return false }
            let opener = code[i]
            if opener == "\"" || opener == "'" {
                i = code.index(after: i)
                while i < code.endIndex {
                    if code[i] == "\\" {
                        i = code.index(i, offsetBy: 2, limitedBy: code.endIndex) ?? code.endIndex
                        continue
                    }
                    if code[i] == opener { i = code.index(after: i); return true }
                    i = code.index(after: i)
                }
                return true
            }
            guard opener == "{" else { return false }
            var depth = 0
            while i < code.endIndex {
                if code[i] == "\"" || code[i] == "'" { _ = skipDelimited(&i); continue }
                if code[i] == "{" { depth += 1 }
                if code[i] == "}" {
                    depth -= 1
                    i = code.index(after: i)
                    if depth == 0 { return true }
                    continue
                }
                i = code.index(after: i)
            }
            return true
        }

        /// Consumes the rest of an opening tag, reporting whether it self-closed.
        func finishOpeningTag(_ i: inout String.Index) -> Bool {
            var lastMeaningful: Character = " "
            while i < code.endIndex {
                if code[i] == "\"" || code[i] == "'" || code[i] == "{" {
                    _ = skipDelimited(&i)
                    lastMeaningful = "x"
                    continue
                }
                if code[i] == ">" {
                    i = code.index(after: i)
                    return lastMeaningful == "/"
                }
                if !code[i].isWhitespace { lastMeaningful = code[i] }
                i = code.index(after: i)
            }
            return false
        }

        if finishOpeningTag(&cursor) { return open.lowerBound..<cursor }

        // Paired element: balance `<tag …>` against `</tag>`. Only the same
        // tag name matters — a different nested element cannot close this one.
        var depth = 1
        while cursor < code.endIndex, depth > 0 {
            guard let next = code.range(of: "<", range: cursor..<code.endIndex) else { break }
            var i = next.upperBound
            let closing = i < code.endIndex && code[i] == "/"
            if closing { i = code.index(after: i) }
            let start = i
            while i < code.endIndex, code[i].isLetter || code[i].isNumber
                    || code[i] == "_" || code[i] == "$" || code[i] == "." {
                i = code.index(after: i)
            }
            guard String(code[start..<i]) == tag else { cursor = next.upperBound; continue }
            if closing {
                while i < code.endIndex, code[i] != ">" { i = code.index(after: i) }
                if i < code.endIndex { i = code.index(after: i) }
                depth -= 1
                cursor = i
                if depth == 0 { return open.lowerBound..<cursor }
            } else {
                if !finishOpeningTag(&i) { depth += 1 }
                cursor = i
            }
        }
        return open.lowerBound..<code.endIndex
    }

    /// Whether a snippet is JSX rather than markup: it opens with a tag and
    /// names at least one capitalized component. Real HTML has no
    /// uppercase-initial tag names, so plain markup helpers stay markup.
    static func isJSXUsage(_ code: String) -> Bool {
        let body = strippingLeadingModuleLines(fromMarkup: code)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return body.hasPrefix("<") && body.range(of: "<[A-Z]", options: .regularExpression) != nil
    }

    private static let typescriptPresets = #"[["typescript", { "allExtensions": true }]]"#

    private static func language(for flavor: WebPreviewFlavor) -> SupportedLanguage {
        switch flavor {
        case .html: return .html
        case .css: return .css
        case .javascript: return .javascript
        case .typescript: return .typescript
        case .react: return .react
        case .glsl: return .glsl
        }
    }

    // MARK: - HTML

    private static func htmlDocument(
        code: String,
        appearance: Appearance,
        prependedHTML: String = "",
        extraCSS: String = "",
        helperScript: String = "",
        needsBabel: Bool = false,
        runtime: PreviewRuntime? = nil,
        bootstrap: Bool = false
    ) -> String {
        let bootstrapCSS = runtime.map { bootstrapStyle($0, if: bootstrap) } ?? ""
        let bootstrapJS = runtime.map { bootstrapScript($0, if: bootstrap) } ?? ""
        let hasExtras = !prependedHTML.isEmpty || !extraCSS.isEmpty || !helperScript.isEmpty
            || !bootstrapCSS.isEmpty
        if code.range(of: "<html", options: .caseInsensitive) != nil {
            // Full-document passthrough. With connections the extras are
            // injected into the document itself — wrapping a complete <html>
            // document inside the skeleton's <body> is invalid markup that
            // WebKit renders unpredictably.
            //
            // The CSP goes in unconditionally, before the `hasExtras` shortcut:
            // a passthrough document that needs no extras is still snippet code
            // about to run, and without the meta tag it would inherit no policy
            // at all — free to pull remote scripts and beacon out through
            // subresource loads the navigation delegate never sees.
            var doc = insertingCSP(into: code, allowsCDNModules: false)
            guard hasExtras else { return doc }
            // Ahead of the snippet's own CSS so its overrides still win, and
            // it supersedes the CDN <link> such documents usually carry — that
            // link resolves to nothing here.
            if !bootstrapCSS.isEmpty {
                doc = inserting(bootstrapCSS, before: "</head>", in: doc, fallbackPrefix: true)
            }
            if !bootstrapJS.isEmpty {
                doc = inserting(bootstrapJS, before: "</body>", in: doc, fallbackPrefix: false)
            }
            if !extraCSS.isEmpty {
                doc = inserting(styleTag(extraCSS), before: "</head>", in: doc, fallbackPrefix: true)
            }
            if !prependedHTML.isEmpty {
                doc = inserting(prependedHTML, afterTag: "<body", in: doc)
            }
            if !helperScript.isEmpty {
                let block = executionBlock(
                    code: helperScript,
                    babel: needsBabel ? runtime?.babel : nil,
                    presets: needsBabel ? typescriptPresets : nil
                )
                doc = inserting(block, before: "</body>", in: doc, fallbackPrefix: false)
            }
            return doc
        }
        var body = ""
        if !prependedHTML.isEmpty { body += prependedHTML + "\n" }
        body += code
        if !helperScript.isEmpty {
            body += "\n" + executionBlock(
                code: helperScript,
                babel: needsBabel ? runtime?.babel : nil,
                presets: needsBabel ? typescriptPresets : nil
            )
        }
        if !bootstrapJS.isEmpty { body += "\n" + bootstrapJS }
        return skeleton(
            appearance: appearance, body: body,
            headExtras: bootstrapCSS + styleTag(extraCSS)
        )
    }

    /// Puts the CSP meta tag as early in `document` as the markup allows.
    ///
    /// Position is load-bearing, not cosmetic: WebKit enforces a meta CSP from
    /// the point it parses it, so a policy appended before `</head>` would let
    /// any `<script src>` or `<link>` above it load unpoliced. Preference order
    /// is therefore immediately after `<head…>`, then after `<html…>`, then the
    /// very front of the document (which also covers fragments that open with
    /// `<html` inside a comment and have no real head).
    ///
    /// A document that already carries its own CSP keeps it — meta policies
    /// intersect rather than override, so ours can only tighten it further.
    static func insertingCSP(into document: String, allowsCDNModules: Bool) -> String {
        let meta = cspMeta(allowsCDNModules: allowsCDNModules)
        for tag in ["<head", "<html"] {
            guard let open = document.range(of: tag, options: .caseInsensitive),
                  let close = document.range(
                    of: ">", options: [], range: open.upperBound..<document.endIndex
                  ) else { continue }
            return document.replacingCharacters(
                in: close.upperBound..<close.upperBound, with: "\n" + meta
            )
        }
        return meta + "\n" + document
    }

    /// Inserts `fragment` on its own line before the first (case-insensitive)
    /// occurrence of `marker`. Malformed documents without the marker get the
    /// fragment prepended or appended instead of losing it.
    private static func inserting(
        _ fragment: String, before marker: String, in document: String, fallbackPrefix: Bool
    ) -> String {
        guard let range = document.range(of: marker, options: .caseInsensitive) else {
            return fallbackPrefix ? fragment + "\n" + document : document + "\n" + fragment
        }
        return document.replacingCharacters(in: range.lowerBound..<range.lowerBound, with: fragment + "\n")
    }

    /// Inserts `fragment` right after the closing `>` of the first tag whose
    /// name starts with `tagPrefix` (e.g. `<body` matches `<body class=…>`).
    /// Without the tag, the fragment is prepended.
    private static func inserting(_ fragment: String, afterTag tagPrefix: String, in document: String) -> String {
        guard let open = document.range(of: tagPrefix, options: .caseInsensitive),
              let close = document.range(of: ">", options: [], range: open.upperBound..<document.endIndex) else {
            return fragment + "\n" + document
        }
        return document.replacingCharacters(in: close.upperBound..<close.upperBound, with: "\n" + fragment)
    }

    // MARK: - CSS

    private static func cssDocument(
        code: String, markup: String = "", appearance: Appearance,
        runtime: PreviewRuntime? = nil, bootstrap: Bool = false
    ) -> String {
        // Snippets that carry their own markup alongside the CSS preview as
        // HTML — but only when no connected markup exists, and only when the
        // tag sits outside comments/strings (`content: "<b>"` is still CSS).
        if markup.isEmpty, containsMarkup(code) {
            return htmlDocument(
                code: code, appearance: appearance, runtime: runtime, bootstrap: bootstrap
            )
        }
        let demoMarkup = """
        <div class="demo">
          <h2>Heading</h2>
          <p>Paragraph with a <a href="#">link</a> and <code>code</code>.</p>
          <button>Button</button>
          <div class="card box item">.card .box .item</div>
        </div>
        """
        let bootstrapJS = runtime.map { bootstrapScript($0, if: bootstrap) } ?? ""
        let body = """
        \(markup.isEmpty ? demoMarkup : markup)
        \(styleTag(code))
        \(bootstrapJS)
        """
        return skeleton(
            appearance: appearance, body: body,
            headExtras: runtime.map { bootstrapStyle($0, if: bootstrap) } ?? ""
        )
    }

    /// Whether `code` contains an HTML tag outside CSS comments and quoted
    /// strings. Internal so tests can pin the routing decision.
    static func containsMarkup(_ code: String) -> Bool {
        var scrubbed = code.replacingOccurrences(
            of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression
        )
        scrubbed = scrubbed.replacingOccurrences(
            of: #""[^"\n]*"|'[^'\n]*'"#, with: "", options: .regularExpression
        )
        return scrubbed.range(of: "<[a-zA-Z]", options: .regularExpression) != nil
    }

    // MARK: - JavaScript / TypeScript

    private static func scriptDocument(
        code: String,
        appearance: Appearance,
        babel: String?,
        presets: String?,
        prependedHTML: String = "",
        extraCSS: String = "",
        runtime: PreviewRuntime? = nil,
        bootstrap: Bool = false
    ) -> String {
        var body = ""
        if !prependedHTML.isEmpty { body += prependedHTML + "\n" }
        body += executionBlock(code: code, babel: babel, presets: presets)
        let bootstrapJS = runtime.map { bootstrapScript($0, if: bootstrap) } ?? ""
        if !bootstrapJS.isEmpty { body += "\n" + bootstrapJS }
        return skeleton(
            appearance: appearance, body: body,
            headExtras: (runtime.map { bootstrapStyle($0, if: bootstrap) } ?? "") + styleTag(extraCSS)
        )
    }

    /// Console panel + script tag that JSON-embeds `code` and evaluates it,
    /// optionally through an inlined Babel with the given presets.
    private static func executionBlock(code: String, babel: String?, presets: String?) -> String {
        let babelTag = babel.map { "<script>\($0)</script>" } ?? ""
        return """
        <pre id="console" class="snippet-console"></pre>
        \(babelTag)
        <script>
        \(consoleShim(errorsOnly: false))
        \(scriptProgram(code: code, useBabel: babel != nil, presets: presets))
        </script>
        """
    }

    /// The user program for JS/TS flavors — one source of truth shared by the
    /// initial document and `sourceUpdateScript`.
    private static func scriptProgram(code: String, useBabel: Bool, presets: String?) -> String {
        let run: String
        if useBabel, let presets {
            run = """
            const __out = Babel.transform(__snippetSource, { presets: \(presets), filename: "snippet.ts" });
            (0, eval)(__out.code);
            """
        } else {
            run = "(0, eval)(__snippetSource);"
        }
        return """
        const __snippetSource = \(jsonLiteral(code));
        try {
          \(run)
        } catch (e) {
          __snippetConsole.append("error", __snippetErrorText(e));
        }
        """
    }

    // MARK: - React

    private static func reactDocument(
        code: String,
        appearance: Appearance,
        runtime: PreviewRuntime,
        helperScript: String = "",
        prependedHTML: String = "",
        extraCSS: String = "",
        bootstrap: Bool = false,
        policy: Policy = .denied
    ) -> String {
        // Babel output is strict-mode, so declarations inside eval() stay
        // scoped to it: the component must be captured from within the
        // evaluated source, not probed from the shim afterwards. Mount-target
        // detection uses the entry code only — helpers never become the root.
        // Stripped react imports leave hooks unbound; the UMD runtime only
        // exposes the React/ReactDOM globals. (All handled in `reactSource`.)
        let (source, cdnSpecifiers) = reactSource(
            code: code, helperScript: helperScript, policy: policy
        )
        var body = ""
        if !prependedHTML.isEmpty { body += prependedHTML + "\n" }
        body += """
        \(tailwindBlock(runtime.tailwind))
        <div id="root"></div>
        <pre id="console" class="snippet-console"></pre>
        <script>\(runtime.react)</script>
        <script>\(runtime.reactDOM)</script>
        <script>\(runtime.babel)</script>
        <script>
        \(consoleShim(errorsOnly: true))
        \(reactProgram(source: source, cdn: cdnSpecifiers))
        </script>
        \(bootstrapScript(runtime, if: bootstrap))
        """
        return skeleton(
            appearance: appearance, body: body,
            headExtras: bootstrapStyle(runtime, if: bootstrap) + styleTag(extraCSS),
            // Only a grant widens the CSP. A snippet with npm imports the user
            // has not approved renders under the closed policy, so even the
            // loader's own `import()` would be blocked — belt to the braces of
            // simply not emitting it.
            allowsCDNModules: !cdnSpecifiers.allowed.isEmpty
        )
    }

    /// The transform+mount program for the React flavor — one source of truth
    /// shared by the initial document and `sourceUpdateScript`. The root is
    /// kept on `window` so an update can re-render without a second
    /// `createRoot` on the same container.
    private static func reactProgram(source: String, cdn: CDNModules) -> String {
        // npm packages resolve through esm.sh; loaded modules are cached on
        // `window.__snippetModules` so source updates don't re-fetch.
        let loader = cdn.allowed.isEmpty ? "" : """
          window.__snippetModules = window.__snippetModules || {};
          for (const __spec of [\(cdn.allowed.map(jsonLiteral).joined(separator: ", "))]) {
            if (!window.__snippetModules[__spec]) {
              window.__snippetModules[__spec] = await import("https://esm.sh/" + __spec);
            }
          }
        """
        // Denied imports fail loudly rather than as a bare "X is not defined"
        // twenty lines into someone else's minified component.
        let blocked = cdn.blocked.isEmpty ? "" : """
          __snippetConsole.append("error", \(jsonLiteral(
            "Blocked npm import(s): " + cdn.blocked.joined(separator: ", ")
              + ". Allow this snippet to load packages from esm.sh to run it."
          )));
        """
        return """
        const __snippetSource = \(jsonLiteral(source));
        // Tailwind can only see a component's utility classes once React has
        // put them in the DOM, so the stylesheet for them lands a tick after
        // mount — by which time any component that measured its own container
        // (every canvas/WebGL one) has latched a pre-layout size. They all
        // re-measure on window resize, so replaying that as the stylesheet
        // appears and grows repairs the size without knowing anything about
        // them. Mounting is never *blocked* on Tailwind: waiting on a compile
        // that may be slow (or on rAF, which a background window throttles to
        // a crawl) leaves the preview empty for as long as it takes.
        // Scoped to <head>, where Tailwind injects, so React's own DOM writes
        // in <body> can't feed a resize back into a component that resizes.
        function __snippetSettleLayout() {
          if (!document.querySelector('style[type="text/tailwindcss"]')) return;
          let frame = 0;
          const nudge = () => {
            cancelAnimationFrame(frame);
            frame = requestAnimationFrame(() => window.dispatchEvent(new Event("resize")));
          };
          const observer = new MutationObserver(nudge);
          observer.observe(document.head, { childList: true, characterData: true, subtree: true });
          setTimeout(() => {
            observer.disconnect();
            nudge();
          }, 1500);
        }
        // Re-applies prop overrides onto the previewed component wherever it
        // appears inside a usage snippet's JSX (`<div …><CursorGrid … /></div>`).
        // Assigned to `window` because the snippet runs through indirect eval,
        // which only sees globals — and on the update path this whole program
        // is wrapped in an IIFE.
        window.__snippetOverride = (node, target, overrides) => {
          if (!overrides || !target || !React.isValidElement(node)) return node;
          if (node.type === target) return React.cloneElement(node, overrides);
          const children = node.props && node.props.children;
          if (children === undefined || children === null) return node;
          return React.cloneElement(node, undefined, React.Children.map(
            children, (child) => window.__snippetOverride(child, target, overrides)
          ));
        };
        async function __snippetMount() {
        \(blocked)
        \(loader)
          // Discards a mount whose awaits were overtaken by a newer source
          // update (the update path declares `__generation` in its wrapping
          // IIFE; the document path has none).
          if (typeof __generation !== "undefined" && __generation !== window.__previewGeneration) { return; }
          const out = Babel.transform(__snippetSource, {
            presets: [["react"], ["typescript", { "isTSX": true, "allExtensions": true }]],
            filename: "snippet.tsx"
          });
          (0, eval)(out.code);
          const component = window.__SnippetExport;
          if (!component) { throw new Error("No component found — export a default component or define one named App."); }
          window.__previewRoot = window.__previewRoot || ReactDOM.createRoot(document.getElementById("root"));
          window.__snippetRender = (overrides) => {
            if (overrides !== undefined) window.__snippetPropOverrides = overrides;
            window.__previewRoot.render(
              React.createElement(component, window.__snippetPropOverrides || null)
            );
          };
          window.__snippetRender();
          __snippetSettleLayout();
        }
        __snippetMount().catch((e) => {
          __snippetConsole.append("error", __snippetErrorText(e));
        });
        """
    }

    /// The complete evaluated React source (helpers stripped and prepended,
    /// hook bindings, export capture) — shared by document and update paths.
    private static func reactSource(
        code: String, helperScript: String, policy: Policy = .denied
    ) -> (source: String, cdnSpecifiers: CDNModules) {
        // npm imports beyond the bundled react/react-dom are stripped like the
        // rest of the module syntax, then re-bound from the CDN modules that
        // `reactProgram` awaits into `window.__snippetModules` before eval —
        // but only where the policy allows the fetch. Denied, the bindings are
        // left out too: they would resolve to `undefined` members of an empty
        // module map and fail further from the cause than the console error.
        let fullCode = helperScript + "\n" + code
        let cdnSpecifiers = CDNModules(
            detected: unsupportedImports(in: fullCode), policy: policy
        )
        let bindings = cdnSpecifiers.allowed.isEmpty ? "" : cdnImportBindings(in: fullCode)
        var source = stripModuleSyntax(code, rewriteDefaultExport: true)
        // A helper that is a bare JSX expression is a usage/demo snippet: it
        // references the entry's component, so it must run AFTER the entry
        // (prepending it hits the const's temporal dead zone), wrapped as a
        // component so the element actually renders — as the mount target.
        let target = reactMountTarget(in: code).map { "(typeof \($0) !== \"undefined\" ? \($0) : null)" } ?? "null"
        var usageComponent = ""
        if !helperScript.isEmpty {
            let strippedHelper = stripModuleSyntax(helperScript, rewriteDefaultExport: false)
            var trimmed = strippedHelper.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<") {
                // Only the first preset — see `firstJSXElement`.
                if let first = firstJSXElement(in: trimmed) {
                    trimmed = String(trimmed[first])
                }
                while trimmed.hasSuffix(";") { trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
                // The usage snippet hard-codes its props, so rendering it as-is
                // would swallow every parameter control: the shim hands prop
                // overrides to the mount target, which here is the wrapper, not
                // the component. `__snippetOverride` re-applies them onto the
                // component's own element wherever it sits in the usage tree.
                usageComponent = """


                const __SnippetUsage = (__props) => window.__snippetOverride((<>
                \(trimmed)
                </>), \(target), __props);
                """
            } else {
                source = strippedHelper + "\n\n" + source
            }
        }
        source = bindings + """
        const { useState, useEffect, useRef, useMemo, useCallback, useContext,
                useReducer, useLayoutEffect, useId, Fragment, createElement } = React;

        """ + source

        source += usageComponent + """


        window.__SnippetExport = (typeof __SnippetUsage !== "undefined" && __SnippetUsage) || (typeof __SnippetDefault !== "undefined" && __SnippetDefault) || \(target);
        """
        return (source, cdnSpecifiers)
    }

    /// `const` declarations that re-create the bindings of every stripped CDN
    /// import from the corresponding `window.__snippetModules` entry. Handles
    /// default, namespace (`* as N`), and named (`{ a, b as c }`) clauses;
    /// side-effect imports load but bind nothing. Prepended to the evaluated
    /// source, so the declarations live in the same eval scope as the snippet.
    static func cdnImportBindings(in code: String) -> String {
        let pattern = #"(?m)^[ \t]*import\b([\s\S]*?)\bfrom[ \t]*["']([^"'\n]*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return "" }
        let fullRange = NSRange(code.startIndex..., in: code)
        var lines: [String] = []
        // Connected snippets often repeat the entry's imports; a name bound
        // once must not produce a second `const` (SyntaxError at eval).
        var declared: Set<String> = []
        for match in regex.matches(in: code, range: fullRange) {
            guard let clauseRange = Range(match.range(at: 1), in: code),
                  let specRange = Range(match.range(at: 2), in: code) else { continue }
            let spec = String(code[specRange])
            guard !spec.hasPrefix("."), !spec.hasPrefix("/"),
                  spec != "react", spec != "react-dom",
                  !spec.hasPrefix("react/"), !spec.hasPrefix("react-dom/")
            else { continue }
            let clause = String(code[clauseRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let module = "window.__snippetModules[\(jsonLiteral(spec))]"

            if let namespaceName = firstMatch(#"\*\s*as\s+([A-Za-z_$][\w$]*)"#, in: clause),
               declared.insert(namespaceName).inserted {
                lines.append("const \(namespaceName) = \(module);")
            }
            if let namedBody = firstMatch(#"\{([\s\S]*?)\}"#, in: clause) {
                let entries = namedBody.split(separator: ",").compactMap { part -> String? in
                    let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return nil }
                    let pieces = name.components(separatedBy: " as ")
                    if pieces.count == 2 {
                        let local = pieces[1].trimmingCharacters(in: .whitespaces)
                        guard declared.insert(local).inserted else { return nil }
                        return "\(pieces[0].trimmingCharacters(in: .whitespaces)): \(local)"
                    }
                    guard declared.insert(name).inserted else { return nil }
                    return name
                }
                if !entries.isEmpty {
                    lines.append("const { \(entries.joined(separator: ", ")) } = \(module);")
                }
            }
            if let defaultName = firstMatch(#"^([A-Za-z_$][\w$]*)"#, in: clause), defaultName != "type",
               declared.insert(defaultName).inserted {
                lines.append("const \(defaultName) = (\(module).default !== undefined ? \(module).default : \(module));")
            }
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n\n"
    }

    /// A JSX usage snippet saved with language HTML (capitalized component
    /// tags historically mis-detected) reaches the preview as prepended
    /// markup, where the browser renders its leading `import` lines as
    /// literal text. Leading module statements can never be meaningful
    /// markup, so drop that leading run — imports inside `<script>` blocks
    /// further down stay untouched.
    static func strippingLeadingModuleLines(fromMarkup html: String) -> String {
        html.replacingOccurrences(
            of: #"\A(?:\s*import\b[\s\S]*?["'][^"'\n]*["'][ \t]*;?)+[ \t]*\n?"#,
            with: "", options: .regularExpression
        )
    }

    /// Rewrites module syntax that Babel's script-mode transform won't accept.
    /// Imports are satisfied by the inlined globals. The entry's default
    /// export becomes the well-known `__SnippetDefault` binding; helper
    /// default exports keep their declaration but lose the export marker.
    /// Internal (not private) so tests can pin the stripping behavior.
    static func stripModuleSyntax(_ code: String, rewriteDefaultExport: Bool) -> String {
        // An import statement always ends at its module string literal, so
        // match through it non-greedily — this removes multi-line named
        // imports (the ReactBits convention) that a line-based strip leaves
        // half-behind, breaking Babel with "} from" residue.
        var source = code.replacingOccurrences(
            of: #"(?m)^[ \t]*import\b[\s\S]*?["'][^"'\n]*["'][ \t]*;?"#,
            with: "", options: .regularExpression
        )
        // Export lists (`export { A, B };`, optionally multi-line or
        // re-exporting from a module) vanish entirely; the generic marker
        // strip below would leave a bare block behind.
        source = source.replacingOccurrences(
            of: #"(?m)^[ \t]*export[ \t]*\{[\s\S]*?\}([ \t]*from[ \t]*["'][^"'\n]*["'])?[ \t]*;?"#,
            with: "", options: .regularExpression
        )
        if rewriteDefaultExport {
            // `export default function Strands() {}` is a *declaration*. Turning
            // it into `const __SnippetDefault = function Strands() {}` makes it a
            // named function *expression*, whose name binds only inside its own
            // body — so a usage snippet's `<Strands />` throws "Strands is not
            // defined". Keep the declaration and alias it instead.
            let named = firstMatch(#"export\s+default\s+(?:async\s+)?function\s+([A-Za-z_$][\w$]*)"#, in: source)
                ?? firstMatch(#"export\s+default\s+class\s+([A-Za-z_$][\w$]*)"#, in: source)
            if let named {
                source = source.replacingOccurrences(
                    of: #"export\s+default\s+(?=(?:async\s+)?function\b|class\b)"#,
                    with: "", options: .regularExpression
                )
                source += "\n\nconst __SnippetDefault = \(named);"
            } else {
                source = source.replacingOccurrences(of: "export default", with: "const __SnippetDefault =")
            }
        } else {
            source = source.replacingOccurrences(of: "export default function", with: "function")
            source = source.replacingOccurrences(of: "export default class", with: "class")
            source = source.replacingOccurrences(of: "export default", with: "void")
        }
        return source.replacingOccurrences(
            of: #"(?m)^\s*export\s+"#, with: "", options: .regularExpression
        )
    }

    /// Module specifiers the preview cannot satisfy: anything that is not a
    /// relative path (relative imports are covered by connected snippets and
    /// stripped CSS imports) or the bundled react/react-dom globals. Used to
    /// warn instead of failing with a bare "x is not defined".
    static func unsupportedImports(in code: String) -> [String] {
        let specifiers = allMatches(
            #"(?m)^[ \t]*import\b[\s\S]*?["']([^"'\n]*)["']"#, in: code
        )
        var seen: Set<String> = []
        return specifiers.filter { spec in
            guard !spec.hasPrefix("."), !spec.hasPrefix("/"),
                  spec != "react", spec != "react-dom",
                  !spec.hasPrefix("react/"), !spec.hasPrefix("react-dom/")
            else { return false }
            return seen.insert(spec).inserted
        }
    }

    /// Which top-level identifier the react shim should render, mirroring the
    /// reactbits convention: default export, then `App`, then the last
    /// capitalized top-level declaration. Nil when only an anonymous default
    /// export exists (the shim's `__SnippetDefault` binding covers that).
    static func reactMountTarget(in code: String) -> String? {
        if let name = firstMatch(#"export\s+default\s+function\s+([A-Z]\w*)"#, in: code) {
            return name
        }
        if code.range(of: #"export\s+default\b"#, options: .regularExpression) != nil {
            return firstMatch(#"export\s+default\s+([A-Z]\w*)"#, in: code)
        }
        if code.range(of: #"(?:function|const|let|var|class)\s+App\b"#, options: .regularExpression) != nil {
            return "App"
        }
        return allMatches(#"(?:function|const|let|var|class)\s+([A-Z]\w*)"#, in: code).last
    }

    // MARK: - GLSL

    private static func glslDocument(code: String, appearance: Appearance) -> String {
        // Fragment-only snippets (shadertoy-style) get a prelude declaring the
        // version, precision, standard uniforms and output; full shaders with
        // their own #version pass through untouched.
        let fragment: String
        if code.contains("#version") {
            fragment = code
        } else {
            fragment = """
            #version 300 es
            /*snippet-glsl-header*/
            precision highp float;
            uniform float iTime;
            uniform vec2 iResolution;
            uniform vec4 iMouse;
            out vec4 fragColor;
            \(code)
            """
        }
        let body = """
        <canvas id="glcanvas"></canvas>
        <pre id="console" class="snippet-console"></pre>
        <script>
        \(consoleShim(errorsOnly: true))
        // Custom uniforms drive the preview's parameter controls: overrides
        // arrive via the same __snippetRender(overrides) hook the React
        // flavor uses, and are applied every frame.
        const __customUniforms = \(glslUniformsJSON(in: fragment));
        window.__snippetRender = (overrides) => {
          if (overrides !== undefined) window.__snippetPropOverrides = overrides;
        };
        function __snippetHexToRGB(hex) {
          let d = hex.startsWith("#") ? hex.slice(1) : hex;
          if (d.length === 3) d = d.split("").map((c) => c + c).join("");
          const v = parseInt(d, 16);
          return isNaN(v) ? [0, 0, 0] : [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255];
        }
        function __applyCustomUniforms(gl) {
          const overrides = window.__snippetPropOverrides || {};
          for (const u of __customUniforms) {
            if (!u.loc) continue;
            const v = overrides[u.name] !== undefined ? overrides[u.name] : u.def;
            if (u.type === "float") gl.uniform1f(u.loc, Number(v));
            else if (u.type === "int") gl.uniform1i(u.loc, Math.round(Number(v)));
            else if (u.type === "bool") gl.uniform1i(u.loc, v ? 1 : 0);
            else if (u.type === "color") {
              const c = __snippetHexToRGB(String(v));
              if (u.size === 4) gl.uniform4f(u.loc, c[0], c[1], c[2], 1.0);
              else gl.uniform3f(u.loc, c[0], c[1], c[2]);
            }
          }
        }
        const __fragmentSource = \(jsonLiteral(fragment));
        const __vertexSource = ["#version 300 es", "in vec2 p;", "void main() { gl_Position = vec4(p, 0.0, 1.0); }"].join("\\n");
        const canvas = document.getElementById("glcanvas");
        const gl = canvas.getContext("webgl2");
        if (!gl) {
          __snippetConsole.append("error", "WebGL2 unavailable");
        } else {
          function compile(type, src) {
            const s = gl.createShader(type);
            gl.shaderSource(s, src);
            gl.compileShader(s);
            if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
              throw new Error(gl.getShaderInfoLog(s));
            }
            return s;
          }
          try {
            const program = gl.createProgram();
            gl.attachShader(program, compile(gl.VERTEX_SHADER, __vertexSource));
            gl.attachShader(program, compile(gl.FRAGMENT_SHADER, __fragmentSource));
            gl.linkProgram(program);
            if (!gl.getProgramParameter(program, gl.LINK_STATUS)) {
              throw new Error(gl.getProgramInfoLog(program));
            }
            gl.useProgram(program);
            const buf = gl.createBuffer();
            gl.bindBuffer(gl.ARRAY_BUFFER, buf);
            gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1,-1, 3,-1, -1,3]), gl.STATIC_DRAW);
            const loc = gl.getAttribLocation(program, "p");
            gl.enableVertexAttribArray(loc);
            gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
            const uTime = gl.getUniformLocation(program, "iTime");
            const uResolution = gl.getUniformLocation(program, "iResolution");
            const uMouse = gl.getUniformLocation(program, "iMouse");
            for (const u of __customUniforms) u.loc = gl.getUniformLocation(program, u.name);
            let mouse = [0, 0, 0, 0];
            canvas.addEventListener("pointermove", (e) => {
              const r = canvas.getBoundingClientRect();
              mouse[0] = (e.clientX - r.left) * devicePixelRatio;
              mouse[1] = (r.height - (e.clientY - r.top)) * devicePixelRatio;
            });
            canvas.addEventListener("pointerdown", () => { mouse[2] = 1; });
            canvas.addEventListener("pointerup", () => { mouse[2] = 0; });
            const start = performance.now();
            function frame() {
              const w = canvas.clientWidth * devicePixelRatio;
              const h = canvas.clientHeight * devicePixelRatio;
              if (canvas.width !== w || canvas.height !== h) {
                canvas.width = w; canvas.height = h;
              }
              gl.viewport(0, 0, w, h);
              if (uTime) gl.uniform1f(uTime, (performance.now() - start) / 1000);
              if (uResolution) gl.uniform2f(uResolution, w, h);
              if (uMouse) gl.uniform4f(uMouse, mouse[0], mouse[1], mouse[2], mouse[3]);
              __applyCustomUniforms(gl);
              gl.drawArrays(gl.TRIANGLES, 0, 3);
              requestAnimationFrame(frame);
            }
            frame();
          } catch (e) {
            __snippetConsole.append("error", String(e && e.message || e));
          }
        }
        </script>
        """
        return skeleton(
            appearance: appearance,
            body: body,
            extraCSS: "#glcanvas { position: absolute; inset: 0; width: 100%; height: 100%; display: block; }"
        )
    }

    /// JSON array describing the shader's tweakable uniforms for the in-page
    /// application loop — `[{"name":…,"type":…,"size":…,"def":…}]`.
    private static func glslUniformsJSON(in fragment: String) -> String {
        let entries = PreviewParamDetector.glslParams(in: fragment).compactMap { param -> String? in
            let name = jsonLiteral(param.name)
            switch param.kind {
            case .number(let def):
                return #"{"name": \#(name), "type": "float", "def": \#(def)}"#
            case .integer(let def):
                return #"{"name": \#(name), "type": "int", "def": \#(def)}"#
            case .boolean(let def):
                return #"{"name": \#(name), "type": "bool", "def": \#(def)}"#
            case .color(let hex):
                let isVec4 = fragment.range(
                    of: #"uniform\s+vec4\s+\#(param.name)\b"#, options: .regularExpression
                ) != nil
                return #"{"name": \#(name), "type": "color", "size": \#(isVec4 ? 4 : 3), "def": \#(jsonLiteral(hex))}"#
            case .text, .choice:
                return nil
            }
        }
        return "[" + entries.joined(separator: ", ") + "]"
    }

    // MARK: - Incremental updates

    /// JS that re-renders the mounted React component with the given prop
    /// overrides — the live path behind the preview's parameter controls.
    /// No transform, no reload: just a render with merged props.
    static func propsUpdateScript(overrides: [String: PreviewParamValue]) -> String {
        let entries = overrides
            .sorted { $0.key < $1.key }
            .map { "\(jsonLiteral($0.key)): \($0.value.jsonLiteral)" }
            .joined(separator: ", ")
        return """
        if (typeof window.__snippetRender === "function") {
          window.__snippetRender({ \(entries) });
        }
        """
    }

    /// JS that retints an already-loaded shell in place — theme flips must
    /// not re-parse the inlined runtimes.
    static func themeUpdateScript(appearance: Appearance) -> String {
        """
        (function() {
          const s = document.documentElement.style;
          s.setProperty("--preview-bg", \(jsonLiteral(appearance.backgroundHex)));
          s.setProperty("--preview-text", \(jsonLiteral(appearance.textHex)));
          const meta = document.querySelector('meta[name="color-scheme"]');
          if (meta) meta.setAttribute("content", \(jsonLiteral(appearance.isDark ? "dark" : "light")));
        })();
        """
    }

    /// JS that re-runs the user program inside the already-loaded shell.
    /// Returns nil for flavors whose shell depends on the source (HTML —
    /// including the full-document passthrough — CSS, and GLSL): those force
    /// a full reload. The program payload is built by the same functions the
    /// document path uses (`scriptProgram` / `reactSource` + `reactProgram`).
    static func sourceUpdateScript(
        linked: [LinkedSource],
        entryFlavor: WebPreviewFlavor,
        policy: Policy = .denied
    ) -> String? {
        guard let entry = linked.last else { return nil }
        let scriptHelpers = helperRoles(in: linked, entryFlavor: entryFlavor).script
        let helperScript = scriptHelpers.map(\.code).joined(separator: "\n\n")
        let helpersNeedBabel = scriptHelpers.contains { $0.language != .javascript }

        let program: String
        switch entryFlavor {
        case .javascript, .typescript:
            let combined = helperScript.isEmpty ? entry.code : helperScript + "\n\n" + entry.code
            // The Babel runtime is only present when the shell was built with
            // it; the view's classifier only takes this path when the flavor
            // (and thus the Babel decision) is unchanged.
            let useBabel = entryFlavor == .typescript || helpersNeedBabel
            program = scriptProgram(
                code: combined, useBabel: useBabel,
                presets: useBabel ? typescriptPresets : nil
            )
        case .react:
            let (source, cdnSpecifiers) = reactSource(
                code: entry.code, helperScript: helperScript, policy: policy
            )
            program = reactProgram(source: source, cdn: cdnSpecifiers)
        case .html, .css, .glsl:
            return nil
        }
        // The IIFE scopes the program's consts (the shell already declared
        // them at top level); the generation counter lets any future async
        // consumer detect that a newer update superseded it.
        return """
        (function() {
          window.__previewGeneration = (window.__previewGeneration || 0) + 1;
          const __generation = window.__previewGeneration;
          const __consoleEl = document.getElementById("console");
          if (__consoleEl) __consoleEl.textContent = "";
          if (__generation !== window.__previewGeneration) { return; }
          \(program)
        })();
        """
    }

    // MARK: - Shared pieces

    /// The preview's Content-Security-Policy, as a `<meta>` tag.
    ///
    /// Everything the preview legitimately needs is inline: 'unsafe-inline'
    /// covers the embedded runtimes and snippet code, 'unsafe-eval' the React
    /// path (Babel output runs via eval). connect-src 'none' is the actual
    /// security payoff — no fetch/XHR/WebSocket egress; img-src data:/blob:
    /// keeps data-URI images working while blocking remote beacons.
    ///
    /// Documents the user opted into npm imports for additionally allow module
    /// loads from esm.sh. That widening is what `import()` needs, and it is
    /// genuinely a hole in the no-egress property: dynamic `import()` is
    /// governed by script-src, not connect-src, so snippet code can encode data
    /// into a specifier and reach the network. It is gated behind an explicit
    /// per-snippet opt-in for exactly that reason — see `Policy`.
    ///
    /// Emitted into *every* document path, skeleton and full-document
    /// passthrough alike (`htmlDocument`), so no preview ever runs unpoliced.
    static func cspMeta(allowsCDNModules: Bool) -> String {
        let scriptSrc = "'unsafe-inline' 'unsafe-eval'" + (allowsCDNModules ? " https://esm.sh" : "")
        return "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src \(scriptSrc); style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'\">"
    }

    private static func skeleton(
        appearance: Appearance,
        body: String,
        extraCSS: String = "",
        headExtras: String = "",
        allowsCDNModules: Bool = false
    ) -> String {
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        \(cspMeta(allowsCDNModules: allowsCDNModules))
        <meta name="color-scheme" content="\(appearance.isDark ? "dark" : "light")">
        <style>
        :root { --preview-bg: \(appearance.backgroundHex); --preview-text: \(appearance.textHex); }
        html, body { margin: 0; padding: 0; height: 100%; }
        body {
          background: var(--preview-bg);
          color: var(--preview-text);
          font: 14px -apple-system, system-ui, sans-serif;
          padding: 16px;
          box-sizing: border-box;
          display: flex;
          flex-direction: column;
        }
        /* The React mount point fills the preview and centers what it mounts,
           mirroring the demo frame every ReactBits component is authored
           against: `h-full`/`w-full` roots need a parent with a real height,
           and a small component reads as placed rather than dropped in the
           top-left corner. */
        #root {
          flex: 1 1 auto;
          min-height: 0;
          display: flex;
          align-items: center;
          justify-content: center;
          overflow: hidden;
        }
        /* Usage snippets frame their demo at a fixed size (`height: 600px`),
           which on the site sits in a page that scrolls. Here the pane is the
           frame, so a taller demo would just be cut off — clipping a glass
           orb's top and bottom. Capping makes it shrink to fit instead; it
           never stretches anything smaller. */
        #root > * { max-width: 100%; max-height: 100%; }
        .snippet-console {
          font: 12px ui-monospace, monospace;
          white-space: pre-wrap;
          margin: 0;
          flex: 0 1 auto;
          overflow: auto;
        }
        /* An untouched console must not reserve space, and a chatty one (a
           component logging from `onChange` on every scroll tick) must not
           push the preview off screen. */
        .snippet-console:empty { display: none; }
        #root ~ .snippet-console { max-height: 33%; }
        .snippet-console .error { color: #ff6b6b; }
        \(extraCSS)
        </style>\(headExtras)
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// Tailwind's browser build plus the stylesheet it compiles against.
    /// Importing `theme` and `utilities` directly (rather than the umbrella
    /// `tailwindcss`) deliberately skips Preflight: the reset would strip the
    /// native look off every `<h2>`/`<button>` in non-Tailwind React snippets.
    /// Only `border-box` is reinstated, because utility padding scales assume
    /// it. Both specifiers are bundled in the build, so nothing is fetched —
    /// which matters under the skeleton's `connect-src 'none'`.
    private static func tailwindBlock(_ tailwind: String) -> String {
        guard !tailwind.isEmpty else { return "" }
        return """
        <style type="text/tailwindcss">
        @import "tailwindcss/theme" layer(theme);
        @import "tailwindcss/utilities" layer(utilities);
        @layer base { *, ::before, ::after { box-sizing: border-box; } }
        </style>
        <script>\(tailwind)</script>
        """
    }

    /// Bootstrap's stylesheet, as a head fragment. Its own `@charset` rule is
    /// dropped: valid only at the very start of an external stylesheet, it is
    /// meaningless inside a `<style>` tag.
    private static func bootstrapStyle(_ runtime: PreviewRuntime, if needed: Bool) -> String {
        guard needed, !runtime.bootstrapCSS.isEmpty else { return "" }
        let css = runtime.bootstrapCSS.replacingOccurrences(
            of: #"^@charset\s+"[^"]*";"#, with: "", options: .regularExpression
        )
        return styleTag(css)
    }

    /// Bootstrap's JS bundle, as a body fragment. Dropdowns, modals, tabs,
    /// carousels and tooltips are inert markup without it.
    private static func bootstrapScript(_ runtime: PreviewRuntime, if needed: Bool) -> String {
        guard needed, !runtime.bootstrapJS.isEmpty else { return "" }
        return "<script>\(runtime.bootstrapJS)</script>"
    }

    /// Style tag for dependency CSS; empty input produces no tag at all so
    /// single-source documents stay byte-identical.
    private static func styleTag(_ css: String) -> String {
        guard !css.isEmpty else { return "" }
        return "<style>\(css.replacingOccurrences(of: "</style", with: "<\\/style"))</style>"
    }

    /// Mirrors console output into the in-page panel so JS snippets have
    /// visible output without the web inspector.
    ///
    /// `errorsOnly` is for the React flavor, where the preview *is* the
    /// output: a component wired to `onChange={(i, x) => console.log(i, x)}`
    /// — the ReactBits house style — otherwise paints a running list of its
    /// own options over the demo. Errors still surface, and everything still
    /// reaches the web inspector.
    private static func consoleShim(errorsOnly: Bool) -> String {
        """
    const __snippetConsole = {
      el: document.getElementById("console"),
      // A component that logs on every animation/scroll tick would otherwise
      // grow the panel without bound; only the newest lines are worth keeping.
      limit: 200,
      errorsOnly: \(errorsOnly),
      append(level, text) {
        if (!this.el) return;
        if (this.errorsOnly && level !== "error") return;
        const line = document.createElement("div");
        if (level === "error") line.className = "error";
        line.textContent = text;
        this.el.appendChild(line);
        while (this.el.childElementCount > this.limit) {
          this.el.removeChild(this.el.firstElementChild);
        }
        this.el.scrollTop = this.el.scrollHeight;
      }
    };
    for (const level of ["log", "info", "warn", "error"]) {
      const original = console[level].bind(console);
      console[level] = (...args) => {
        original(...args);
        __snippetConsole.append(level, args.map(a => {
          try { return typeof a === "string" ? a : JSON.stringify(a); }
          catch { return String(a); }
        }).join(" "));
      };
    }
    window.addEventListener("error", (e) => {
      // Errors inside cross-origin (CDN module) callbacks are muted by the
      // browser to a bare "Script error." with no location — pure noise.
      if (e.message === "Script error." && !e.filename) return;
      __snippetConsole.append("error", e.message);
    });
    // WebKit's Error.stack omits the "Name: message" head line, so a bare
    // `e.stack` renders as an anonymous stack — always prepend the head.
    function __snippetErrorText(e) {
      if (!e) return String(e);
      const head = e.name ? e.name + ": " + e.message : String(e);
      return e.stack ? head + "\\n" + e.stack : head;
    }
    """
    }

    /// JSON string literal for safe embedding inside <script> — JSONEncoder
    /// escapes forward slashes, so "</script>" can never terminate the tag.
    private static func jsonLiteral(_ string: String) -> String {
        let data = (try? JSONEncoder().encode([string])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        allMatches(pattern, in: text).first
    }

    private static func allMatches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }
}

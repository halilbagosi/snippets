import Foundation

/// Builds self-contained HTML documents for the WKWebView preview engine.
/// Pure string → string; no WebKit dependency so it stays unit-testable.
enum WebPreviewHTMLBuilder {
    struct Appearance {
        let isDark: Bool
        let backgroundHex: String
        let textHex: String
    }

    /// Vendored runtime scripts, inlined into the document so previews work
    /// offline and never depend on file-URL resource loading.
    struct ReactRuntime {
        let react: String
        let reactDOM: String
        let babel: String
    }

    static func document(
        code: String,
        flavor: WebPreviewFlavor,
        appearance: Appearance,
        runtime: ReactRuntime
    ) -> String {
        document(
            linked: [LinkedSource(language: language(for: flavor), code: code)],
            entryFlavor: flavor,
            appearance: appearance,
            runtime: runtime
        )
    }

    /// Combined document for a snippet plus its resolved dependencies
    /// (helpers first, entry last — see `SnippetLinker`). Dependency CSS is
    /// injected as a style block, dependency HTML is prepended above the
    /// entry markup, and dependency JS/TS/React runs before the entry code.
    static func document(
        linked: [LinkedSource],
        entryFlavor: WebPreviewFlavor,
        appearance: Appearance,
        runtime: ReactRuntime
    ) -> String {
        guard let entry = linked.last else {
            return skeleton(appearance: appearance, body: "")
        }
        let helpers = linked.dropLast()
        let css = helpers.filter { $0.language == .css }.map(\.code).joined(separator: "\n\n")
        let html = helpers.filter { $0.language == .html }
            .map { strippingLeadingModuleLines(fromMarkup: $0.code) }
            .joined(separator: "\n")
        let scriptHelpers = helpers.filter { [.javascript, .typescript, .react].contains($0.language) }
        let helperScript = scriptHelpers.map(\.code).joined(separator: "\n\n")
        let helpersNeedBabel = scriptHelpers.contains { $0.language != .javascript }

        switch entryFlavor {
        case .html:
            return htmlDocument(
                code: entry.code, appearance: appearance,
                prependedHTML: html, extraCSS: css,
                helperScript: helperScript, needsBabel: helpersNeedBabel, runtime: runtime
            )
        case .css:
            let helperCSS = helpers.filter { $0.language == .css }.map(\.code)
            return cssDocument(
                code: (helperCSS + [entry.code]).joined(separator: "\n\n"),
                markup: html,
                appearance: appearance
            )
        case .javascript, .typescript:
            let combined = helperScript.isEmpty ? entry.code : helperScript + "\n\n" + entry.code
            let useBabel = entryFlavor == .typescript || helpersNeedBabel
            return scriptDocument(
                code: combined, appearance: appearance,
                babel: useBabel ? runtime.babel : nil,
                presets: useBabel ? typescriptPresets : nil,
                prependedHTML: html, extraCSS: css
            )
        case .react:
            return reactDocument(
                code: entry.code, appearance: appearance, runtime: runtime,
                helperScript: helperScript, prependedHTML: html, extraCSS: css
            )
        case .glsl:
            let combined = (helpers.filter { $0.language == .glsl }.map(\.code) + [entry.code])
                .joined(separator: "\n\n")
            return glslDocument(code: combined, appearance: appearance)
        }
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
        runtime: ReactRuntime? = nil
    ) -> String {
        let hasExtras = !prependedHTML.isEmpty || !extraCSS.isEmpty || !helperScript.isEmpty
        if code.range(of: "<html", options: .caseInsensitive) != nil {
            // Full-document passthrough. With connections the extras are
            // injected into the document itself — wrapping a complete <html>
            // document inside the skeleton's <body> is invalid markup that
            // WebKit renders unpredictably.
            guard hasExtras else { return code }
            var doc = code
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
        return skeleton(appearance: appearance, body: body, headExtras: styleTag(extraCSS))
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

    private static func cssDocument(code: String, markup: String = "", appearance: Appearance) -> String {
        // Snippets that carry their own markup alongside the CSS preview as
        // HTML — but only when no connected markup exists, and only when the
        // tag sits outside comments/strings (`content: "<b>"` is still CSS).
        if markup.isEmpty, containsMarkup(code) {
            return htmlDocument(code: code, appearance: appearance)
        }
        let demoMarkup = """
        <div class="demo">
          <h2>Heading</h2>
          <p>Paragraph with a <a href="#">link</a> and <code>code</code>.</p>
          <button>Button</button>
          <div class="card box item">.card .box .item</div>
        </div>
        """
        let body = """
        \(markup.isEmpty ? demoMarkup : markup)
        \(styleTag(code))
        """
        return skeleton(appearance: appearance, body: body)
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
        extraCSS: String = ""
    ) -> String {
        var body = ""
        if !prependedHTML.isEmpty { body += prependedHTML + "\n" }
        body += executionBlock(code: code, babel: babel, presets: presets)
        return skeleton(appearance: appearance, body: body, headExtras: styleTag(extraCSS))
    }

    /// Console panel + script tag that JSON-embeds `code` and evaluates it,
    /// optionally through an inlined Babel with the given presets.
    private static func executionBlock(code: String, babel: String?, presets: String?) -> String {
        let babelTag = babel.map { "<script>\($0)</script>" } ?? ""
        return """
        <pre id="console" class="snippet-console"></pre>
        \(babelTag)
        <script>
        \(consoleShim)
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
        runtime: ReactRuntime,
        helperScript: String = "",
        prependedHTML: String = "",
        extraCSS: String = ""
    ) -> String {
        // Babel output is strict-mode, so declarations inside eval() stay
        // scoped to it: the component must be captured from within the
        // evaluated source, not probed from the shim afterwards. Mount-target
        // detection uses the entry code only — helpers never become the root.
        // Stripped react imports leave hooks unbound; the UMD runtime only
        // exposes the React/ReactDOM globals. (All handled in `reactSource`.)
        let (source, cdnSpecifiers) = reactSource(code: code, helperScript: helperScript)
        var body = ""
        if !prependedHTML.isEmpty { body += prependedHTML + "\n" }
        body += """
        <div id="root"></div>
        <pre id="console" class="snippet-console"></pre>
        <script>\(runtime.react)</script>
        <script>\(runtime.reactDOM)</script>
        <script>\(runtime.babel)</script>
        <script>
        \(consoleShim)
        \(reactProgram(source: source, cdnSpecifiers: cdnSpecifiers))
        </script>
        """
        return skeleton(
            appearance: appearance, body: body, headExtras: styleTag(extraCSS),
            allowsCDNModules: !cdnSpecifiers.isEmpty
        )
    }

    /// The transform+mount program for the React flavor — one source of truth
    /// shared by the initial document and `sourceUpdateScript`. The root is
    /// kept on `window` so an update can re-render without a second
    /// `createRoot` on the same container.
    private static func reactProgram(source: String, cdnSpecifiers: [String]) -> String {
        // npm packages resolve through esm.sh; loaded modules are cached on
        // `window.__snippetModules` so source updates don't re-fetch. The
        // `typeof __generation` check discards a mount whose module loads
        // were overtaken by a newer source update (the update path declares
        // `__generation` in its wrapping IIFE; the document path has none).
        let loader = cdnSpecifiers.isEmpty ? "" : """
          window.__snippetModules = window.__snippetModules || {};
          for (const __spec of [\(cdnSpecifiers.map(jsonLiteral).joined(separator: ", "))]) {
            if (!window.__snippetModules[__spec]) {
              window.__snippetModules[__spec] = await import("https://esm.sh/" + __spec);
            }
          }
          if (typeof __generation !== "undefined" && __generation !== window.__previewGeneration) { return; }
        """
        return """
        const __snippetSource = \(jsonLiteral(source));
        async function __snippetMount() {
        \(loader)
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
        }
        __snippetMount().catch((e) => {
          __snippetConsole.append("error", __snippetErrorText(e));
        });
        """
    }

    /// The complete evaluated React source (helpers stripped and prepended,
    /// hook bindings, export capture) — shared by document and update paths.
    private static func reactSource(code: String, helperScript: String) -> (source: String, cdnSpecifiers: [String]) {
        // npm imports beyond the bundled react/react-dom are stripped like the
        // rest of the module syntax, then re-bound from the CDN modules that
        // `reactProgram` awaits into `window.__snippetModules` before eval.
        let fullCode = helperScript + "\n" + code
        let cdnSpecifiers = unsupportedImports(in: fullCode)
        let bindings = cdnImportBindings(in: fullCode)
        var source = stripModuleSyntax(code, rewriteDefaultExport: true)
        // A helper that is a bare JSX expression is a usage/demo snippet: it
        // references the entry's component, so it must run AFTER the entry
        // (prepending it hits the const's temporal dead zone), wrapped as a
        // component so the element actually renders — as the mount target.
        var usageComponent = ""
        if !helperScript.isEmpty {
            let strippedHelper = stripModuleSyntax(helperScript, rewriteDefaultExport: false)
            var trimmed = strippedHelper.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<") {
                while trimmed.hasSuffix(";") { trimmed = String(trimmed.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
                usageComponent = "\n\nconst __SnippetUsage = () => (<>\n\(trimmed)\n</>);"
            } else {
                source = strippedHelper + "\n\n" + source
            }
        }
        source = bindings + """
        const { useState, useEffect, useRef, useMemo, useCallback, useContext,
                useReducer, useLayoutEffect, useId, Fragment, createElement } = React;

        """ + source

        let target = reactMountTarget(in: code).map { "(typeof \($0) !== \"undefined\" ? \($0) : null)" } ?? "null"
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
            source = source.replacingOccurrences(of: "export default", with: "const __SnippetDefault =")
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
        \(consoleShim)
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
        entryFlavor: WebPreviewFlavor
    ) -> String? {
        guard let entry = linked.last else { return nil }
        let helpers = linked.dropLast()
        let scriptHelpers = helpers.filter { [.javascript, .typescript, .react].contains($0.language) }
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
            let (source, cdnSpecifiers) = reactSource(code: entry.code, helperScript: helperScript)
            program = reactProgram(source: source, cdnSpecifiers: cdnSpecifiers)
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

    private static func skeleton(
        appearance: Appearance,
        body: String,
        extraCSS: String = "",
        headExtras: String = "",
        allowsCDNModules: Bool = false
    ) -> String {
        // Everything the preview legitimately needs is inline: 'unsafe-inline'
        // covers the embedded runtimes and snippet code, 'unsafe-eval' the React
        // path (Babel output runs via eval). connect-src 'none' is the actual
        // security payoff — no fetch/XHR/WebSocket egress; img-src data:/blob:
        // keeps data-URI images working while blocking remote beacons.
        // Documents with npm imports additionally allow module loads from
        // esm.sh (script-src only — connect-src stays closed, so snippet code
        // still can't fetch/beacon, even to esm.sh).
        // Note: full-document passthrough snippets bypass this skeleton (and its
        // CSP); the WebPreviewView navigation delegate constrains those instead.
        let scriptSrc = "'unsafe-inline' 'unsafe-eval'" + (allowsCDNModules ? " https://esm.sh" : "")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src \(scriptSrc); style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'">
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
        }
        .snippet-console {
          font: 12px ui-monospace, monospace;
          white-space: pre-wrap;
          margin: 0;
        }
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

    /// Style tag for dependency CSS; empty input produces no tag at all so
    /// single-source documents stay byte-identical.
    private static func styleTag(_ css: String) -> String {
        guard !css.isEmpty else { return "" }
        return "<style>\(css.replacingOccurrences(of: "</style", with: "<\\/style"))</style>"
    }

    /// Mirrors console output into the in-page panel so JS snippets have
    /// visible output without the web inspector.
    private static let consoleShim = """
    const __snippetConsole = {
      el: document.getElementById("console"),
      append(level, text) {
        if (!this.el) return;
        const line = document.createElement("div");
        if (level === "error") line.className = "error";
        line.textContent = text;
        this.el.appendChild(line);
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

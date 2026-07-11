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
        let html = helpers.filter { $0.language == .html }.map(\.code).joined(separator: "\n")
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
            return cssDocument(code: entry.code, appearance: appearance)
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
        if !hasExtras, code.range(of: "<html", options: .caseInsensitive) != nil {
            return code
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

    // MARK: - CSS

    private static func cssDocument(code: String, appearance: Appearance) -> String {
        // Snippets that carry their own markup alongside the CSS preview as HTML.
        if code.range(of: "<[a-zA-Z]", options: .regularExpression) != nil {
            return htmlDocument(code: code, appearance: appearance)
        }
        let body = """
        <div class="demo">
          <h2>Heading</h2>
          <p>Paragraph with a <a href="#">link</a> and <code>code</code>.</p>
          <button>Button</button>
          <div class="card box item">.card .box .item</div>
        </div>
        \(styleTag(code))
        """
        return skeleton(appearance: appearance, body: body)
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
        let run: String
        if babel != nil, let presets {
            run = """
            const __out = Babel.transform(__snippetSource, { presets: \(presets), filename: "snippet.ts" });
            (0, eval)(__out.code);
            """
        } else {
            run = "(0, eval)(__snippetSource);"
        }
        return """
        <pre id="console" class="snippet-console"></pre>
        \(babelTag)
        <script>
        \(consoleShim)
        const __snippetSource = \(jsonLiteral(code));
        try {
          \(run)
        } catch (e) {
          __snippetConsole.append("error", String(e && e.stack || e));
        }
        </script>
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
        var source = stripModuleSyntax(code, rewriteDefaultExport: true)
        if !helperScript.isEmpty {
            source = stripModuleSyntax(helperScript, rewriteDefaultExport: false) + "\n\n" + source
        }
        // Stripped react imports leave hooks unbound; the UMD runtime only
        // exposes the React/ReactDOM globals.
        source = """
        const { useState, useEffect, useRef, useMemo, useCallback, useContext,
                useReducer, useLayoutEffect, useId, Fragment, createElement } = React;

        """ + source

        let target = reactMountTarget(in: code).map { "(typeof \($0) !== \"undefined\" ? \($0) : null)" } ?? "null"
        source += """


        window.__SnippetExport = (typeof __SnippetDefault !== "undefined" && __SnippetDefault) || \(target);
        """
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
        const __snippetSource = \(jsonLiteral(source));
        function __snippetMount() {
          const out = Babel.transform(__snippetSource, {
            presets: [["react"], ["typescript", { "isTSX": true, "allExtensions": true }]],
            filename: "snippet.tsx"
          });
          (0, eval)(out.code);
          const component = window.__SnippetExport;
          if (!component) { throw new Error("No component found — export a default component or define one named App."); }
          ReactDOM.createRoot(document.getElementById("root")).render(React.createElement(component));
        }
        try { __snippetMount(); } catch (e) {
          __snippetConsole.append("error", String(e && e.stack || e));
        }
        </script>
        """
        return skeleton(appearance: appearance, body: body, headExtras: styleTag(extraCSS))
    }

    /// Rewrites module syntax that Babel's script-mode transform won't accept.
    /// Imports are satisfied by the inlined globals. The entry's default
    /// export becomes the well-known `__SnippetDefault` binding; helper
    /// default exports keep their declaration but lose the export marker.
    private static func stripModuleSyntax(_ code: String, rewriteDefaultExport: Bool) -> String {
        var source = code.replacingOccurrences(
            of: #"(?m)^\s*import\s[^\n]*$"#, with: "", options: .regularExpression
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

    // MARK: - Shared pieces

    private static func skeleton(
        appearance: Appearance,
        body: String,
        extraCSS: String = "",
        headExtras: String = ""
    ) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="\(appearance.isDark ? "dark" : "light")">
        <style>
        html, body { margin: 0; padding: 0; height: 100%; }
        body {
          background: \(appearance.backgroundHex);
          color: \(appearance.textHex);
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
    window.addEventListener("error", (e) => __snippetConsole.append("error", e.message));
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

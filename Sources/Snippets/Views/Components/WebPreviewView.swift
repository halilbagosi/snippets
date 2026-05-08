import SwiftUI
import WebKit

// MARK: - HTML Builder

/// Generates themed HTML preview content for every supported language.
enum PreviewHTMLBuilder {

    /// Whether this language can produce a truly "runnable" preview (live DOM output).
    static func isRunnable(_ language: SupportedLanguage) -> Bool {
        switch language {
        case .html, .css, .javascript, .react, .typescript: return true
        default: return false
        }
    }

    static func html(
        for code: String,
        language: SupportedLanguage,
        isDark: Bool,
        compact: Bool
    ) -> String {
        switch language {
        case .html:       return htmlPreview(code, isDark: isDark)
        case .css:        return cssPreview(code, isDark: isDark)
        case .javascript: return jsPreview(code, isDark: isDark)
        case .react:      return reactPreview(code, isDark: isDark)
        case .typescript: return tsPreview(code, isDark: isDark)
        case .json:       return jsonPreview(code, isDark: isDark, compact: compact)
        default:          return codeCardPreview(code, language: language, isDark: isDark, compact: compact)
        }
    }

    // MARK: – Runnable previews

    private static func htmlPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        // Inject base styles if user code doesn't set them
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 12px; font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: \(bg); color: \(isDark ? "#e6edF3" : "#242a30"); }
        </style>
        </head>
        <body>
        \(code)
        </body>
        </html>
        """
    }

    private static func cssPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { box-sizing: border-box; }
        body { display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; background: \(bg); color: \(fg); font-family: -apple-system, sans-serif; padding: 16px; }
        \(code)
        </style>
        </head>
        <body>
        <div class="preview">
          <h2>Heading</h2>
          <p>Preview paragraph text.</p>
          <button>Button</button>
          <a href="#">Link</a>
          <div class="box" style="width:60px;height:60px;margin-top:8px;border:1px solid currentColor;border-radius:6px;"></div>
        </div>
        </body>
        </html>
        """
    }

    private static func jsPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 16px; font-family: -apple-system, monospace; background: \(bg); color: \(fg); font-size: 13px; line-height: 1.5; }
        .output-line { padding: 2px 0; }
        .error { color: #ff6b6b; }
        </style>
        </head>
        <body>
        <div id="output"></div>
        <script>
        (function(){
            const out = document.getElementById('output');
            const _log = console.log;
            console.log = function() {
                const line = document.createElement('div');
                line.className = 'output-line';
                line.textContent = Array.from(arguments).map(a => {
                    if (typeof a === 'object') return JSON.stringify(a, null, 2);
                    return String(a);
                }).join(' ');
                out.appendChild(line);
                _log.apply(console, arguments);
            };
            try {
                \(escaped)
            } catch(e) {
                const line = document.createElement('div');
                line.className = 'output-line error';
                line.textContent = e.toString();
                out.appendChild(line);
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func reactPreview(_ code: String, isDark: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let escaped = code
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: 16px; font-family: -apple-system, sans-serif; background: \(bg); color: \(fg); }
        .error { color: #ff6b6b; font-family: monospace; font-size: 12px; white-space: pre-wrap; padding: 12px; }
        </style>
        <script src="https://unpkg.com/react@18/umd/react.production.min.js" crossorigin></script>
        <script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js" crossorigin></script>
        <script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
        </head>
        <body>
        <div id="root"></div>
        <script>
        (function() {
            try {
                const userCode = `\(escaped)`;
                // Strip import/export statements for in-browser eval
                const cleaned = userCode
                    .replace(/^\\s*import\\s+.*?[;\\n]/gm, '')
                    .replace(/^\\s*export\\s+default\\s+/gm, 'const __DefaultExport__ = ')
                    .replace(/^\\s*export\\s+/gm, '');
                const transpiled = Babel.transform(cleaned, {
                    presets: ['react'],
                    plugins: []
                }).code;
                const module = { exports: {} };
                const fn = new Function('React', 'ReactDOM', 'module', 'exports', 'useState', 'useEffect', 'useRef', 'useMemo', 'useCallback',
                    transpiled + ';\\nreturn typeof __DefaultExport__ !== "undefined" ? __DefaultExport__ : (typeof App !== "undefined" ? App : null);'
                );
                const { useState, useEffect, useRef, useMemo, useCallback } = React;
                const Component = fn(React, ReactDOM, module, module.exports, useState, useEffect, useRef, useMemo, useCallback);
                if (Component) {
                    const root = ReactDOM.createRoot(document.getElementById('root'));
                    root.render(React.createElement(Component));
                } else {
                    document.getElementById('root').innerHTML = '<div class="error">No default export or App component found.</div>';
                }
            } catch(e) {
                document.getElementById('root').innerHTML = '<div class="error">' + e.toString() + '</div>';
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func tsPreview(_ code: String, isDark: Bool) -> String {
        // TypeScript runs as JS after stripping type annotations via regex
        let stripped = code
            .replacingOccurrences(of: #": string"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": number"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": boolean"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": any"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #": void"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[A-Z]\w*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"interface \w+ \{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"type \w+ = [^;]+;"#, with: "", options: .regularExpression)
        return jsPreview(stripped, isDark: isDark)
    }

    // MARK: – JSON viewer

    private static func jsonPreview(_ code: String, isDark: Bool, compact: Bool) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let keyColor = isDark ? "#7ab5ff" : "#2563eb"
        let strColor = isDark ? "#f2cc60" : "#b45309"
        let numColor = isDark ? "#7ab5ff" : "#1d4ed8"
        let boolColor = isDark ? "#ff7b7b" : "#dc2626"
        let fontSize = compact ? "10px" : "12px"
        let escaped = code.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "</script>", with: "<\\/script>")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        body { margin: 0; padding: \(compact ? "8px" : "14px"); font-family: ui-monospace, 'SF Mono', monospace; background: \(bg); color: \(fg); font-size: \(fontSize); line-height: 1.6; overflow: auto; }
        .key { color: \(keyColor); }
        .str { color: \(strColor); }
        .num { color: \(numColor); }
        .bool, .null { color: \(boolColor); }
        .bracket { color: \(isDark ? "#6e7681" : "#8b949e"); }
        .indent { margin-left: 16px; }
        .error { color: #ff6b6b; font-size: 12px; }
        </style>
        </head>
        <body>
        <div id="json-root"></div>
        <script>
        (function(){
            function renderJSON(val, depth) {
                if (val === null) return '<span class="null">null</span>';
                if (typeof val === 'boolean') return '<span class="bool">' + val + '</span>';
                if (typeof val === 'number') return '<span class="num">' + val + '</span>';
                if (typeof val === 'string') return '<span class="str">"' + val.replace(/</g,'&lt;') + '"</span>';
                if (Array.isArray(val)) {
                    if (val.length === 0) return '<span class="bracket">[]</span>';
                    let h = '<span class="bracket">[</span><br>';
                    val.forEach(function(item, i) {
                        h += '<div class="indent">' + renderJSON(item, depth+1) + (i < val.length-1 ? ',' : '') + '</div>';
                    });
                    return h + '<span class="bracket">]</span>';
                }
                if (typeof val === 'object') {
                    const keys = Object.keys(val);
                    if (keys.length === 0) return '<span class="bracket">{}</span>';
                    let h = '<span class="bracket">{</span><br>';
                    keys.forEach(function(k, i) {
                        h += '<div class="indent"><span class="key">"' + k + '"</span>: ' + renderJSON(val[k], depth+1) + (i < keys.length-1 ? ',' : '') + '</div>';
                    });
                    return h + '<span class="bracket">}</span>';
                }
                return String(val);
            }
            try {
                const data = JSON.parse('\(escaped)');
                document.getElementById('json-root').innerHTML = renderJSON(data, 0);
            } catch(e) {
                document.getElementById('json-root').innerHTML = '<div class="error">' + e.toString() + '</div>';
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    // MARK: – Themed code card (all other languages)

    private static func codeCardPreview(
        _ code: String,
        language: SupportedLanguage,
        isDark: Bool,
        compact: Bool
    ) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let gutterColor = isDark ? "#3b4048" : "#b0b8c4"
        let keywordColor = isDark ? "#ff7b72" : "#cf222e"
        let stringColor = isDark ? "#f2cc60" : "#b45309"
        let commentColor = isDark ? "#6e8295" : "#7e8894"
        let typeColor = isDark ? "#7ab5ff" : "#1d4ed8"
        let numberColor = isDark ? "#7ab5ff" : "#1d4ed8"
        let accentHex = language.accentHex
        let fontSize = compact ? "10px" : "12.5px"
        let lineHeight = compact ? "1.5" : "1.65"
        let padding = compact ? "8px 6px" : "14px 12px"

        let keywords = languageKeywords(language)
        let escapedCode = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            background: \(bg);
            font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Fira Code', monospace;
            font-size: \(fontSize);
            line-height: \(lineHeight);
            color: \(fg);
            padding: \(padding);
            overflow: hidden;
        }
        .line { display: flex; }
        .gutter {
            color: \(gutterColor);
            text-align: right;
            padding-right: 12px;
            min-width: \(compact ? "24px" : "32px");
            user-select: none;
            flex-shrink: 0;
        }
        .code-content { white-space: pre; flex: 1; overflow: hidden; }
        .kw { color: \(keywordColor); font-weight: 600; }
        .str { color: \(stringColor); }
        .cmt { color: \(commentColor); font-style: italic; }
        .typ { color: \(typeColor); }
        .num { color: \(numberColor); }
        .accent-bar {
            position: fixed;
            top: 0; left: 0;
            width: 3px;
            height: 100%;
            background: \(accentHex);
            opacity: 0.6;
            border-radius: 0 2px 2px 0;
        }
        </style>
        </head>
        <body>
        <div class="accent-bar"></div>
        <script>
        (function(){
            const raw = \(jsonStringLiteral(escapedCode));
            const keywords = new Set(\(jsonArrayLiteral(keywords)));
            const lines = raw.split('\\n');
            let html = '';
            for (let i = 0; i < lines.length; i++) {
                const num = i + 1;
                const highlighted = highlightLine(lines[i], keywords);
                html += '<div class="line"><span class="gutter">' + num + '</span><span class="code-content">' + highlighted + '</span></div>';
            }
            document.body.insertAdjacentHTML('beforeend', html);

            function highlightLine(line, kws) {
                // Comment detection
                if (line.trimStart().startsWith('//') || line.trimStart().startsWith('#')) {
                    return '<span class="cmt">' + line + '</span>';
                }
                // Simple token-based highlighting
                return line.replace(/(["'`])(?:(?!\\1|\\\\)[\\s\\S]|\\\\.)*?\\1|\\b(\\d+\\.?\\d*(?:[eE][+-]?\\d+)?)\\b|\\b([a-zA-Z_]\\w*)\\b/g,
                    function(m, q, num, word) {
                        if (q) return '<span class="str">' + m + '</span>';
                        if (num) return '<span class="num">' + m + '</span>';
                        if (word && kws.has(word)) return '<span class="kw">' + word + '</span>';
                        if (word && word[0] === word[0].toUpperCase() && word[0] !== word[0].toLowerCase() && word.length > 1)
                            return '<span class="typ">' + word + '</span>';
                        return m;
                    }
                );
            }
        })();
        </script>
        </body>
        </html>
        """
    }

    private static func languageKeywords(_ language: SupportedLanguage) -> [String] {
        switch language {
        case .swift:
            return ["import","func","var","let","if","else","guard","return","while","for","in","switch","case","default","break","continue","class","struct","enum","protocol","extension","init","self","nil","true","false","throw","try","catch","do","async","await","some","any","private","public","static","override"]
        case .python:
            return ["def","class","if","elif","else","return","while","for","in","import","from","as","not","and","or","is","None","True","False","try","except","finally","raise","with","lambda","pass"]
        case .rust:
            return ["fn","let","mut","if","else","match","return","while","for","in","loop","break","continue","struct","enum","impl","pub","use","mod","self","true","false","async","await"]
        case .go:
            return ["package","import","func","var","const","if","else","return","for","range","switch","case","default","break","struct","interface","type","map","go","defer","true","false","nil"]
        case .kotlin:
            return ["fun","val","var","if","else","when","return","while","for","in","class","object","interface","data","null","true","false","this","super","import","package"]
        case .glsl, .metal, .hlsl:
            return ["void","uniform","varying","in","out","return","if","else","for","while","struct","const","fragment","vertex","kernel","true","false"]
        case .cpp:
            return ["if","else","return","while","for","do","switch","case","class","struct","enum","namespace","using","public","private","virtual","template","const","static","new","delete","this","true","false","nullptr","auto","void","include","define"]
        case .typescript:
            return ["import","export","from","function","var","let","const","if","else","return","while","for","class","new","this","null","undefined","true","false","async","await","interface","type","enum"]
        case .javascript, .react:
            return ["import","export","from","function","var","let","const","if","else","return","while","for","class","new","this","null","undefined","true","false","async","await","typeof"]
        case .css:
            return ["display","position","margin","padding","color","background","border","font","width","height","flex","grid"]
        case .html:
            return ["html","head","body","div","span","script","style","link","meta","title","class","id","src","href"]
        case .json, .unknown:
            return []
        }
    }

    private static func jsonStringLiteral(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private static func jsonArrayLiteral(_ items: [String]) -> String {
        let inner = items.map { "\"\($0)\"" }.joined(separator: ",")
        return "[\(inner)]"
    }
}

// MARK: - WebPreviewView

#if canImport(AppKit)
struct WebPreviewView: NSViewRepresentable {
    let code: String
    let language: SupportedLanguage
    var isDark: Bool = true
    var compact: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.currentCode = ""
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if code or language actually changed
        let key = "\(language.rawValue)|\(isDark)|\(compact)|\(code)"
        guard key != context.coordinator.currentCode else { return }
        context.coordinator.currentCode = key

        let htmlContent = PreviewHTMLBuilder.html(
            for: code,
            language: language,
            isDark: isDark,
            compact: compact
        )
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var currentCode: String = ""
    }
}
#else
struct WebPreviewView: View {
    let code: String
    let language: SupportedLanguage
    var isDark: Bool = true
    var compact: Bool = false

    var body: some View {
        Text("Preview not supported on this platform")
    }
}
#endif

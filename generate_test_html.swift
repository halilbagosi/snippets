import Foundation

enum SupportedLanguage: String {
    case swift = "Swift"
    case react = "React"
    var accentHex: String { return "#FFFFFF" }
}

enum PreviewHTMLBuilder {
    static func html(
        for code: String,
        language: SupportedLanguage,
        isDark: Bool,
        compact: Bool
    ) -> String {
        switch language {
        case .swift: return codeCardPreview(code, language: language, isDark: isDark, compact: compact)
        case .react: return reactPreview(code, isDark: isDark)
        default: return ""
        }
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

    private static func codeCardPreview(
        _ code: String,
        language: SupportedLanguage,
        isDark: Bool,
        compact: Bool
    ) -> String {
        let bg = isDark ? "#0e1014" : "#f5f6f8"
        let fg = isDark ? "#e6edf3" : "#242a30"
        let fontSize = compact ? "10px" : "12.5px"
        let lineHeight = compact ? "1.5" : "1.65"
        let padding = compact ? "8px 6px" : "14px 12px"

        let escapedCode = code
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        </head>
        <body>
        <script>
        (function(){
            const raw = \(jsonStringLiteral(escapedCode));
            const keywords = new Set(\(jsonArrayLiteral(["func", "var"])));
            const lines = raw.split('\\n');
            let html = '';
            for (let i = 0; i < lines.length; i++) {
                const num = i + 1;
                html += '<div class="line">' + num + ' ' + lines[i] + '</div>';
            }
            document.body.insertAdjacentHTML('beforeend', html);
        })();
        </script>
        </body>
        </html>
        """
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

let swiftCode = """
func hello() {
    print("world")
}
"""

let reactCode = """
export default function App() {
    return <h1>Hello React</h1>;
}
"""

let swiftHTML = PreviewHTMLBuilder.html(for: swiftCode, language: .swift, isDark: true, compact: false)
let reactHTML = PreviewHTMLBuilder.html(for: reactCode, language: .react, isDark: true, compact: false)

try swiftHTML.write(toFile: "swift_test.html", atomically: true, encoding: .utf8)
try reactHTML.write(toFile: "react_test.html", atomically: true, encoding: .utf8)

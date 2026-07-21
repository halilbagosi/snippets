import CryptoKit
import Foundation

/// Turns a SwiftUI snippet into a compilable dylib source with an exported
/// factory returning an `NSHostingView` for the snippet's root view.
/// Pure string logic — the compile/load steps live in `SwiftPreviewBuilder`.
enum SwiftPreviewHarness {
    struct Harness: Equatable {
        let source: String
        let symbolName: String
        /// Full-source hash, also used as the dylib cache key.
        let hash: String
    }

    enum HarnessError: LocalizedError {
        case noRootView
        case genericRootOnly(String)

        var errorDescription: String? {
            switch self {
            case .noRootView:
                return "No SwiftUI View found. Define a struct conforming to View (named Preview or ContentView to pick the root explicitly)."
            case .genericRootOnly(let name):
                return "“\(name)” is generic, so the preview can't instantiate it directly. Add a non-generic wrapper: struct Preview: View { var body: some View { \(name)<…>(…) } }"
            }
        }
    }

    static func make(code: String) throws -> Harness {
        try make(entry: code, helpers: [])
    }

    /// Helpers (resolved dependencies) join the entry in one compile unit,
    /// helpers first. `#Preview` blocks are stripped everywhere (the macro
    /// needs Xcode's PreviewsMacros plugin, unavailable to the standalone
    /// compile); the entry's first block becomes a synthesized root view —
    /// it is the author's explicit preview, complete with init arguments a
    /// blind `Root()` call can't supply. Otherwise the root view is picked
    /// from the entry code, falling back to the helpers when the entry
    /// declares no view of its own.
    static func make(entry: String, helpers: [String]) throws -> Harness {
        let strippedEntry = strippingPreviewBlocks(from: entry)
        let strippedHelpers = helpers.map { strippingPreviewBlocks(from: $0) }

        let root: String
        var synthesizedRoot = ""
        if let previewBody = strippedEntry.firstPreviewBody {
            root = "__SnippetPreviewRoot"
            synthesizedRoot = """


            struct __SnippetPreviewRoot: View {
                var body: some View {
            \(previewBody)
                }
            }
            """
        } else if let found = rootViewName(in: strippedEntry.stripped)
            ?? strippedHelpers.lazy.compactMap({ rootViewName(in: $0.stripped) }).first {
            root = found
        } else {
            if let generic = ([strippedEntry] + strippedHelpers).lazy
                .compactMap({ genericViewName(in: $0.stripped) }).first {
                throw HarnessError.genericRootOnly(generic)
            }
            throw HarnessError.noRootView
        }
        let combined = (strippedHelpers + [strippedEntry]).map(\.stripped)
            .joined(separator: "\n\n") + synthesizedRoot
        let hash = SHA256.hash(data: Data(combined.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let shortHash = String(hash.prefix(8))
        let symbolName = "snippet_make_view_\(shortHash)"

        var imports: [String] = []
        for module in ["SwiftUI", "AppKit"] where !combined.contains("import \(module)") {
            imports.append("import \(module)")
        }
        let source = """
        \(imports.joined(separator: "\n"))
        \(combined)

        @_cdecl("\(symbolName)")
        public func \(symbolName)() -> UnsafeMutableRawPointer {
            Unmanaged.passRetained(NSHostingView(rootView: \(root)())).toOpaque()
        }
        """
        return Harness(source: source, symbolName: symbolName, hash: hash)
    }

    /// Root-view priority: `Preview`, then `ContentView`, then the first
    /// view no other part of the code instantiates (the composed root, not a
    /// subcomponent that likely needs init arguments), then the first view.
    /// `extension X: View` conformances count; generic views are never picked
    /// (the harness can't infer their type arguments — `make` surfaces a
    /// dedicated error when nothing else qualifies).
    static func rootViewName(in code: String) -> String? {
        var names = allCaptures(#"struct\s+(\w+)\s*:\s*[^({]*\bView\b"#, in: code)
        for name in allCaptures(#"extension\s+(\w+)\s*:\s*[^({]*\bView\b"#, in: code)
        where !names.contains(name) {
            names.append(name)
        }
        if names.contains("Preview") { return "Preview" }
        if names.contains("ContentView") { return "ContentView" }
        let unreferenced = names.first { name in
            code.range(of: #"\b\#(name)\s*\("#, options: .regularExpression) == nil
        }
        return unreferenced ?? names.first
    }

    /// Removes every `#Preview` block (optional argument list, balanced
    /// trailing closure) and returns the first block's closure body — the
    /// canonical root for the harness. Balanced-brace scanning, not regex:
    /// preview bodies nest arbitrary closures.
    static func strippingPreviewBlocks(
        from code: String
    ) -> (stripped: String, firstPreviewBody: String?) {
        var stripped = ""
        var firstBody: String?
        var cursor = code.startIndex

        while let start = code.range(of: #"#Preview\b"#, options: .regularExpression, range: cursor..<code.endIndex) {
            var index = start.upperBound
            func skipWhitespace() {
                while index < code.endIndex, code[index].isWhitespace { index = code.index(after: index) }
            }
            skipWhitespace()
            if index < code.endIndex, code[index] == "(",
               let closeParen = balancedEnd(in: code, from: index, open: "(", close: ")") {
                index = closeParen
                skipWhitespace()
            }
            guard index < code.endIndex, code[index] == "{",
                  let closeBrace = balancedEnd(in: code, from: index, open: "{", close: "}") else {
                // Malformed block: keep the text as-is and move past the token.
                stripped += code[cursor..<start.upperBound]
                cursor = start.upperBound
                continue
            }
            if firstBody == nil {
                let bodyStart = code.index(after: index)
                let bodyEnd = code.index(before: closeBrace)
                firstBody = String(code[bodyStart..<bodyEnd])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            stripped += code[cursor..<start.lowerBound]
            cursor = closeBrace
        }
        stripped += code[cursor...]
        return (stripped, firstBody)
    }

    /// Index just past the delimiter that balances the opener at `from`.
    /// Skips string literals so braces inside them don't miscount.
    private static func balancedEnd(
        in code: String, from: String.Index, open: Character, close: Character
    ) -> String.Index? {
        var depth = 0
        var index = from
        var inString = false
        while index < code.endIndex {
            let char = code[index]
            if inString {
                if char == "\\", code.index(after: index) < code.endIndex {
                    index = code.index(after: index)
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == open {
                depth += 1
            } else if char == close {
                depth -= 1
                if depth == 0 { return code.index(after: index) }
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// A generic View declaration — findable but not instantiable, used only
    /// for the `genericRootOnly` diagnostic.
    private static func genericViewName(in code: String) -> String? {
        allCaptures(#"struct\s+(\w+)<[^>\n]*>\s*:\s*[^({]*\bView\b"#, in: code).first
    }

    private static func allCaptures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[r])
        }
    }
}

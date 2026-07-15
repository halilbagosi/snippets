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

        var errorDescription: String? {
            "No SwiftUI View found. Define a struct conforming to View (named Preview or ContentView to pick the root explicitly)."
        }
    }

    static func make(code: String) throws -> Harness {
        try make(entry: code, helpers: [])
    }

    /// Helpers (resolved dependencies) join the entry in one compile unit,
    /// helpers first. The root view is picked from the entry code only.
    static func make(entry: String, helpers: [String]) throws -> Harness {
        guard let root = rootViewName(in: entry) else {
            throw HarnessError.noRootView
        }
        let combined = (helpers + [entry]).joined(separator: "\n\n")
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
    /// struct conforming to View.
    static func rootViewName(in code: String) -> String? {
        let names = allCaptures(#"struct\s+(\w+)\s*:\s*[^({]*\bView\b"#, in: code)
        if names.contains("Preview") { return "Preview" }
        if names.contains("ContentView") { return "ContentView" }
        return names.first
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

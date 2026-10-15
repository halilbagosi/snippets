// Only feeds SwiftPreviewBuilder; see the note there on APP_STORE.
#if !APP_STORE
import CryptoKit
import Foundation

/// Turns a Swift snippet into a compilable source file. Snippets with
/// something to show — a View, a `#Preview` block, a style or modifier —
/// become a dylib exporting a factory that returns an `NSHostingView`;
/// anything else becomes a small console program whose output is shown.
/// Pure string logic — the compile/load/run steps live in
/// `SwiftPreviewBuilder`.
enum SwiftPreviewHarness {
    enum Mode: Equatable {
        /// A dylib with an exported `symbolName` factory, loaded in-process.
        case view
        /// An executable run as a child process; `parseAsLibrary` when the
        /// code has its own `@main` entry point instead of top-level code.
        case console(parseAsLibrary: Bool)
    }

    struct Harness: Equatable {
        let source: String
        let symbolName: String
        /// Full-source hash, also used as the artifact cache key.
        let hash: String
        let mode: Mode
        /// The type the preview instantiates on its own, when it is one of the
        /// snippet's types rather than a `#Preview` body — named in the hint
        /// when that type turns out to need init arguments.
        let rootName: String?
    }

    enum HarnessError: LocalizedError {
        case genericRootOnly(String)

        var errorDescription: String? {
            switch self {
            case .genericRootOnly(let name):
                return "“\(name)” is generic, so the preview can't instantiate it directly. Add a #Preview that picks its type arguments: #Preview { \(name)<…>(…) }"
            }
        }
    }

    /// The file names diagnostics are reported against (`snippet:3:5:
    /// error: …`), via `#sourceLocation`, so line numbers match the editor
    /// rather than the generated file.
    static let entryFileName = "snippet"
    static let harnessFileName = "preview harness"
    static func helperFileName(_ index: Int) -> String { "connected snippet \(index + 1)" }

    static func make(code: String) throws -> Harness {
        try make(entry: code, helpers: [])
    }

    /// Helpers (resolved dependencies) join the entry in one compile unit,
    /// helpers first. `#Preview` blocks are stripped everywhere (the macro
    /// needs Xcode's PreviewsMacros plugin, unavailable to the standalone
    /// compile); the entry's first block becomes a synthesized root view —
    /// it is the author's explicit preview, complete with init arguments a
    /// blind `Root()` call can't supply. Otherwise the root is picked from the
    /// entry code, falling back to the helpers when the entry declares
    /// nothing previewable of its own. With no root anywhere the snippet runs
    /// as a console program.
    static func make(entry: String, helpers: [String]) throws -> Harness {
        let strippedEntry = strippingPreviewBlocks(from: entry)
        let strippedHelpers = helpers.map { strippingPreviewBlocks(from: $0).stripped }
        let maskedEntry = String(codeMask(strippedEntry.stripped))
        let maskedHelpers = strippedHelpers.map { String(codeMask($0)) }

        var segments: [(file: String, code: String)] = strippedHelpers.enumerated()
            .map { (helperFileName($0.offset), $0.element) }
        segments.append((entryFileName, strippedEntry.stripped))
        let masked = (maskedHelpers + [maskedEntry]).joined(separator: "\n")

        let root: Root?
        if let previewBody = strippedEntry.firstPreviewBody {
            root = .previewBody(previewBody)
        } else {
            root = self.root(in: maskedEntry)
                ?? maskedHelpers.lazy.compactMap { self.root(in: $0) }.first
        }

        guard let root else {
            if let generic = ([maskedEntry] + maskedHelpers).lazy
                .compactMap({ genericViewName(in: $0) }).first {
                throw HarnessError.genericRootOnly(generic)
            }
            let parseAsLibrary = masked.range(of: #"@main\b"#, options: .regularExpression) != nil
            return assemble(
                segments: segments, masked: masked, imports: ["Foundation"],
                trailer: "", symbolName: "", mode: .console(parseAsLibrary: parseAsLibrary),
                rootName: nil
            )
        }

        // The symbol is named after the snippet source alone, so it is stable
        // for a given snippet and distinct between snippets loaded together.
        let sourceHash = sha256(segments.map(\.code).joined(separator: "\n\u{0}"))
        let symbolName = "snippet_make_view_\(sourceHash.prefix(8))"
        let rootExpression: String
        var synthesized = ""
        switch root {
        case .view(let name):
            rootExpression = "\(name)()"
        case .previewBody(let body):
            rootExpression = "__SnippetPreviewRoot()"
            synthesized = synthesizedRoot(body: body)
        case .style(let name, let kind):
            rootExpression = "__SnippetPreviewRoot()"
            synthesized = synthesizedRoot(body: kind.demo(name))
        }
        let trailer = """
        \(synthesized)
        @_cdecl("\(symbolName)")
        public func \(symbolName)() -> UnsafeMutableRawPointer {
            Unmanaged.passRetained(NSHostingView(rootView: \(rootExpression))).toOpaque()
        }
        """
        return assemble(
            segments: segments, masked: masked, imports: ["SwiftUI", "AppKit"],
            trailer: trailer, symbolName: symbolName, mode: .view, rootName: root.typeName
        )
    }

    private static func assemble(
        segments: [(file: String, code: String)], masked: String, imports: [String],
        trailer: String, symbolName: String, mode: Mode, rootName: String?
    ) -> Harness {
        var source = imports
            .filter { masked.range(of: #"\bimport\s+\#($0)\b"#, options: .regularExpression) == nil }
            .map { "import \($0)\n" }
            .joined()
        for segment in segments {
            source += "#sourceLocation(file: \"\(segment.file)\", line: 1)\n"
            source += segment.code
            if !segment.code.hasSuffix("\n") { source += "\n" }
        }
        source += "#sourceLocation(file: \"\(harnessFileName)\", line: 1)\n"
        source += trailer
        return Harness(
            source: source, symbolName: symbolName, hash: sha256(source), mode: mode,
            rootName: rootName
        )
    }

    private static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Root selection

    private enum Root {
        case view(String)
        case previewBody(String)
        case style(String, StyleKind)

        var typeName: String? {
            switch self {
            case .view(let name), .style(let name, _): return name
            case .previewBody: return nil
            }
        }
    }

    /// Protocols that are not views themselves but have an obvious way to be
    /// shown: applied to a stock control.
    private enum StyleKind: String, CaseIterable {
        case buttonStyle = "ButtonStyle"
        case primitiveButtonStyle = "PrimitiveButtonStyle"
        case toggleStyle = "ToggleStyle"
        case viewModifier = "ViewModifier"

        func demo(_ name: String) -> String {
            switch self {
            case .buttonStyle, .primitiveButtonStyle:
                return """
                Button("Button") {}
                    .buttonStyle(\(name)())
                    .padding()
                """
            case .toggleStyle:
                return """
                @Previewable @State var isOn = true
                Toggle("Toggle", isOn: $isOn)
                    .toggleStyle(\(name)())
                    .padding()
                """
            case .viewModifier:
                return """
                Text("Preview")
                    .modifier(\(name)())
                    .padding()
                """
            }
        }
    }

    /// Protocols whose conformers are Views (`NSViewRepresentable` and
    /// `Shape` refine `View`; the plain `\bView\b` match misses them).
    private static let viewProtocols = "View|NSViewRepresentable|NSViewControllerRepresentable|Shape|InsettableShape"

    private static func root(in maskedCode: String) -> Root? {
        if let view = rootViewName(in: maskedCode) { return .view(view) }
        for kind in StyleKind.allCases {
            if let name = conformers(of: kind.rawValue, in: maskedCode).first {
                return .style(name, kind)
            }
        }
        return nil
    }

    /// Root-view priority: `Preview`, then `ContentView`, then the first
    /// view no other part of the code instantiates (the composed root, not a
    /// subcomponent that likely needs init arguments), then the first view.
    /// `extension X: View` conformances count; generic views are never picked
    /// (the harness can't infer their type arguments — `make` surfaces a
    /// dedicated error when nothing else qualifies). Comments and string
    /// literals are ignored.
    static func rootViewName(in code: String) -> String? {
        let masked = String(codeMask(code))
        let names = conformers(of: viewProtocols, in: masked)
        if names.contains("Preview") { return "Preview" }
        if names.contains("ContentView") { return "ContentView" }
        let unreferenced = names.first { name in
            masked.range(of: #"\b\#(name)\s*\("#, options: .regularExpression) == nil
        }
        return unreferenced ?? names.first
    }

    /// Non-generic types declared (or extended) as conforming to one of
    /// `protocols`, in declaration order.
    private static func conformers(of protocols: String, in maskedCode: String) -> [String] {
        var names = allCaptures(#"(?:struct|final\s+class|class)\s+(\w+)\s*:\s*[^({]*\b(?:\#(protocols))\b"#, in: maskedCode)
        for name in allCaptures(#"extension\s+(\w+)\s*:\s*[^({]*\b(?:\#(protocols))\b"#, in: maskedCode)
        where !names.contains(name) {
            names.append(name)
        }
        return names
    }

    /// A generic View declaration — findable but not instantiable, used only
    /// for the `genericRootOnly` diagnostic.
    private static func genericViewName(in maskedCode: String) -> String? {
        allCaptures(#"struct\s+(\w+)<[^>\n]*>\s*:\s*[^({]*\b(?:\#(viewProtocols))\b"#, in: maskedCode).first
    }

    // MARK: #Preview blocks

    /// A root view whose body is a `#Preview` closure. `@Previewable`
    /// declarations become stored properties: left in `body` they would be
    /// locals re-created on every evaluation, so a `@State` there could never
    /// change.
    private static func synthesizedRoot(body: String) -> String {
        var properties: [String] = []
        var statements: [String] = []
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@Previewable") {
                properties.append(
                    "    " + trimmed.dropFirst("@Previewable".count)
                        .trimmingCharacters(in: .whitespaces)
                )
            } else {
                statements.append(line)
            }
        }
        return """
        struct __SnippetPreviewRoot: View {
        \(properties.joined(separator: "\n"))
            var body: some View {
        \(statements.joined(separator: "\n"))
            }
        }

        """
    }

    /// Removes every `#Preview` block (optional argument list, balanced
    /// trailing closure) and returns the first block's closure body — the
    /// canonical root for the harness. Balanced-brace scanning over the
    /// comment- and string-masked code: preview bodies nest arbitrary
    /// closures, and `#Preview` or a brace inside a string or comment is not
    /// code. A removed block leaves its newlines behind so the lines after it
    /// keep their numbers in diagnostics.
    static func strippingPreviewBlocks(
        from code: String
    ) -> (stripped: String, firstPreviewBody: String?) {
        let chars = Array(code)
        let mask = codeMask(code)
        let token = Array("#Preview")
        var stripped = ""
        var firstBody: String?
        var cursor = 0
        var index = 0

        func isIdentifier(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        func skipWhitespace(_ i: inout Int) {
            while i < mask.count, mask[i].isWhitespace { i += 1 }
        }

        while index + token.count <= mask.count {
            guard mask[index] == "#", Array(mask[index..<index + token.count]) == token,
                  index + token.count == mask.count || !isIdentifier(mask[index + token.count])
            else {
                index += 1
                continue
            }
            var i = index + token.count
            skipWhitespace(&i)
            if i < mask.count, mask[i] == "(", let close = balancedEnd(in: mask, from: i, open: "(", close: ")") {
                i = close
                skipWhitespace(&i)
            }
            guard i < mask.count, mask[i] == "{",
                  let closeBrace = balancedEnd(in: mask, from: i, open: "{", close: "}") else {
                // Malformed block: keep the text as-is and move past the token.
                index += token.count
                continue
            }
            if firstBody == nil {
                firstBody = String(chars[(i + 1)..<(closeBrace - 1)])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            stripped += String(chars[cursor..<index])
            stripped += String(repeating: "\n", count: chars[index..<closeBrace].filter(\.isNewline).count)
            cursor = closeBrace
            index = closeBrace
        }
        stripped += String(chars[cursor...])
        return (stripped, firstBody)
    }

    /// Index just past the delimiter that balances the opener at `from`, in
    /// masked code (so strings and comments can't miscount).
    private static func balancedEnd(
        in mask: [Character], from: Int, open: Character, close: Character
    ) -> Int? {
        var depth = 0
        for i in from..<mask.count {
            if mask[i] == open {
                depth += 1
            } else if mask[i] == close {
                depth -= 1
                if depth == 0 { return i + 1 }
            }
        }
        return nil
    }

    // MARK: Lexing

    /// `code` with every comment and string literal (delimiters, contents and
    /// interpolations) replaced by spaces, newlines kept — one output
    /// Character per input Character, so offsets carry over. Pattern
    /// matching runs on this, so a view named in a comment, or `#Preview`
    /// quoted in a `Text`, is not mistaken for code.
    static func codeMask(_ code: String) -> [Character] {
        enum Context {
            case code(interpolationDepth: Int?)
            case string(hashes: Int, multiline: Bool)
            case blockComment
        }
        let chars = Array(code)
        var out = chars
        var stack: [Context] = [.code(interpolationDepth: nil)]
        // Anything above the top-level code context is a string, a comment,
        // or code interpolated into a string.
        var masking: Bool { stack.count > 1 }
        var i = 0

        func at(_ offset: Int, _ text: String) -> Bool {
            let t = Array(text)
            guard offset + t.count <= chars.count else { return false }
            return Array(chars[offset..<offset + t.count]) == t
        }
        func hashes(from offset: Int) -> Int {
            var n = 0
            while offset + n < chars.count, chars[offset + n] == "#" { n += 1 }
            return n
        }
        func blank(_ range: Range<Int>) {
            for j in range where j < out.count && !out[j].isNewline { out[j] = " " }
        }

        while i < chars.count {
            switch stack[stack.count - 1] {
            case .code(let depth):
                if at(i, "//") {
                    var end = i
                    while end < chars.count, !chars[end].isNewline { end += 1 }
                    blank(i..<end)
                    i = end
                } else if at(i, "/*") {
                    blank(i..<i + 2)
                    stack.append(.blockComment)
                    i += 2
                } else if chars[i] == "#" || chars[i] == "\"" {
                    let n = hashes(from: i)
                    guard i + n < chars.count, chars[i + n] == "\"" else {
                        if masking { blank(i..<i + 1) }
                        i += 1
                        continue
                    }
                    let multiline = at(i + n, "\"\"\"")
                    let length = n + (multiline ? 3 : 1)
                    blank(i..<i + length)
                    stack.append(.string(hashes: n, multiline: multiline))
                    i += length
                } else {
                    if let depth {
                        if chars[i] == "(" {
                            stack[stack.count - 1] = .code(interpolationDepth: depth + 1)
                        } else if chars[i] == ")" {
                            if depth == 0 {
                                stack.removeLast() // back into the string
                            } else {
                                stack[stack.count - 1] = .code(interpolationDepth: depth - 1)
                            }
                        }
                    }
                    if masking { blank(i..<i + 1) }
                    i += 1
                }
            case .string(let n, let multiline):
                let pounds = String(repeating: "#", count: n)
                if at(i, "\\" + pounds + "(") {
                    let length = n + 2
                    blank(i..<i + length)
                    stack.append(.code(interpolationDepth: 0))
                    i += length
                } else if at(i, "\\" + pounds) {
                    let length = n + 2 // the backslash, pounds, and escaped char
                    blank(i..<min(i + length, chars.count))
                    i += length
                } else if at(i, (multiline ? "\"\"\"" : "\"") + pounds) {
                    let length = (multiline ? 3 : 1) + n
                    blank(i..<i + length)
                    stack.removeLast()
                    i += length
                } else if !multiline, chars[i].isNewline {
                    stack.removeLast() // unterminated literal: stop at the line end
                    i += 1
                } else {
                    blank(i..<i + 1)
                    i += 1
                }
            case .blockComment:
                if at(i, "*/") {
                    blank(i..<i + 2)
                    stack.removeLast()
                    i += 2
                } else if at(i, "/*") {
                    blank(i..<i + 2)
                    stack.append(.blockComment)
                    i += 2
                } else {
                    blank(i..<i + 1)
                    i += 1
                }
            }
        }
        return out
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

    // MARK: Diagnostics

    /// Compiler output trimmed to what fits the panel, with a plain-language
    /// hint first for the failures a snippet author hits most.
    static func describeCompileFailure(_ diagnostics: String, harness: Harness) -> String {
        var hints: [String] = []
        let harnessError = diagnostics.contains("\(harnessFileName):")
        if harnessError, diagnostics.contains("missing argument"), let root = harness.rootName {
            hints.append("“\(root)” needs arguments, so the preview can't create one on its own. Add a #Preview block that builds it, e.g. #Preview { \(root)(…) }")
        }
        if let missing = firstCapture(#"error: cannot find (?:type )?'(\w+)' in scope"#, in: diagnostics) {
            hints.append("If “\(missing)” is defined in another snippet, add that snippet under connections in the editor so the two compile together.")
        }
        if harness.mode == .view, diagnostics.contains("expressions are not allowed at the top level") {
            hints.append("Snippets that declare a View compile as a library, so top-level statements can't run. Move them into the view, or into a #Preview block.")
        }

        let lines = diagnostics.split(separator: "\n", omittingEmptySubsequences: false)
        let limit = 150
        var body = lines.prefix(limit).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lines.count > limit {
            body += "\n… \(lines.count - limit) more lines"
        }
        return (hints + [body]).joined(separator: "\n\n")
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        allCaptures(pattern, in: text).first
    }
}
#endif

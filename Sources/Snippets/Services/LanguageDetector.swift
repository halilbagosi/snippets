import Foundation

enum SupportedLanguage: String, CaseIterable, Identifiable, Hashable {
    case html = "HTML"
    case swift = "Swift"
    case rust = "Rust"
    case javascript = "JavaScript"
    case json = "JSON"
    case go = "Go"
    case react = "React"
    case hlsl = "HLSL"
    case glsl = "GLSL"
    case python = "Python"
    case typescript = "TypeScript"
    case cpp = "C/C++"
    case kotlin = "Kotlin"
    case metal = "Metal"
    case css = "CSS"
    case unknown = "Unknown"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .glsl, .metal, .hlsl: return "cube.transparent"
        case .swift: return "swift"
        case .kotlin: return "k.circle"
        case .rust: return "shippingbox"
        case .go: return "g.circle"
        case .python: return "p.circle"
        case .typescript, .javascript: return "curlybraces"
        case .react: return "atom"
        case .css: return "paintpalette"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .json: return "doc.text"
        case .cpp: return "c.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var accentHex: String {
        switch self {
        case .glsl: return "#1E90FF"
        case .metal: return "#A855F7"
        case .hlsl: return "#0EA5E9"
        case .swift: return "#F97316"
        case .kotlin: return "#7F5AF0"
        case .rust: return "#B45309"
        case .go: return "#06B6D4"
        case .python: return "#3B82F6"
        case .typescript: return "#2563EB"
        case .javascript: return "#EAB308"
        case .react: return "#61DAFB"
        case .css: return "#EC4899"
        case .html: return "#EF4444"
        case .json: return "#10B981"
        case .cpp: return "#6366F1"
        case .unknown: return "#9CA3AF"
        }
    }
    // Note: `accentHexLight` removed — light mode now uses `accentHex` values.

    var accentHexSelectedFill: String {
        switch self {
        case .glsl: return "#0B63CE"
        case .metal: return "#9333EA"
        case .hlsl: return "#0369A1"
        case .swift: return "#B45309"
        case .kotlin: return "#7F5AF0"
        case .rust: return "#B45309"
        case .go: return "#0E7490"
        case .python: return "#2563EB"
        case .typescript: return "#2563EB"
        case .javascript: return "#7A5D00"
        case .react: return "#0072A3"
        case .css: return "#BE185D"
        case .html: return "#DC2626"
        case .json: return "#047857"
        case .cpp: return "#4F46E5"
        case .unknown: return "#6B7280"
        }
    }
}

/// Guesses a snippet's language from its source alone.
///
/// Detection is weighted evidence, not a first-match scan: every language
/// scores its own markers over the same sanitized text and the highest score
/// wins. That matters because real snippets are mixtures — an HTML document
/// carries a `<script>`, a React component carries type annotations, a Metal
/// shader is also valid C++ — and the language that owns the *file* is the one
/// with the most distinctive evidence, not the one whose rule ran first.
enum LanguageDetector {

    /// How much source is examined. Long enough to see past a license header,
    /// a wall of imports, or a leading comment block, short enough to stay
    /// inside a frame: detection reruns on every keystroke in the editor, and
    /// cost is linear in this window (~1 ms per kilobyte scanned).
    private static let scanLimit = 8_192

    /// Quoted strings longer than this many bytes are treated as payload
    /// (prose, an embedded shader, a data blob) and blanked before scoring.
    /// Shorter ones survive, so `from 'react'` and `class="hero"` still count.
    private static let inlineStringLimit = 40

    /// Minimum score to claim a language — one `.decisive` marker, or a few
    /// corroborating weaker ones. Below it, nothing is claimed.
    private static let minimumConfidence = 3.0

    /// Evidence needed for a family override to fire (see `resolve`).
    private static let overrideConfidence = 6.0

    // MARK: - Entry point

    static func detect(code rawCode: String) -> SupportedLanguage {
        detect(code: rawCode, unwrappingFences: true)
    }

    private static func detect(code rawCode: String, unwrappingFences: Bool) -> SupportedLanguage {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .unknown }

        // A pasted markdown block already states its language; believe it.
        if unwrappingFences, let fence = fencedBlock(in: trimmed) {
            if let declared = fence.language { return declared }
            return detect(code: fence.body, unwrappingFences: false)
        }

        if isJSON(trimmed) { return .json }

        let clean = sanitized(String(trimmed.prefix(scanLimit)))
        return resolve(scores(for: clean))
    }

    // MARK: - Scoring

    /// One regex plus how much a match is worth, and how many matches keep
    /// counting — the cap stops a repetitive file from letting a single weak
    /// marker outweigh genuinely distinctive evidence.
    struct Marker {
        let regex: NSRegularExpression
        let weight: Double
        let cap: Int
    }

    struct Profile {
        let language: SupportedLanguage
        let markers: [Marker]
        let penalties: [Marker]

        init(language: SupportedLanguage, markers: [Marker?], penalties: [Marker?] = []) {
            self.language = language
            self.markers = markers.compactMap { $0 }
            self.penalties = penalties.compactMap { $0 }
        }
    }

    static func marker(_ pattern: String, _ weight: Double, cap: Int = 1) -> Marker? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            assertionFailure("LanguageDetector: invalid marker pattern \(pattern)")
            return nil
        }
        return Marker(regex: regex, weight: weight, cap: cap)
    }

    private static func scores(for text: String) -> [(language: SupportedLanguage, score: Double)] {
        // Every marker re-bridges the subject string to NSString. Handing the
        // regexes a String that is *already* backed by NSString storage makes
        // each of those bridges a retain instead of a full UTF-16 copy — with
        // this many markers that is the difference between a few milliseconds
        // and a dropped frame, since detection reruns on every keystroke.
        let storage = text as NSString
        let subject = storage as String
        let range = NSRange(location: 0, length: storage.length)

        return profiles.map { profile in
            let positive = profile.markers.reduce(0.0) { $0 + value(of: $1, in: subject, range: range) }
            let negative = profile.penalties.reduce(0.0) { $0 + value(of: $1, in: subject, range: range) }
            return (profile.language, positive - negative)
        }
    }

    private static func value(of marker: Marker, in text: String, range: NSRange) -> Double {
        var hits = 0
        marker.regex.enumerateMatches(in: text, options: [], range: range) { _, _, stop in
            hits += 1
            if hits >= marker.cap { stop.pointee = true }
        }
        return Double(hits) * marker.weight
    }

    // MARK: - Resolution

    private static func resolve(_ scores: [(language: SupportedLanguage, score: Double)]) -> SupportedLanguage {
        func score(_ language: SupportedLanguage) -> Double {
            scores.first { $0.language == language }?.score ?? 0
        }

        var winner = SupportedLanguage.unknown
        var best = -Double.infinity
        for entry in scores where entry.score >= minimumConfidence {
            let ties = entry.score == best && priority(entry.language) < priority(winner)
            if entry.score > best || ties {
                winner = entry.language
                best = entry.score
            }
        }
        guard winner != .unknown else { return .unknown }

        // Family overrides. Within a family the members share almost all of
        // their syntax, so the specialised dialect wins whenever it has real
        // evidence of its own — even if the shared base scored higher on
        // sheer volume of common markers.
        if [.javascript, .typescript].contains(winner), score(.react) >= overrideConfidence {
            return .react
        }
        // Markup gets a higher bar: a hand-written page that merely mentions a
        // hook in a script tag is still a page, so React has to out-score the
        // markup outright rather than just clear the override threshold.
        if winner == .html, score(.react) >= max(overrideConfidence, score(.html)) {
            return .react
        }
        if winner == .javascript, score(.typescript) >= overrideConfidence {
            return .typescript
        }
        if winner == .cpp {
            // Metal and HLSL are C++ dialects; GLSL borrows its declarations.
            let shaders = [SupportedLanguage.metal, .hlsl, .glsl].map { ($0, score($0)) }
            if let strongest = shaders.max(by: { $0.1 < $1.1 }), strongest.1 >= overrideConfidence {
                return strongest.0
            }
        }
        return winner
    }

    /// Tie-break order, most specific first: when two languages score exactly
    /// the same, the narrower one is the better guess.
    private static func priority(_ language: SupportedLanguage) -> Int {
        switch language {
        case .json: return 0
        case .metal: return 1
        case .hlsl: return 2
        case .glsl: return 3
        case .react: return 4
        case .swift: return 5
        case .kotlin: return 6
        case .rust: return 7
        case .go: return 8
        case .python: return 9
        case .typescript: return 10
        case .cpp: return 11
        case .css: return 12
        case .html: return 13
        case .javascript: return 14
        case .unknown: return .max
        }
    }

    // MARK: - JSON

    /// JSON is decided by parsing, not by markers — the shape of the data says
    /// nothing about the language, only its validity does. A second attempt
    /// covers JSONC/JSON5-style files with comments or trailing commas.
    private static func isJSON(_ trimmed: String) -> Bool {
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        if (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil { return true }

        guard trimmed.utf8.count <= 262_144 else { return false }
        let relaxed = sanitized(trimmed).replacingOccurrences(
            of: #",(\s*[}\]])"#, with: "$1", options: .regularExpression
        )
        return (try? JSONSerialization.jsonObject(with: Data(relaxed.utf8))) != nil
    }

    // MARK: - Markdown fences

    /// A snippet pasted as a single ```-fenced block, with the fence's info
    /// string resolved to a language when it names one we support.
    private static func fencedBlock(in trimmed: String) -> (language: SupportedLanguage?, body: String)? {
        let marks: [Character] = ["`", "~"]
        guard let opener = trimmed.first, marks.contains(opener),
              trimmed.hasPrefix(String(repeating: opener, count: 3))
        else { return nil }

        var lines = trimmed.components(separatedBy: .newlines)
        let info = lines
            .removeFirst()
            .drop { $0 == opener }
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .prefix { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "#" }

        if let last = lines.last, last.trimmingCharacters(in: .whitespaces).allSatisfy({ $0 == opener }),
           !last.isEmpty {
            lines.removeLast()
        }
        return (language(forFenceInfo: String(info)), lines.joined(separator: "\n"))
    }

    private static func language(forFenceInfo info: String) -> SupportedLanguage? {
        switch info {
        case "html", "htm", "xml", "svg", "vue": return .html
        case "css", "scss", "sass", "less", "postcss": return .css
        case "js", "javascript", "mjs", "cjs", "node": return .javascript
        case "ts", "typescript", "mts", "cts": return .typescript
        case "jsx", "tsx", "react": return .react
        case "json", "json5", "jsonc": return .json
        case "swift": return .swift
        case "py", "python", "python3": return .python
        case "go", "golang": return .go
        case "rs", "rust": return .rust
        case "kt", "kts", "kotlin": return .kotlin
        case "glsl", "frag", "vert", "fragment", "vertex", "shader": return .glsl
        case "metal", "msl": return .metal
        case "hlsl", "fx", "cg", "shaderlab": return .hlsl
        case "c", "cpp", "c++", "cc", "cxx", "h", "hpp", "objc": return .cpp
        default: return nil
        }
    }

    // MARK: - Sanitizing

    /// Strips the parts of a file that lie about its language: comments (which
    /// often quote *other* languages) and long string bodies (embedded
    /// shaders, HTML blobs, prose). Short strings survive so that import
    /// specifiers like `from 'react'` and attributes like `class="x"` still
    /// count as evidence.
    ///
    /// One pass handles both, because they nest: `//` inside a string is not a
    /// comment, and a quote inside a comment does not open a string.
    ///
    /// Works on UTF-8 bytes rather than characters — every delimiter it looks
    /// for is ASCII, and no byte of a multi-byte scalar can be mistaken for
    /// one, so non-ASCII source passes through untouched at a fraction of the
    /// cost of building grapheme clusters.
    private static func sanitized(_ source: String) -> String {
        let bytes = Array(source.utf8)
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count)
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]

            if byte == .quote || byte == .apostrophe {
                // Triple-quoted block (Swift/Python): drop the body wholesale.
                if index + 2 < bytes.count, bytes[index + 1] == byte, bytes[index + 2] == byte {
                    result.append(contentsOf: [byte, byte])
                    index = endOfTriple(bytes, from: index + 3, quote: byte)
                    continue
                }
                if let string = readString(bytes, from: index, quote: byte) {
                    result.append(contentsOf: string.bytes)
                    index = string.end
                    continue
                }
                // Unterminated: an apostrophe in prose, or a Rust lifetime.
                result.append(byte)
                index += 1
                continue
            }

            if byte == .backtick {
                result.append(contentsOf: [UInt8.backtick, .backtick])
                index = endOfTemplate(bytes, from: index + 1)
                continue
            }

            if byte == .slash, index + 1 < bytes.count {
                if bytes[index + 1] == .slash {
                    while index < bytes.count, bytes[index] != .newline { index += 1 }
                    continue
                }
                if bytes[index + 1] == .star {
                    index += 2
                    while index + 1 < bytes.count,
                          !(bytes[index] == .star && bytes[index + 1] == .slash) {
                        index += 1
                    }
                    index = min(index + 2, bytes.count)
                    result.append(.space)
                    continue
                }
            }

            result.append(byte)
            index += 1
        }
        return String(decoding: result, as: UTF8.self)
    }

    private static func endOfTriple(_ bytes: [UInt8], from start: Int, quote: UInt8) -> Int {
        var index = start
        while index + 2 < bytes.count {
            if bytes[index] == quote, bytes[index + 1] == quote, bytes[index + 2] == quote {
                return index + 3
            }
            index += 1
        }
        return bytes.count
    }

    private static func endOfTemplate(_ bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count {
            if bytes[index] == .backslash { index += 2; continue }
            if bytes[index] == .backtick { return index + 1 }
            index += 1
        }
        return bytes.count
    }

    /// Reads a single-line quoted string. Returns `nil` when it never closes
    /// on its line, which means the quote was not a string delimiter at all.
    private static func readString(
        _ bytes: [UInt8], from start: Int, quote: UInt8
    ) -> (bytes: [UInt8], end: Int)? {
        var index = start + 1
        var body: [UInt8] = []
        while index < bytes.count {
            let byte = bytes[index]
            if byte == .newline { return nil }
            if byte == .backslash {
                body.append(contentsOf: [UInt8.space, .space])
                index += 2
                continue
            }
            if byte == quote {
                let kept = body.count > inlineStringLimit ? [] : body
                return ([quote] + kept + [quote], index + 1)
            }
            body.append(byte)
            index += 1
        }
        return nil
    }
}

private extension UInt8 {
    static let quote: UInt8 = 0x22
    static let apostrophe: UInt8 = 0x27
    static let backtick: UInt8 = 0x60
    static let slash: UInt8 = 0x2F
    static let star: UInt8 = 0x2A
    static let backslash: UInt8 = 0x5C
    static let newline: UInt8 = 0x0A
    static let space: UInt8 = 0x20
}

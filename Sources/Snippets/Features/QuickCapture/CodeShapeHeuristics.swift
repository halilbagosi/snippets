import Foundation

/// Answers "is this code at all?" for arbitrary clipboard text.
///
/// Deliberately separate from `LanguageDetector`, which answers a different
/// question — "which language is this code?" — and was tuned against a corpus
/// of text already known to be code. Feeding it a paragraph of prose that
/// happens to contain a brace can score a language, so this gate runs first
/// and the detector only ever sees what survives.
///
/// Weighted signals rather than a single rule: no one signal is reliable, but
/// real code almost always trips two or three. The thresholds are tuned
/// against `CodeShapeHeuristicsTests`, which is the actual specification.
enum CodeShapeHeuristics {

    /// Below this there is not enough shape to judge, and a snippet that short
    /// is not worth prompting over.
    static let minimumCharacters = 24

    /// Score at or above which text is treated as code.
    private static let threshold = 3

    /// Characters far more common in code than in prose. Notably excludes
    /// `.` `,` `'` `"` `:` `!` `?` — all ordinary punctuation.
    private static let codeSymbols: Set<Character> = [
        "{", "}", "(", ")", "[", "]", ";", "=", "<", ">",
        "/", "\\", "|", "&", "*", "+", "_", "#", "$", "`", "@", "~", "^"
    ]

    private static let keywords: Set<String> = [
        "func", "function", "def", "class", "struct", "enum", "import",
        "return", "const", "let", "var", "if", "else", "for", "while",
        "public", "private", "static", "void", "int", "string", "bool",
        "null", "nil", "true", "false", "async", "await", "export",
        "require", "include", "package", "namespace", "interface", "print",
        "select", "insert", "update", "delete", "from", "where"
    ]

    static func isLikelyCode(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumCharacters else { return false }
        guard !isBareURL(trimmed) else { return false }
        return score(trimmed) >= threshold
    }

    // MARK: - Scoring

    private static func score(_ text: String) -> Int {
        // A fence is an explicit "this is code" marker from whoever wrote it.
        if text.contains("```") { return threshold + 1 }

        var total = 0
        let density = symbolDensity(text)
        let lines = text.components(separatedBy: .newlines)

        if density >= 0.06 {
            total += 2
        } else if density >= 0.03 {
            total += 1
        }

        if lines.count >= 2, lines.contains(where: isIndented) {
            total += 2
        }

        if lines.contains(where: endsLikeAStatement) {
            total += 2
        }

        if hasCommandFlag(text) {
            total += 2
        }

        switch keywordHits(text) {
        case 0: break
        case 1: total += 1
        default: total += 2
        }

        // Sentence-shaped text with almost no code punctuation is prose, and
        // a lone incidental signal should not be enough to override that.
        if density < 0.02, wordCount(text) >= 8 {
            total -= 3
        }

        return total
    }

    // MARK: - Signals

    private static func symbolDensity(_ text: String) -> Double {
        guard !text.isEmpty else { return 0 }
        let hits = text.reduce(into: 0) { count, character in
            if codeSymbols.contains(character) { count += 1 }
        }
        return Double(hits) / Double(text.count)
    }

    private static func isIndented(_ line: String) -> Bool {
        line.hasPrefix("  ") || line.hasPrefix("\t")
    }

    private static func endsLikeAStatement(_ line: String) -> Bool {
        guard let last = line.trimmingCharacters(in: .whitespaces).last else { return false }
        return last == ";" || last == "{" || last == "}"
    }

    /// A `-x` or `--flag` token, which is what carries shell one-liners: they
    /// have few symbols and no language keywords. Hyphenated words like
    /// "well-known" do not match, because the hyphen is not preceded by
    /// whitespace or a line start.
    private static func hasCommandFlag(_ text: String) -> Bool {
        var previousWasBoundary = true
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "-", previousWasBoundary {
                var next = text.index(after: index)
                if next < text.endIndex, text[next] == "-" {
                    next = text.index(after: next)
                }
                if next < text.endIndex, text[next].isLetter { return true }
            }
            previousWasBoundary = character.isWhitespace
            index = text.index(after: index)
        }
        return false
    }

    private static func keywordHits(_ text: String) -> Int {
        let words = text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return Set(words).intersection(keywords).count
    }

    private static func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    private static func isBareURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isNewline) else { return false }
        guard text.components(separatedBy: .whitespaces).count == 1 else { return false }
        return text.hasPrefix("http://") || text.hasPrefix("https://")
    }
}

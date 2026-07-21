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

enum LanguageDetector {
    private struct Rule {
        let language: SupportedLanguage
        let markers: [String]
        let minimumMatches: Int
    }

    private static let rules: [Rule] = [
        Rule(language: .glsl, markers: ["#version", "gl_Position", "gl_FragColor", "uniform ", "varying ", "void main()"], minimumMatches: 1),
        Rule(language: .metal, markers: ["#include <metal_stdlib>", "fragment ", "vertex ", "kernel ", "using namespace metal"], minimumMatches: 1),
        Rule(language: .hlsl, markers: ["SV_Position", "cbuffer ", "Texture2D", ": SV_TARGET"], minimumMatches: 1),
        Rule(language: .swift, markers: ["import SwiftUI", "import Foundation", "@State", "@main", "struct ", "var body: some View", "func ", "guard "], minimumMatches: 2),
        Rule(language: .kotlin, markers: ["fun ", "val ", "data class", "companion object", "package "], minimumMatches: 2),
        Rule(language: .rust, markers: ["fn ", "let mut", "impl ", "use std::", "->", "pub fn"], minimumMatches: 2),
        Rule(language: .go, markers: ["package ", "import \"", "fmt.", "func ", ":= "], minimumMatches: 2),
        Rule(language: .python, markers: ["def ", "import ", "print(", "if __name__", "self.", "lambda "], minimumMatches: 2),
        Rule(language: .typescript, markers: [": string", ": number", "interface ", "export type", "as const"], minimumMatches: 1),
        Rule(language: .react, markers: ["import React", "useState", "useEffect", "JSX.Element", "</>", "ReactDOM", "from 'react'", "from \"react\""], minimumMatches: 2),
        Rule(language: .javascript, markers: ["const ", "function ", "console.log", "() =>", "require(", "module.exports"], minimumMatches: 2),
        Rule(language: .css, markers: ["margin:", "padding:", "font-size:", "display:", "color:", "background:"], minimumMatches: 2),
        Rule(language: .html, markers: ["<!DOCTYPE", "<html", "<div", "<body", "</"], minimumMatches: 1),
        Rule(language: .cpp, markers: ["#include", "std::", "cout <<", "int main(", "namespace "], minimumMatches: 2)
    ]

    static func detect(code rawCode: String) -> SupportedLanguage {
        let scanPrefix = rawCode.prefix(2_048)
        var code = String(scanPrefix).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return .unknown }
        // Embedded shader sources (GLSL in JS template literals, or in Swift
        // multiline strings) would otherwise trip the shader rules and outvote
        // the host language, so blank out those string bodies before scanning.
        code = strippingEmbeddedStringBlocks(from: code)

        if let first = code.first, first == "{" || first == "[" {
            if rawCode.utf8.count > 2_048 {
                return .json
            }
            if (try? JSONSerialization.jsonObject(with: Data(code.utf8))) != nil {
                return .json
            }
        }

        var bestMatch: (language: SupportedLanguage, score: Int) = (.unknown, 0)
        for rule in rules {
            var hits = 0
            let confidentMatchCount = max(rule.minimumMatches, 3)
            for marker in rule.markers where code.contains(marker) {
                hits += 1
                if hits >= confidentMatchCount {
                    return rule.language
                }
            }
            if hits >= rule.minimumMatches && hits > bestMatch.score {
                bestMatch = (rule.language, hits)
            }
        }

        // JSX usage snippets (`<Strands amplitude={1} />`) carry capitalized
        // component tags that no HTML document has, but hit zero react
        // markers — without this they land on .html (closing tags trip "</")
        // or .unknown (self-closing only) and the preview mishandles them.
        // Only a tie-break: any confident language above still wins, so
        // generics like `Array<String>` in typed code are unaffected.
        if bestMatch.language == .html || bestMatch.language == .unknown,
           containsJSXComponentTag(code) {
            return .react
        }

        return bestMatch.language
    }

    /// A PascalCase tag in tag position — start of line or after `(`/`{`/
    /// `,`/whitespace — so `Array<String>` (identifier immediately before
    /// `<`) and shouty legacy HTML (`<TABLE>`, all-caps, no lowercase)
    /// never match.
    private static func containsJSXComponentTag(_ code: String) -> Bool {
        code.range(
            of: #"(?m)(?:^|[\s({,])<[A-Z](?=[A-Za-z0-9]*[a-z])[A-Za-z0-9]*(?:\s|/>|>)"#,
            options: .regularExpression
        ) != nil
    }

    /// Removes the bodies of backtick template literals and `"""` multiline
    /// strings. An unclosed delimiter (from the 2 KB scan truncation) strips
    /// through to the end.
    private static func strippingEmbeddedStringBlocks(from code: String) -> String {
        var result = ""
        result.reserveCapacity(code.count)
        var remainder = Substring(code)
        let delimiters = ["\"\"\"", "`"]
        outer: while !remainder.isEmpty {
            var earliest: (open: Range<Substring.Index>, delimiter: String)?
            for delimiter in delimiters {
                if let range = remainder.range(of: delimiter) {
                    if earliest == nil || range.lowerBound < earliest!.open.lowerBound {
                        earliest = (range, delimiter)
                    }
                }
            }
            guard let match = earliest else {
                result += remainder
                break outer
            }
            result += remainder[..<match.open.lowerBound]
            let afterOpen = remainder[match.open.upperBound...]
            guard let close = afterOpen.range(of: match.delimiter) else { break outer }
            remainder = afterOpen[close.upperBound...]
        }
        return result
    }
}

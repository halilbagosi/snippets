import Foundation

enum SupportedLanguage: String, CaseIterable, Identifiable, Hashable {
    case glsl = "GLSL"
    case metal = "Metal"
    case hlsl = "HLSL"
    case swift = "Swift"
    case kotlin = "Kotlin"
    case rust = "Rust"
    case go = "Go"
    case python = "Python"
    case typescript = "TypeScript"
    case javascript = "JavaScript"
    case react = "React"
    case css = "CSS"
    case html = "HTML"
    case json = "JSON"
    case cpp = "C/C++"
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

    var accentHexLight: String {
        switch self {
        case .glsl: return "#005EA8"
        case .metal: return "#7E22CE"
        case .hlsl: return "#0369A1"
        case .swift: return "#9A3E00"
        case .kotlin: return "#5B21B6"
        case .rust: return "#92400E"
        case .go: return "#0E7490"
        case .python: return "#1D4ED8"
        case .typescript: return "#1D4ED8"
        case .javascript: return "#7A5D00"
        case .react: return "#0072A3"
        case .css: return "#9B1060"
        case .html: return "#A00000"
        case .json: return "#047857"
        case .cpp: return "#4338CA"
        case .unknown: return "#4B5563"
        }
    }

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
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return .unknown }

        if let first = code.first, first == "{" || first == "[" {
            if (try? JSONSerialization.jsonObject(with: Data(code.utf8))) != nil {
                return .json
            }
        }

        var bestMatch: (language: SupportedLanguage, score: Int) = (.unknown, 0)
        for rule in rules {
            let hits = rule.markers.reduce(into: 0) { count, marker in
                if code.contains(marker) { count += 1 }
            }
            if hits >= rule.minimumMatches && hits > bestMatch.score {
                bestMatch = (rule.language, hits)
            }
        }

        return bestMatch.language
    }
}

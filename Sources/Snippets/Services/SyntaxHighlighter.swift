import Foundation
#if canImport(AppKit)
import AppKit
import SwiftUI

enum TokenKind {
    case keyword
    case type
    case number
    case string
    case comment
    case attribute
    case property
    case tag
}

struct Token {
    let range: NSRange
    let kind: TokenKind
}

struct LanguageRules {
    var lineCommentPrefix: String? = "//"
    var blockComment: (open: String, close: String)? = ("/*", "*/")
    var stringDelimiters: [Character] = ["\"", "'"]
    var allowMultilineStringFor: Set<Character> = []
    var keywords: Set<String> = []
    var typeBuiltins: Set<String> = []
    var allowsCapitalizedTypes: Bool = true
    var attributePrefix: Character? = nil
    var hashIsLineComment: Bool = false
    var hashIsPreprocessor: Bool = false
}

@MainActor
enum SyntaxHighlighter {

    // MARK: - Caches

    /// Cache for fully-highlighted NSAttributedStrings (used by attributedString(for:...))
    private static let highlightCache: NSCache<NSString, NSAttributedString> = {
        let cache = NSCache<NSString, NSAttributedString>()
        cache.countLimit = 50
        cache.totalCostLimit = 5 * 1024 * 1024
        return cache
    }()

    /// Cache for NSFont instances keyed by fontSize
    private static var cachedFonts: [CGFloat: NSFont] = [:]

    /// Cache for NSColor instances keyed by "tokenKind_themeScheme"
    private static var cachedColors: [String: NSColor] = [:]

    private static func cachedFont(size: CGFloat) -> NSFont {
        if let font = cachedFonts[size] { return font }
        let font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        cachedFonts[size] = font
        return font
    }

    private static func cachedColor(for kind: TokenKind, theme: Theme) -> NSColor {
        let key = "\(kind)_\(schemeCacheKey(for: theme))"
        if let color = cachedColors[key] { return color }
        let color = _resolveColor(for: kind, theme: theme)
        cachedColors[key] = color
        return color
    }

    private static func schemeCacheKey(for theme: Theme) -> String {
        theme.scheme == .dark ? "dark" : "light"
    }

    private static func _resolveColor(for kind: TokenKind, theme: Theme) -> NSColor {
        switch kind {
        case .keyword, .attribute: return NSColor(theme.keyword)
        case .type, .property, .tag: return NSColor(theme.symbol)
        case .number: return NSColor(theme.symbol)
        case .string: return NSColor(theme.string)
        case .comment: return NSColor(theme.comment)
        }
    }

    // MARK: - Public API

    static func applyAttributes(
        to storage: NSTextStorage,
        language: SupportedLanguage,
        theme: Theme,
        fontSize: CGFloat = 13
    ) {
        let source = storage.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)

        let baseFont = cachedFont(size: fontSize)
        let baseColor = NSColor(theme.text)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: fullRange)

        let langRules = rules(for: language)
        let tokens = CodeTokenizer(source: source, rules: langRules).tokenize()
        for token in tokens {
            let color = cachedColor(for: token.kind, theme: theme)
            storage.addAttribute(.foregroundColor, value: color, range: token.range)
        }
        storage.endEditing()
    }

    static func attributedString(
        for source: String,
        language: SupportedLanguage,
        theme: Theme,
        fontSize: CGFloat = 13
    ) -> NSAttributedString {
        // Check cache first
        let cacheKey = "\(source.hashValue)_\(source.utf8.count)_\(language.rawValue)_\(schemeCacheKey(for: theme))_\(fontSize)" as NSString
        if let cached = highlightCache.object(forKey: cacheKey) {
            return cached
        }

        let storage = NSTextStorage(string: source)
        applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
        let result = NSAttributedString(attributedString: storage)

        // Store in cache before returning
        let estimatedCost = max(1, source.utf8.count * 4)
        highlightCache.setObject(result, forKey: cacheKey, cost: estimatedCost)
        return result
    }

    private static func color(for kind: TokenKind, theme: Theme) -> NSColor {
        return cachedColor(for: kind, theme: theme)
    }

    // MARK: - Static Lazy Language Rules

    private static let swiftRules: LanguageRules = {
        var r = LanguageRules()
        r.attributePrefix = "@"
        r.keywords = [
            "import", "func", "var", "let", "if", "else", "guard", "return", "while", "for",
            "in", "switch", "case", "default", "break", "continue", "class", "struct", "enum",
            "protocol", "extension", "init", "deinit", "public", "private", "internal",
            "fileprivate", "open", "static", "final", "override", "self", "Self", "super",
            "nil", "true", "false", "throw", "throws", "rethrows", "try", "catch", "do",
            "defer", "where", "as", "is", "async", "await", "some", "any", "inout",
            "mutating", "nonmutating", "associatedtype", "typealias", "operator", "prefix",
            "postfix", "infix", "lazy", "weak", "unowned", "convenience", "required",
            "optional", "indirect", "subscript", "set", "get", "willSet", "didSet"
        ]
        r.typeBuiltins = ["Int", "Double", "Float", "String", "Bool", "Array", "Dictionary", "Set", "Optional", "Any", "AnyObject", "Never", "Void"]
        return r
    }()

    private static let jsRules: LanguageRules = {
        var r = LanguageRules()
        r.keywords = [
            "import", "export", "from", "function", "var", "let", "const", "if", "else",
            "return", "while", "for", "in", "of", "switch", "case", "default", "break",
            "continue", "class", "extends", "new", "this", "super", "null", "undefined",
            "true", "false", "throw", "try", "catch", "finally", "async", "await", "yield",
            "typeof", "instanceof", "do", "delete", "void", "interface", "type", "enum",
            "public", "private", "protected", "readonly", "implements", "abstract",
            "namespace", "module", "declare", "as", "is", "keyof", "infer", "static",
            "get", "set"
        ]
        r.stringDelimiters = ["\"", "'", "`"]
        r.allowMultilineStringFor = ["`"]
        r.typeBuiltins = ["string", "number", "boolean", "any", "void", "never", "unknown", "object", "Array"]
        return r
    }()

    private static let pythonRules: LanguageRules = {
        var r = LanguageRules()
        r.lineCommentPrefix = "#"
        r.blockComment = nil
        r.hashIsLineComment = true
        r.keywords = [
            "import", "from", "as", "def", "class", "if", "elif", "else", "return",
            "while", "for", "in", "not", "and", "or", "is", "None", "True", "False",
            "try", "except", "finally", "raise", "with", "lambda", "pass", "break",
            "continue", "global", "nonlocal", "yield", "async", "await", "del", "assert"
        ]
        r.typeBuiltins = ["int", "float", "str", "bool", "list", "dict", "tuple", "set", "bytes", "object"]
        r.allowsCapitalizedTypes = true
        return r
    }()

    private static let shaderRules: LanguageRules = {
        var r = LanguageRules()
        r.keywords = [
            "void", "uniform", "varying", "attribute", "in", "out", "inout", "return",
            "if", "else", "for", "while", "do", "break", "continue", "struct", "const",
            "fragment", "vertex", "kernel", "using", "namespace", "metal", "discard",
            "true", "false", "layout", "precision", "highp", "mediump", "lowp",
            "include", "version", "define"
        ]
        r.typeBuiltins = [
            "vec2", "vec3", "vec4", "mat2", "mat3", "mat4", "mat2x2", "mat2x3", "mat2x4",
            "mat3x2", "mat3x3", "mat3x4", "mat4x2", "mat4x3", "mat4x4",
            "float", "int", "bool", "uint", "sampler1D", "sampler2D", "sampler3D",
            "samplerCube", "sampler2DArray", "texture2d", "texture3d", "texturecube",
            "half", "half2", "half3", "half4", "double", "ivec2", "ivec3", "ivec4",
            "uvec2", "uvec3", "uvec4", "bvec2", "bvec3", "bvec4", "float2", "float3",
            "float4", "int2", "int3", "int4", "uint2", "uint3", "uint4"
        ]
        r.allowsCapitalizedTypes = false
        r.hashIsPreprocessor = true
        return r
    }()

    private static let rustRules: LanguageRules = {
        var r = LanguageRules()
        r.keywords = [
            "fn", "let", "mut", "if", "else", "match", "return", "while", "for", "in",
            "loop", "break", "continue", "struct", "enum", "trait", "impl", "pub", "use",
            "mod", "self", "Self", "crate", "super", "where", "as", "move", "ref", "box",
            "true", "false", "async", "await", "dyn", "unsafe", "extern", "static",
            "const", "type"
        ]
        r.typeBuiltins = ["i8", "i16", "i32", "i64", "i128", "u8", "u16", "u32", "u64", "u128", "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc", "Arc"]
        return r
    }()

    private static let goRules: LanguageRules = {
        var r = LanguageRules()
        r.keywords = [
            "package", "import", "func", "var", "const", "if", "else", "return", "for",
            "range", "switch", "case", "default", "break", "continue", "struct", "interface",
            "type", "map", "chan", "go", "defer", "select", "fallthrough", "true", "false",
            "nil", "new", "make"
        ]
        r.typeBuiltins = ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32", "float64", "string", "bool", "byte", "rune", "error"]
        r.stringDelimiters = ["\"", "'", "`"]
        r.allowMultilineStringFor = ["`"]
        return r
    }()

    private static let kotlinRules: LanguageRules = {
        var r = LanguageRules()
        r.attributePrefix = "@"
        r.keywords = [
            "import", "package", "fun", "val", "var", "if", "else", "when", "return",
            "while", "for", "in", "out", "do", "break", "continue", "class", "object",
            "interface", "enum", "data", "sealed", "inline", "operator", "companion",
            "init", "null", "true", "false", "this", "super", "throw", "try", "catch",
            "finally", "is", "as", "abstract", "open", "override", "public", "private",
            "internal", "protected", "lateinit", "by", "where", "suspend"
        ]
        r.typeBuiltins = ["Int", "Long", "Short", "Byte", "Float", "Double", "Boolean", "Char", "String", "Any", "Unit", "Nothing", "List", "Map", "Set", "Array"]
        return r
    }()

    private static let cppRules: LanguageRules = {
        var r = LanguageRules()
        r.hashIsPreprocessor = true
        r.keywords = [
            "if", "else", "return", "while", "for", "do", "switch", "case", "default",
            "break", "continue", "class", "struct", "enum", "namespace", "using", "public",
            "private", "protected", "virtual", "override", "template", "typename", "const",
            "static", "extern", "new", "delete", "this", "true", "false", "nullptr", "NULL",
            "auto", "void", "sizeof", "typedef", "operator", "friend", "inline", "explicit",
            "constexpr", "noexcept", "decltype", "throw", "try", "catch", "union", "register",
            "volatile", "mutable", "include", "define", "ifdef", "ifndef", "endif", "pragma"
        ]
        r.typeBuiltins = ["int", "float", "double", "char", "bool", "long", "short", "unsigned", "signed", "wchar_t", "size_t", "string", "vector", "map", "set", "pair", "shared_ptr", "unique_ptr", "weak_ptr", "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t"]
        return r
    }()

    private static let cssRules: LanguageRules = {
        var r = LanguageRules()
        r.lineCommentPrefix = nil
        r.keywords = []
        r.typeBuiltins = []
        r.allowsCapitalizedTypes = false
        return r
    }()

    private static let htmlRules: LanguageRules = {
        var r = LanguageRules()
        r.lineCommentPrefix = nil
        r.blockComment = ("<!--", "-->")
        r.keywords = []
        r.allowsCapitalizedTypes = false
        return r
    }()

    private static let jsonRules: LanguageRules = {
        var r = LanguageRules()
        r.lineCommentPrefix = nil
        r.blockComment = nil
        r.keywords = ["true", "false", "null"]
        r.allowsCapitalizedTypes = false
        return r
    }()

    private static let unknownRules: LanguageRules = {
        var r = LanguageRules()
        r.keywords = []
        r.typeBuiltins = []
        return r
    }()

    private static func rules(for language: SupportedLanguage) -> LanguageRules {
        switch language {
        case .swift: return swiftRules
        case .javascript, .typescript, .react: return jsRules
        case .python: return pythonRules
        case .glsl, .metal, .hlsl: return shaderRules
        case .rust: return rustRules
        case .go: return goRules
        case .kotlin: return kotlinRules
        case .cpp: return cppRules
        case .css: return cssRules
        case .html: return htmlRules
        case .json: return jsonRules
        case .unknown: return unknownRules
        }
    }
}

private final class CodeTokenizer {
    private let nsString: NSString
    private let rules: LanguageRules
    private var pos: Int = 0
    private var tokens: [Token] = []

    // Pre-cached UTF16 arrays for comment delimiters (avoids re-conversion on every call)
    private let lineCommentUTF16: [unichar]?
    private let blockOpenUTF16: [unichar]?
    private let blockCloseUTF16: [unichar]?
    private let blockCloseFirstChar: unichar

    // Pre-built set of valid keyword/type identifier lengths for fast rejection
    private let knownIdentifierLengths: Set<Int>

    init(source: String, rules: LanguageRules) {
        self.nsString = source as NSString
        self.rules = rules

        // Pre-cache UTF16 for comment delimiters
        self.lineCommentUTF16 = rules.lineCommentPrefix.map { Array($0.utf16) }
        self.blockOpenUTF16 = rules.blockComment.map { Array($0.open.utf16) }
        self.blockCloseUTF16 = rules.blockComment.map { Array($0.close.utf16) }
        self.blockCloseFirstChar = rules.blockComment.map { Array($0.close.utf16).first ?? 0 } ?? 0

        // Build set of known keyword/type lengths for early rejection in matchIdentifier
        var lengths = Set<Int>()
        for kw in rules.keywords { lengths.insert(kw.utf16.count) }
        for tb in rules.typeBuiltins { lengths.insert(tb.utf16.count) }
        self.knownIdentifierLengths = lengths
    }

    func tokenize() -> [Token] {
        while pos < nsString.length {
            if let t = matchComment() { tokens.append(t); continue }
            if let t = matchPreprocessor() { tokens.append(t); continue }
            if let t = matchString() { tokens.append(t); continue }
            if let t = matchAttribute() { tokens.append(t); continue }
            if let t = matchIdentifier() { tokens.append(t); continue }
            if let t = matchNumber() { tokens.append(t); continue }
            pos += 1
        }
        return tokens
    }

    private func matchComment() -> Token? {
        if let utf16 = lineCommentUTF16, hasPrefixUTF16(utf16) {
            return scanLineComment(prefixLength: utf16.count)
        }
        if rules.hashIsLineComment, char(at: pos) == 0x23 /* # */ {
            return scanLineComment(prefixLength: 1)
        }
        if let openUTF16 = blockOpenUTF16, let closeUTF16 = blockCloseUTF16, hasPrefixUTF16(openUTF16) {
            let start = pos
            pos += openUTF16.count
            let closeFirst = blockCloseFirstChar
            while pos < nsString.length {
                // Fast first-char check before full prefix comparison
                if char(at: pos) == closeFirst && hasPrefixUTF16(closeUTF16) {
                    pos += closeUTF16.count
                    return Token(range: NSRange(location: start, length: pos - start), kind: .comment)
                }
                pos += 1
            }
            return Token(range: NSRange(location: start, length: pos - start), kind: .comment)
        }
        return nil
    }

    private func scanLineComment(prefixLength: Int) -> Token {
        let start = pos
        pos += prefixLength
        while pos < nsString.length, char(at: pos) != 0x0A {
            pos += 1
        }
        return Token(range: NSRange(location: start, length: pos - start), kind: .comment)
    }

    private func matchPreprocessor() -> Token? {
        guard rules.hashIsPreprocessor, char(at: pos) == 0x23 /* # */ else { return nil }
        let start = pos
        pos += 1
        while pos < nsString.length {
            let c = char(at: pos)
            if isIdentifierChar(c) { pos += 1 } else { break }
        }
        if pos > start + 1 {
            return Token(range: NSRange(location: start, length: pos - start), kind: .keyword)
        }
        pos = start
        return nil
    }

    private func matchString() -> Token? {
        let c = char(at: pos)
        guard let scalar = Unicode.Scalar(c) else { return nil }
        let charValue = Character(scalar)
        guard rules.stringDelimiters.contains(charValue) else { return nil }
        let start = pos
        let quote = c
        let allowMultiline = rules.allowMultilineStringFor.contains(charValue)
        pos += 1
        while pos < nsString.length {
            let cur = char(at: pos)
            if cur == 0x5C /* \\ */ {
                pos += 2
                continue
            }
            if cur == quote {
                pos += 1
                return Token(range: NSRange(location: start, length: pos - start), kind: .string)
            }
            if cur == 0x0A && !allowMultiline {
                break
            }
            pos += 1
        }
        return Token(range: NSRange(location: start, length: pos - start), kind: .string)
    }

    private func matchAttribute() -> Token? {
        guard let prefixChar = rules.attributePrefix else { return nil }
        let prefixCode = String(prefixChar).utf16.first!
        guard char(at: pos) == prefixCode else { return nil }
        let start = pos
        pos += 1
        while pos < nsString.length, isIdentifierChar(char(at: pos)) {
            pos += 1
        }
        if pos > start + 1 {
            return Token(range: NSRange(location: start, length: pos - start), kind: .attribute)
        }
        pos = start
        return nil
    }

    private func matchIdentifier() -> Token? {
        let c = char(at: pos)
        guard isIdentifierStart(c) else { return nil }
        let start = pos
        pos += 1
        while pos < nsString.length, isIdentifierChar(char(at: pos)) {
            pos += 1
        }
        let length = pos - start
        let range = NSRange(location: start, length: length)

        // Skip substring extraction if length doesn't match any known keyword/type length
        // (unless we need to check capitalizedTypes which has variable length)
        let lengthMatches = knownIdentifierLengths.contains(length)

        if lengthMatches {
            let text = nsString.substring(with: range)
            if rules.keywords.contains(text) {
                return Token(range: range, kind: .keyword)
            }
            if rules.typeBuiltins.contains(text) {
                return Token(range: range, kind: .type)
            }
            // Use O(1) utf16.count instead of O(n) text.count
            if rules.allowsCapitalizedTypes, let first = text.first, first.isUppercase, text.utf16.count > 1 {
                return Token(range: range, kind: .type)
            }
        } else if rules.allowsCapitalizedTypes && length > 1 {
            // No keyword/type match possible, but still check capitalized types
            let firstChar = char(at: start)
            if firstChar >= 0x41 && firstChar <= 0x5A { // A-Z
                return Token(range: range, kind: .type)
            }
        }

        return nil
    }

    private func matchNumber() -> Token? {
        let c = char(at: pos)
        if !isDigit(c) {
            if c == 0x2E /* . */, pos + 1 < nsString.length, isDigit(char(at: pos + 1)) {
            } else {
                return nil
            }
        }
        let start = pos
        var sawDot = false
        var sawExp = false
        while pos < nsString.length {
            let cur = char(at: pos)
            if isDigit(cur) || cur == 0x5F /* _ */ {
                pos += 1
            } else if cur == 0x2E /* . */, !sawDot, !sawExp {
                sawDot = true
                pos += 1
            } else if (cur == 0x65 || cur == 0x45) /* e/E */, !sawExp {
                sawExp = true
                pos += 1
                if pos < nsString.length, char(at: pos) == 0x2B || char(at: pos) == 0x2D {
                    pos += 1
                }
            } else if pos == start + 1, char(at: start) == 0x30, (cur == 0x78 || cur == 0x58 || cur == 0x62 || cur == 0x42 || cur == 0x6F || cur == 0x4F) {
                pos += 1
            } else if isHexDigit(cur), pos > start, (char(at: start + 1) == 0x78 || char(at: start + 1) == 0x58) {
                pos += 1
            } else {
                break
            }
        }
        return Token(range: NSRange(location: start, length: pos - start), kind: .number)
    }

    // MARK: - Character Utilities

    private func char(at index: Int) -> unichar {
        guard index < nsString.length else { return 0 }
        return nsString.character(at: index)
    }

    /// Optimized hasPrefix using pre-cached UTF16 arrays — avoids substring allocation entirely.
    private func hasPrefixUTF16(_ sUTF16: [unichar]) -> Bool {
        guard pos + sUTF16.count <= nsString.length else { return false }
        for i in 0..<sUTF16.count {
            if nsString.character(at: pos + i) != sUTF16[i] { return false }
        }
        return true
    }

    /// Legacy hasPrefix for arbitrary strings — uses character-by-character comparison (no substring allocation).
    private func hasPrefix(_ s: String) -> Bool {
        let sUTF16 = Array(s.utf16)
        guard pos + sUTF16.count <= nsString.length else { return false }
        for i in 0..<sUTF16.count {
            if nsString.character(at: pos + i) != sUTF16[i] { return false }
        }
        return true
    }

    private func isIdentifierStart(_ c: unichar) -> Bool {
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
    }

    private func isIdentifierChar(_ c: unichar) -> Bool {
        return isIdentifierStart(c) || isDigit(c)
    }

    private func isDigit(_ c: unichar) -> Bool {
        return c >= 0x30 && c <= 0x39
    }

    private func isHexDigit(_ c: unichar) -> Bool {
        return isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66)
    }
}

#endif

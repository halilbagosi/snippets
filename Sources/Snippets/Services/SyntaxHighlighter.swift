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

enum SyntaxHighlighter {

    static func applyAttributes(
        to storage: NSTextStorage,
        language: SupportedLanguage,
        theme: Theme,
        fontSize: CGFloat = 13
    ) {
        let source = storage.string
        let fullRange = NSRange(location: 0, length: (source as NSString).length)

        let baseFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let baseColor = NSColor(theme.text)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor
        ], range: fullRange)

        let rules = rules(for: language)
        let tokens = CodeTokenizer(source: source, rules: rules).tokenize()
        for token in tokens {
            let color = color(for: token.kind, theme: theme)
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
        let storage = NSTextStorage(string: source)
        applyAttributes(to: storage, language: language, theme: theme, fontSize: fontSize)
        return NSAttributedString(attributedString: storage)
    }

    private static func color(for kind: TokenKind, theme: Theme) -> NSColor {
        switch kind {
        case .keyword, .attribute: return NSColor(theme.keyword)
        case .type, .property, .tag: return NSColor(theme.symbol)
        case .number: return NSColor(theme.symbol)
        case .string: return NSColor(theme.string)
        case .comment: return NSColor(theme.comment)
        }
    }

    private static func rules(for language: SupportedLanguage) -> LanguageRules {
        switch language {
        case .swift:
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

        case .javascript, .typescript, .react:
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

        case .python:
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

        case .glsl, .metal, .hlsl:
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

        case .rust:
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

        case .go:
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

        case .kotlin:
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

        case .cpp:
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

        case .css:
            var r = LanguageRules()
            r.lineCommentPrefix = nil
            r.keywords = []
            r.typeBuiltins = []
            r.allowsCapitalizedTypes = false
            return r

        case .html:
            var r = LanguageRules()
            r.lineCommentPrefix = nil
            r.blockComment = ("<!--", "-->")
            r.keywords = []
            r.allowsCapitalizedTypes = false
            return r

        case .json:
            var r = LanguageRules()
            r.lineCommentPrefix = nil
            r.blockComment = nil
            r.keywords = ["true", "false", "null"]
            r.allowsCapitalizedTypes = false
            return r

        case .unknown:
            var r = LanguageRules()
            r.keywords = []
            r.typeBuiltins = []
            return r
        }
    }
}

private final class CodeTokenizer {
    private let nsString: NSString
    private let rules: LanguageRules
    private var pos: Int = 0
    private var tokens: [Token] = []

    init(source: String, rules: LanguageRules) {
        self.nsString = source as NSString
        self.rules = rules
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
        if let prefix = rules.lineCommentPrefix, hasPrefix(prefix) {
            return scanLineComment(prefixLength: (prefix as NSString).length)
        }
        if rules.hashIsLineComment, char(at: pos) == 0x23 /* # */ {
            return scanLineComment(prefixLength: 1)
        }
        if let block = rules.blockComment, hasPrefix(block.open) {
            let start = pos
            pos += (block.open as NSString).length
            while pos < nsString.length {
                if hasPrefix(block.close) {
                    pos += (block.close as NSString).length
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
        let range = NSRange(location: start, length: pos - start)
        let text = nsString.substring(with: range)
        if rules.keywords.contains(text) {
            return Token(range: range, kind: .keyword)
        }
        if rules.typeBuiltins.contains(text) {
            return Token(range: range, kind: .type)
        }
        if rules.allowsCapitalizedTypes, let first = text.first, first.isUppercase, text.count > 1 {
            return Token(range: range, kind: .type)
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

    private func char(at index: Int) -> unichar {
        guard index < nsString.length else { return 0 }
        return nsString.character(at: index)
    }

    private func hasPrefix(_ s: String) -> Bool {
        let len = (s as NSString).length
        guard pos + len <= nsString.length else { return false }
        return nsString.substring(with: NSRange(location: pos, length: len)) == s
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

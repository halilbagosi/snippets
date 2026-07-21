import Foundation

/// A tweakable parameter detected in a preview's entry component, shown as a
/// native control so users can play with the preview in real time.
struct PreviewParam: Equatable, Identifiable {
    enum Kind: Equatable {
        case number(default: Double)
        case integer(default: Int)
        case boolean(default: Bool)
        case color(defaultHex: String)
        case text(default: String)
        case choice(default: String, options: [String])
    }

    let name: String
    let kind: Kind

    var id: String { name }
}

enum PreviewParamValue: Equatable, Codable {
    case number(Double)
    case boolean(Bool)
    case string(String)

    /// JSON fragment for embedding in the preview's override script.
    var jsonLiteral: String {
        switch self {
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15
                ? String(Int(value)) : String(value)
        case .boolean(let value):
            return value ? "true" : "false"
        case .string(let value):
            let data = (try? JSONEncoder().encode([value])) ?? Data("[\"\"]".utf8)
            return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
        }
    }
}

/// Where a parameter's default value lives in the source, so a config can be
/// written back surgically. Declarations without a `// = value` annotation have
/// no literal to replace, so they record an insertion point instead.
enum ParamWriteTarget: Equatable {
    case literal(Range<String.Index>)
    case annotation(insertAt: String.Index)
}

/// A detected parameter together with the source location of its default.
struct DetectedParam: Equatable {
    let param: PreviewParam
    let target: ParamWriteTarget
}

/// Extracts default-valued props from a React entry component's destructured
/// signature — `({ amplitude = 1, glow = true, tint = "#ff94b8" })` — the
/// ReactBits convention. Only scalar defaults become controls; arrays,
/// objects and function defaults are left alone.
enum PreviewParamDetector {
    /// Single entry point for "what params does this preview have", replacing the
    /// per-flavor detection that was inlined in the preview view.
    static func detect(
        for language: SupportedLanguage, resolution: SnippetLinker.Resolution
    ) -> [DetectedParam] {
        let entry = resolution.sources.last?.code ?? ""
        let combined = resolution.sources.map(\.code).joined(separator: "\n")
        switch language.previewKind {
        case .web(.react): return detectReact(in: entry)
        case .web(.glsl): return detectGLSL(in: combined)
        case .metal: return detectMetal(in: combined)
        default: return []
        }
    }

    static func reactParams(in code: String) -> [PreviewParam] {
        detectReact(in: code).map(\.param)
    }

    static func detectReact(in code: String) -> [DetectedParam] {
        guard let signature = componentSignatureRange(in: code) else { return [] }
        var out: [DetectedParam] = []
        var seen: Set<String> = []
        let pattern = #"([A-Za-z_$][\w$]*)\s*=\s*("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|-?\d+(?:\.\d+)?|true|false)\s*[,}]"#
        for match in rangedMatches(pattern, in: code, region: signature) {
            guard let nameRange = Range(match.range(at: 1), in: code),
                  let literalRange = Range(match.range(at: 2), in: code) else { continue }
            let name = String(code[nameRange])
            let literal = String(code[literalRange])
            guard seen.insert(name).inserted else { continue }

            let kind: PreviewParam.Kind
            if literal == "true" || literal == "false" {
                kind = .boolean(default: literal == "true")
            } else if literal.hasPrefix("\"") || literal.hasPrefix("'") {
                let value = String(literal.dropFirst().dropLast())
                if value.range(of: #"^#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?$"#, options: .regularExpression) != nil {
                    kind = .color(defaultHex: value)
                } else if value.count <= 60, !value.contains("\\") {
                    let options = stringOptions(for: name, default: value, in: code)
                    kind = options.count > 1 ? .choice(default: value, options: options) : .text(default: value)
                } else {
                    continue
                }
            } else if let number = Double(literal) {
                kind = .number(default: number)
            } else {
                continue
            }
            out.append(DetectedParam(param: PreviewParam(name: name, kind: kind), target: .literal(literalRange)))
        }
        return out
    }

    /// The finite set of values a string prop can take, inferred from the
    /// code so the control can be a dropdown instead of a free-text field
    /// (ReactBits's `falloff = "linear"` pattern). Two sources: a TypeScript
    /// string-literal union for the prop, and equality comparisons against
    /// the prop name. Order: default first, then discovery order.
    static func stringOptions(for name: String, default fallback: String, in code: String) -> [String] {
        var options: [String] = [fallback]
        func add(_ value: String) {
            if !options.contains(value) { options.append(value) }
        }
        // TS union: `falloff?: "linear" | "exponential" | "gaussian"`
        if let union = code.range(
            of: #"\b\#(name)\s*\??\s*:\s*["'][\w-]+["'](?:\s*\|\s*["'][\w-]+["'])+"#,
            options: .regularExpression
        ) {
            for literal in allMatches(#"["']([\w-]+)["']"#, in: String(code[union]), groups: 1) {
                add(literal[0])
            }
        }
        // Comparisons: `falloff === "linear"` / `falloff !== 'gaussian'`
        for match in allMatches(#"\b\#(name)\s*[!=]==?\s*["']([\w-]+)["']"#, in: code, groups: 1) {
            add(match[0])
        }
        return options
    }

    // MARK: - GLSL

    /// Custom uniforms in a GLSL shader (the combined helper+entry source),
    /// excluding the built-ins the runtime already drives. Defaults come from
    /// a trailing `// = value` comment (`// = 1.5`, `// = #ff0044`,
    /// `// = true`); without one, floats/ints default to 0 and colors to
    /// black — exactly what an untouched uniform renders as.
    static func glslParams(in code: String) -> [PreviewParam] {
        detectGLSL(in: code).map(\.param)
    }

    static func detectGLSL(in code: String) -> [DetectedParam] {
        detectAnnotatedFields(
            pattern: #"(?m)^[ \t]*uniform\s+(float|int|bool|vec3|vec4)\s+(\w+)\s*;[ \t]*(?://[ \t]*=[ \t]*(\S+))?"#,
            in: code,
            excluding: ["iTime", "iResolution", "iMouse"]
        )
    }

    /// Shared type→kind mapping for the `// = value` annotation convention used by
    /// both GLSL uniforms and Metal `SnippetParams` fields.
    private static func annotatedKind(type: String, annotated: String) -> PreviewParam.Kind? {
        switch type {
        case "float":
            return .number(default: Double(annotated) ?? 0)
        case "int":
            return .integer(default: Int(annotated) ?? 0)
        case "bool":
            return .boolean(default: annotated == "true")
        case "vec3", "vec4", "float3", "float4":
            return .color(defaultHex: annotated.hasPrefix("#") ? annotated : "#000000")
        default:
            return nil
        }
    }

    // MARK: - Metal

    /// Fields of a snippet-declared `struct SnippetParams { … }`, bound by
    /// the renderer at fragment buffer(1). Same `// = default` convention as
    /// GLSL. Field order is declaration order — it defines the buffer layout.
    static func metalParams(in code: String) -> [PreviewParam] {
        detectMetal(in: code).map(\.param)
    }

    static func detectMetal(in code: String) -> [DetectedParam] {
        guard let structRange = code.range(
            of: #"struct\s+SnippetParams\s*\{[^}]*\}"#, options: .regularExpression
        ) else { return [] }
        return detectAnnotatedFields(
            pattern: #"(?m)^[ \t]*(float3|float4|float|int)\s+(\w+)\s*;[ \t]*(?://[ \t]*=[ \t]*(\S+))?"#,
            in: code,
            region: structRange
        )
    }

    /// Shared match/dedupe/classify loop for the `// = value` annotation
    /// convention: destructures `type`/`name`/`whole` from each match, skips
    /// excluded and duplicate names, chooses `.literal` when the trailing
    /// annotation matched or `.annotation(insertAt:)` when it didn't, and maps
    /// the type through `annotatedKind`.
    private static func detectAnnotatedFields(
        pattern: String,
        in code: String,
        region: Range<String.Index>? = nil,
        excluding excluded: Set<String> = []
    ) -> [DetectedParam] {
        var out: [DetectedParam] = []
        var seen: Set<String> = []
        for match in rangedMatches(pattern, in: code, region: region) {
            guard let typeRange = Range(match.range(at: 1), in: code),
                  let nameRange = Range(match.range(at: 2), in: code),
                  let wholeRange = Range(match.range, in: code) else { continue }
            let name = String(code[nameRange])
            guard !excluded.contains(name),
                  seen.insert(name).inserted else { continue }

            let annotated: String
            let target: ParamWriteTarget
            if let literalRange = Range(match.range(at: 3), in: code) {
                annotated = String(code[literalRange])
                target = .literal(literalRange)
            } else {
                annotated = ""
                target = .annotation(insertAt: wholeRange.upperBound)
            }
            guard let kind = annotatedKind(type: String(code[typeRange]), annotated: annotated) else { continue }
            out.append(DetectedParam(param: PreviewParam(name: name, kind: kind), target: target))
        }
        return out
    }

    /// Packs current values into the exact byte layout MSL gives
    /// `SnippetParams` (float/int: 4-byte align; float3/float4: 16-byte align
    /// and size; stride rounded to the widest alignment). Metal-side struct
    /// and this packer must agree, which they do by construction — both walk
    /// the same declaration order.
    static func packMetalParams(
        _ params: [PreviewParam], overrides: [String: PreviewParamValue]
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        var maxAlignment = 4

        func pad(to alignment: Int) {
            maxAlignment = max(maxAlignment, alignment)
            while bytes.count % alignment != 0 { bytes.append(0) }
        }
        func appendFloat(_ value: Float) {
            withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
        }

        for param in params {
            let override = overrides[param.name]
            switch param.kind {
            case .number(let fallback):
                pad(to: 4)
                if case .number(let value) = override { appendFloat(Float(value)) }
                else { appendFloat(Float(fallback)) }
            case .integer(let fallback):
                pad(to: 4)
                var value = Int32(fallback)
                if case .number(let v) = override { value = Int32(v.rounded()) }
                withUnsafeBytes(of: value) { bytes.append(contentsOf: $0) }
            case .color(let fallbackHex):
                pad(to: 16)
                var hex = fallbackHex
                if case .string(let v) = override { hex = v }
                let (r, g, b) = rgbComponents(ofHex: hex)
                appendFloat(r); appendFloat(g); appendFloat(b); appendFloat(1)
            case .boolean, .text, .choice:
                continue
            }
        }
        pad(to: maxAlignment)
        return bytes
    }

    static func rgbComponents(ofHex hex: String) -> (Float, Float, Float) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else { return (0, 0, 0) }
        return (
            Float((value >> 16) & 0xFF) / 255,
            Float((value >> 8) & 0xFF) / 255,
            Float(value & 0xFF) / 255
        )
    }

    /// Range of the `{ … }` destructuring pattern of the mount component's first
    /// argument, in `code`'s own index space. Searches the default-exported /
    /// conventional component the same way the mount-target detection does:
    /// `function X({…})` or `X = ({…})` arrow forms.
    private static func componentSignatureRange(in code: String) -> Range<String.Index>? {
        let target = WebPreviewHTMLBuilder.reactMountTarget(in: code)
        let patterns: [String]
        if let target {
            patterns = [
                #"function\s+\#(target)\s*\(\s*\{"#,
                #"\#(target)\s*=\s*(?:async\s*)?\(\s*\{"#
            ]
        } else {
            // Anonymous default export: `export default function ({…})` /
            // `export default ({…}) =>`.
            patterns = [
                #"export\s+default\s+function\s*\w*\s*\(\s*\{"#,
                #"export\s+default\s+(?:async\s*)?\(\s*\{"#
            ]
        }
        for pattern in patterns {
            guard let match = code.range(of: pattern, options: .regularExpression) else { continue }
            // The regex ends at the opening `{` of the destructuring pattern.
            let braceIndex = code.index(before: match.upperBound)
            if let end = balancedBraceEnd(in: code, from: braceIndex) {
                return braceIndex..<end
            }
        }
        return nil
    }

    private static func balancedBraceEnd(in code: String, from: String.Index) -> String.Index? {
        var depth = 0
        var index = from
        while index < code.endIndex {
            let char = code[index]
            if char == "{" { depth += 1 }
            if char == "}" {
                depth -= 1
                if depth == 0 { return code.index(after: index) }
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// Regex matches with their capture ranges intact, restricted to `region`
    /// (defaults to the whole string). Matching always runs against the full
    /// source so every returned range is valid in the caller's original string.
    private static func rangedMatches(
        _ pattern: String, in text: String, region: Range<String.Index>? = nil
    ) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(region ?? text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range)
    }

    /// With `allowMissingTrailing`, unmatched optional trailing groups are
    /// simply omitted from the capture array instead of dropping the match.
    private static func allMatches(
        _ pattern: String, in text: String, groups: Int, allowMissingTrailing: Bool = false
    ) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > groups else { return nil }
            var captured: [String] = []
            for group in 1...groups {
                if let r = Range(match.range(at: group), in: text) {
                    captured.append(String(text[r]))
                } else if !allowMissingTrailing {
                    return nil
                }
            }
            return captured
        }
    }
}

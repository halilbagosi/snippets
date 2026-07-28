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

/// Compiled `NSRegularExpression`s, kept for the life of the process.
///
/// The parameter detectors run on the main thread every time SwiftUI
/// re-evaluates a preview — which a parameter-slider drag does on every frame —
/// and each entry point used to compile its patterns from scratch. Compilation,
/// not matching, dominated the cost: detecting an 11-parameter React component
/// compiled ~25 expressions per call, at ~2 ms total, a quarter of a 120 Hz
/// frame budget spent re-deriving a result that had not changed.
///
/// The pattern set is small and fixed apart from the ones built around a
/// parameter's own name, so cardinality tracks the distinct parameter names in
/// a library. The cap only guards against a pathological snippet collection.
/// `NSRegularExpression` is itself thread-safe for matching; only the table
/// needs guarding, so a plain lock is enough and keeps this usable from any
/// isolation domain (the detectors run on the main actor today, and off it in
/// tests).
final class RegexCache: @unchecked Sendable {
    static let shared = RegexCache()

    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]
    private let limit = 512

    static func regex(_ pattern: String) -> NSRegularExpression? {
        shared.regex(pattern)
    }

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[pattern] { return hit }
        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
        if cache.count >= limit { cache.removeAll(keepingCapacity: true) }
        cache[pattern] = compiled
        return compiled
    }
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
                // Escape sequences are decoded so the control shows the real
                // string; `PreviewParamWriter` re-escapes on the way back, so a
                // value containing the delimiter survives a full round trip.
                let value = unescapedLiteralBody(literal)
                if firstMatchRange(#"^#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?$"#, in: value) != nil {
                    kind = .color(defaultHex: value)
                } else if value.count <= 60 {
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

    /// Props a *usage* snippet sets explicitly on the component it mounts —
    /// `<Strands count={3} glass />`.
    ///
    /// These are the values the preview actually renders: the usage element's
    /// props beat the component's destructured defaults. A saved config that
    /// only rewrote the defaults therefore changed nothing on screen, so this
    /// is where such a config has to be written back.
    static func detectJSXUsage(in code: String) -> [DetectedParam] {
        guard let element = usageElementRange(in: code) else { return [] }
        var out: [DetectedParam] = []
        var seen: Set<String> = []
        // Scanned, not matched: a regex cannot skip *over* an expression prop.
        // `colors={["#F97316", …]}` would otherwise read as a bare attribute
        // and the scan would then walk into the array and mint parameters out
        // of its contents.
        for (nameRange, valueRange) in jsxAttributes(in: code, region: element) {
            let name = String(code[nameRange])
            guard seen.insert(name).inserted else { continue }

            guard let valueRange else {
                // Bare attribute: `glass` means `glass={true}`. There is no
                // literal to replace, so a config writes over the name itself.
                out.append(DetectedParam(
                    param: PreviewParam(name: name, kind: .boolean(default: true)),
                    target: .literal(nameRange)
                ))
                continue
            }
            let literal = String(code[valueRange])
            // Inside `{ }` the literal is the braced expression; the writer
            // replaces the whole thing, so keep the braces in the range and
            // read the value from within them.
            let inner = literal.hasPrefix("{")
                ? literal.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
                : literal

            let kind: PreviewParam.Kind
            if inner == "true" || inner == "false" {
                kind = .boolean(default: inner == "true")
            } else if inner.hasPrefix("\"") || inner.hasPrefix("'") {
                let value = unescapedLiteralBody(String(inner))
                if firstMatchRange(#"^#[0-9a-fA-F]{3}(?:[0-9a-fA-F]{3})?$"#, in: value) != nil {
                    kind = .color(defaultHex: value)
                } else if value.count <= 60 {
                    let options = stringOptions(for: name, default: value, in: code)
                    kind = options.count > 1 ? .choice(default: value, options: options) : .text(default: value)
                } else {
                    continue
                }
            } else if let number = Double(inner) {
                kind = .number(default: number)
            } else {
                continue
            }
            out.append(DetectedParam(
                param: PreviewParam(name: name, kind: kind), target: .literal(valueRange)
            ))
        }
        return out
    }

    /// Walks a JSX element's attribute region, yielding each attribute's name
    /// range and the range of its value (nil for a bare attribute).
    ///
    /// Values are returned whole — including the braces of `{…}` — and the
    /// walk steps over them rather than through them, so an array, object or
    /// arrow-function prop contributes nothing but also cannot leak its
    /// innards into the result. Spread props (`{...rest}`) are skipped the
    /// same way.
    private static func jsxAttributes(
        in code: String, region: Range<String.Index>
    ) -> [(name: Range<String.Index>, value: Range<String.Index>?)] {
        var out: [(Range<String.Index>, Range<String.Index>?)] = []
        var i = region.lowerBound

        func skipSpace() {
            while i < region.upperBound, code[i].isWhitespace { i = code.index(after: i) }
        }
        /// Advances past a balanced `{…}` or a quoted string starting at `i`,
        /// returning the range it covered.
        func skipDelimited() -> Range<String.Index>? {
            guard i < region.upperBound else { return nil }
            let start = i
            let opener = code[i]
            if opener == "\"" || opener == "'" {
                i = code.index(after: i)
                while i < region.upperBound {
                    if code[i] == "\\" {
                        i = code.index(i, offsetBy: 2, limitedBy: region.upperBound) ?? region.upperBound
                        continue
                    }
                    if code[i] == opener { i = code.index(after: i); return start..<i }
                    i = code.index(after: i)
                }
                return start..<i
            }
            guard opener == "{" else { return nil }
            var depth = 0
            while i < region.upperBound {
                let ch = code[i]
                if ch == "\"" || ch == "'" { _ = skipDelimited(); continue }
                if ch == "{" { depth += 1 }
                if ch == "}" {
                    depth -= 1
                    i = code.index(after: i)
                    if depth == 0 { return start..<i }
                    continue
                }
                i = code.index(after: i)
            }
            return start..<i
        }

        while i < region.upperBound {
            skipSpace()
            guard i < region.upperBound else { break }
            let ch = code[i]
            guard ch.isLetter || ch == "_" || ch == "$" else {
                if skipDelimited() == nil { i = code.index(after: i) }
                continue
            }
            let nameStart = i
            while i < region.upperBound,
                  code[i].isLetter || code[i].isNumber || code[i] == "_" || code[i] == "$" || code[i] == "-" {
                i = code.index(after: i)
            }
            let nameRange = nameStart..<i
            let afterName = i
            skipSpace()
            guard i < region.upperBound, code[i] == "=" else {
                i = afterName
                out.append((nameRange, nil))
                continue
            }
            i = code.index(after: i)
            skipSpace()
            out.append((nameRange, skipDelimited()))
        }
        return out
    }

    /// The attribute region of the first capitalized JSX element in a usage
    /// snippet: from after the component's tag name to the closing `>`.
    /// Returns nil for anything that is not a usage snippet, so plain markup
    /// and component sources are left alone.
    private static func usageElementRange(in code: String) -> Range<String.Index>? {
        guard let tag = firstMatchRange(#"<[A-Z][\w$]*"#, in: code) else { return nil }
        var depth = 0
        var index = tag.upperBound
        while index < code.endIndex {
            let ch = code[index]
            if ch == "{" { depth += 1 }
            else if ch == "}" { depth -= 1 }
            else if ch == ">" && depth == 0 {
                return tag.upperBound..<index
            }
            index = code.index(after: index)
        }
        return nil
    }

    /// The finite set of values a string prop can take, inferred from the
    /// code so the control can be a dropdown instead of a free-text field
    /// (ReactBits's `falloff = "linear"` pattern). Four sources: a TypeScript
    /// string-literal union for the prop, equality comparisons against the
    /// prop name, the keys of an object literal the prop is used to index, and
    /// the cases of a `switch` over it. Order: default first, then discovery
    /// order.
    static func stringOptions(for name: String, default fallback: String, in code: String) -> [String] {
        var options: [String] = [fallback]
        func add(_ value: String) {
            if !options.contains(value) { options.append(value) }
        }
        // TS union: `falloff?: "linear" | "exponential" | "gaussian"`
        if let union = firstMatchRange(
            #"\b\#(name)\s*\??\s*:\s*["'][\w-]+["'](?:\s*\|\s*["'][\w-]+["'])+"#,
            in: code
        ) {
            for literal in allMatches(#"["']([\w-]+)["']"#, in: String(code[union]), groups: 1) {
                add(literal[0])
            }
        }
        // Comparisons: `falloff === "linear"` / `falloff !== 'gaussian'`
        for match in allMatches(#"\b\#(name)\s*[!=]==?\s*["']([\w-]+)["']"#, in: code, groups: 1) {
            add(match[0])
        }
        // Lookup table: `FALLOFF_CURVES[falloff]` traced back to its
        // `const FALLOFF_CURVES = { linear: …, smooth: … }`. The keys are the
        // accepted values — how ReactBits states a curve or easing prop's
        // options when there is no TypeScript union to read.
        for key in lookupTableKeys(indexedBy: name, in: code) { add(key) }
        // `switch (falloff) { case 'linear': … }`
        if let block = bracedBlock(
            after: #"switch\s*\(\s*\#(qualified(name))\s*\)\s*\{"#, in: code
        ) {
            for match in allMatches(
                #"\bcase\s+["']([\w-]+)["']\s*:"#, in: String(code[block]), groups: 1
            ) {
                add(match[0])
            }
        }
        return options
    }

    /// Pattern matching a read of the prop, whether bare or reached through
    /// the object it was bundled into — `falloff`, `p.falloff`, `opts.p.falloff`.
    /// A component that hands its props to a render loop as one object still
    /// names the prop at the end of the chain.
    private static func qualified(_ name: String) -> String {
        #"(?:[A-Za-z_$][\w$]*\s*\.\s*)*\#(name)"#
    }

    /// Top-level keys of every object literal the prop indexes.
    ///
    /// Each `TABLE[prop]` read is resolved back to `TABLE`'s declaration; a
    /// table declared elsewhere (an import, a prop) simply contributes nothing.
    private static func lookupTableKeys(indexedBy name: String, in code: String) -> [String] {
        var keys: [String] = []
        var seen: Set<String> = []
        for match in allMatches(
            #"\b([A-Za-z_$][\w$]*)\s*\[\s*\#(qualified(name))\s*\]"#, in: code, groups: 1
        ) {
            let table = match[0]
            guard seen.insert(table).inserted,
                  // `[^\n]*` spans an optional type annotation, whose own `=>`
                  // rules out matching the `=` directly.
                  let block = bracedBlock(
                      after: #"\b(?:const|let|var)\s+\#(table)\b[^\n]*=\s*\{"#, in: code
                  )
            else { continue }
            keys.append(contentsOf: objectLiteralKeys(in: code, block: block))
        }
        return keys
    }

    /// Keys at the top level of an object literal, given the range of its
    /// `{ … }`. Nested objects, arrays and call arguments are stepped over and
    /// strings skipped whole, so a nested value cannot contribute keys of its
    /// own. Spreads and shorthand methods match nothing and are dropped.
    private static func objectLiteralKeys(in code: String, block: Range<String.Index>) -> [String] {
        var starts: [String.Index] = []
        var depth = 0
        var atEntryStart = false
        var index = block.lowerBound

        while index < block.upperBound {
            let char = code[index]
            if char == "\"" || char == "'" || char == "`" {
                if atEntryStart { starts.append(index); atEntryStart = false }
                index = skipStringLiteral(in: code, from: index, limit: block.upperBound)
                continue
            }
            if char == "{" || char == "[" || char == "(" {
                if atEntryStart { starts.append(index); atEntryStart = false }
                depth += 1
                // The literal's own opening brace begins its first entry.
                if depth == 1 { atEntryStart = true }
                index = code.index(after: index)
                continue
            }
            if char == "}" || char == "]" || char == ")" {
                depth -= 1
                atEntryStart = false
                index = code.index(after: index)
                continue
            }
            if char == "," && depth == 1 {
                atEntryStart = true
                index = code.index(after: index)
                continue
            }
            if atEntryStart && !char.isWhitespace {
                starts.append(index)
                atEntryStart = false
            }
            index = code.index(after: index)
        }

        return starts.compactMap { start in
            // A key and its colon; 80 characters is far past any real one.
            let segment = String(code[start..<block.upperBound].prefix(80))
            return allMatches(
                #"^["']?([A-Za-z_$][\w$-]*)["']?\s*:"#, in: segment, groups: 1
            ).first?[0]
        }
    }

    /// Range of the `{ … }` block opened by the first match of `pattern`,
    /// which must end at the opening brace itself.
    private static func bracedBlock(after pattern: String, in code: String) -> Range<String.Index>? {
        guard let match = firstMatchRange(pattern, in: code) else { return nil }
        let brace = code.index(before: match.upperBound)
        guard code[brace] == "{", let end = balancedBraceEnd(in: code, from: brace) else { return nil }
        return brace..<end
    }

    /// Index just past the string literal whose opening quote is at `from`.
    private static func skipStringLiteral(
        in code: String, from: String.Index, limit: String.Index
    ) -> String.Index {
        let quote = code[from]
        var index = code.index(after: from)
        while index < limit {
            if code[index] == "\\" {
                index = code.index(index, offsetBy: 2, limitedBy: limit) ?? limit
                continue
            }
            if code[index] == quote { return code.index(after: index) }
            index = code.index(after: index)
        }
        return limit
    }

    /// Combines what a usage snippet pins with what the component declares.
    ///
    /// The usage states a prop's current value and owns the location a config
    /// writes it back to; the component states what the value may be. Only the
    /// component's source carries the option set — a usage is one JSX element
    /// and has no `FALLOFF_CURVES` or type union in it — so a prop the
    /// component detects as a choice stays a choice once pinned, instead of
    /// degrading to a free-text field.
    static func merging(usage: [DetectedParam], into declared: [DetectedParam]) -> [DetectedParam] {
        let pinned = Dictionary(
            usage.map { ($0.param.name, $0) }, uniquingKeysWith: { first, _ in first }
        )
        return declared.map { declaredParam in
            guard let effective = pinned[declaredParam.param.name] else { return declaredParam }
            guard case .choice(_, let options) = declaredParam.param.kind else { return effective }
            let value: String
            switch effective.param.kind {
            case .text(let pinnedValue), .choice(let pinnedValue, _): value = pinnedValue
            default: return effective
            }
            // A usage may pin a value the component's option set never lists;
            // leading with it keeps the picker showing what is on screen.
            return DetectedParam(
                param: PreviewParam(
                    name: effective.param.name,
                    kind: .choice(
                        default: value,
                        options: options.contains(value) ? options : [value] + options
                    )
                ),
                target: effective.target
            )
        }
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
            guard let match = firstMatchRange(pattern, in: code) else { continue }
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
        guard let regex = RegexCache.regex(pattern) else { return [] }
        let range = NSRange(region ?? text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range)
    }

    /// Range of the first match of `pattern`, in `text`'s own index space.
    /// Replaces `String.range(of:options:.regularExpression)`, which recompiles
    /// the expression on every call.
    private static func firstMatchRange(_ pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = RegexCache.regex(pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return Range(match.range, in: text)
    }

    /// Strips a JS string literal's surrounding quotes and decodes the escape
    /// sequences `PreviewParamWriter` emits, so the detected default is the
    /// value the user actually sees. Unknown escapes keep their escaped
    /// character (`\d` → `d`), matching JavaScript.
    private static func unescapedLiteralBody(_ literal: String) -> String {
        var out = ""
        var iterator = literal.dropFirst().dropLast().makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let escapedCharacter = iterator.next() else {
                out.append(character)
                continue
            }
            switch escapedCharacter {
            case "n": out.append("\n")
            case "r": out.append("\r")
            case "t": out.append("\t")
            default: out.append(escapedCharacter)
            }
        }
        return out
    }

    /// With `allowMissingTrailing`, unmatched optional trailing groups are
    /// simply omitted from the capture array instead of dropping the match.
    private static func allMatches(
        _ pattern: String, in text: String, groups: Int, allowMissingTrailing: Bool = false
    ) -> [[String]] {
        guard let regex = RegexCache.regex(pattern) else { return [] }
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

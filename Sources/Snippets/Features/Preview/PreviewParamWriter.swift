import Foundation

/// Writes parameter values back into a snippet's source, so a saved
/// configuration becomes what the code actually declares.
///
/// Edits are applied by assembling a new string left-to-right from the
/// original, which sidesteps index invalidation entirely — replacing ranges
/// in place would leave later `String.Index` values dangling.
enum PreviewParamWriter {
    static func apply(
        _ values: [String: PreviewParamValue],
        to code: String,
        params: [DetectedParam]
    ) -> String {
        let edits: [(range: Range<String.Index>, text: String)] = params
            .compactMap { detected in
                guard let value = values[detected.param.name] else { return nil }
                switch detected.target {
                case .literal(let range):
                    return (range, literalText(value, replacing: String(code[range])))
                case .annotation(let index):
                    return (index..<index, "  // = " + bareText(value))
                }
            }
            .sorted { $0.range.lowerBound < $1.range.lowerBound }

        var out = ""
        var cursor = code.startIndex
        for edit in edits {
            guard edit.range.lowerBound >= cursor else { continue }
            out += code[cursor..<edit.range.lowerBound]
            out += edit.text
            cursor = edit.range.upperBound
        }
        out += code[cursor...]
        return out
    }

    /// Renders a value in the same shape as the literal it replaces, so a
    /// single-quoted JS string stays single-quoted and a bare `#rrggbb`
    /// annotation stays bare.
    private static func literalText(_ value: PreviewParamValue, replacing existing: String) -> String {
        switch value {
        case .number(let number):
            return numberText(number)
        case .boolean(let flag):
            return flag ? "true" : "false"
        case .string(let string):
            guard let quote = existing.first, quote == "\"" || quote == "'" else { return string }
            return "\(quote)\(string)\(quote)"
        }
    }

    private static func bareText(_ value: PreviewParamValue) -> String {
        switch value {
        case .number(let number): return numberText(number)
        case .boolean(let flag): return flag ? "true" : "false"
        case .string(let string): return string
        }
    }

    private static func numberText(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

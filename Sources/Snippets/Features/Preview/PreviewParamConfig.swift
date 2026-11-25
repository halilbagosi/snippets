import Foundation

/// A named set of preview parameter values. `Default` is captured the first
/// time a config is saved and records what the source declared just before —
/// it is immutable and always sorts first.
struct PreviewParamConfig: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var values: [String: PreviewParamValue]
    var isDefault: Bool
    /// The config's own code, for configs created from an efficiency fix
    /// (and `Default`, once one exists). Nil = uses `Default`'s code.
    /// Never read while the config is active: `snippet.code` is the truth then.
    var code: String? = nil
    /// The rating a code config was created from, so its remaining
    /// suggestions can still be added to it.
    var sourceReviewID: UUID? = nil
}

/// Pure lifecycle transforms over a snippet's config list. Kept free of
/// SwiftData and SwiftUI so the rules are directly testable.
enum PreviewParamConfigStore {
    static let defaultName = "Default"

    /// Values as the source currently declares them — the baseline a `Default`
    /// config records.
    static func declaredValues(_ declared: [PreviewParam]) -> [String: PreviewParamValue] {
        var values: [String: PreviewParamValue] = [:]
        for param in declared {
            switch param.kind {
            case .number(let value): values[param.name] = .number(value)
            case .integer(let value): values[param.name] = .number(Double(value))
            case .boolean(let value): values[param.name] = .boolean(value)
            case .color(let hex): values[param.name] = .string(hex)
            case .text(let text): values[param.name] = .string(text)
            case .choice(let selected, _): values[param.name] = .string(selected)
            }
        }
        return values
    }

    /// Saves `current` as a new named config. On the very first save this also
    /// prepends a frozen `Default` holding the declared (pre-change) values.
    static func saving(
        current: [String: PreviewParamValue],
        declared: [PreviewParam],
        named name: String,
        into configs: [PreviewParamConfig]
    ) -> [PreviewParamConfig] {
        var result = configs
        if !result.contains(where: \.isDefault) {
            result.insert(
                PreviewParamConfig(
                    id: UUID(), name: defaultName,
                    values: declaredValues(declared), isDefault: true
                ),
                at: 0
            )
        }
        // A config records every declared param, so applying it fully
        // determines the preview rather than half-overriding the source.
        let values = overlay(current: current, declared: declared)
        result.append(
            PreviewParamConfig(id: UUID(), name: name, values: values, isDefault: false)
        )
        return result
    }

    /// Saves a code variant as a new named config. Creates `Default` first when
    /// absent, and lets `Default` capture `currentCode` the first time a code
    /// config exists, so the original is always one click away.
    static func savingCodeVariant(
        code: String,
        values: [String: PreviewParamValue],
        named name: String,
        sourceReviewID: UUID?,
        currentCode: String,
        declared: [PreviewParam],
        into configs: [PreviewParamConfig]
    ) -> (configs: [PreviewParamConfig], newID: UUID) {
        var result = configs
        if let index = result.firstIndex(where: \.isDefault) {
            if result[index].code == nil { result[index].code = currentCode }
        } else {
            result.insert(
                PreviewParamConfig(
                    id: UUID(), name: defaultName,
                    values: declaredValues(declared), isDefault: true,
                    code: currentCode
                ),
                at: 0
            )
        }
        let newID = UUID()
        result.append(
            PreviewParamConfig(
                id: newID, name: name,
                values: overlay(current: values, declared: declared), isDefault: false,
                code: code, sourceReviewID: sourceReviewID
            )
        )
        return (result, newID)
    }

    /// The flush rule: writes `code` into the active config only if that config
    /// owns code (a code config, or a `Default` that has captured code).
    static func storingActiveCode(
        _ code: String, activeID: UUID?, in configs: [PreviewParamConfig]
    ) -> [PreviewParamConfig] {
        guard let activeID,
              let index = configs.firstIndex(where: { $0.id == activeID }),
              configs[index].code != nil else { return configs }
        var result = configs
        result[index].code = code
        return result
    }

    /// The code `snippet.code` should become when `id` is activated: the
    /// config's own code, else `Default`'s, else nil (leave the code alone).
    static func codeToActivate(for id: UUID, in configs: [PreviewParamConfig]) -> String? {
        guard let config = configs.first(where: { $0.id == id }) else { return nil }
        return config.code ?? configs.first(where: \.isDefault)?.code
    }

    static func updating(
        id: UUID,
        to current: [String: PreviewParamValue],
        declared: [PreviewParam],
        in configs: [PreviewParamConfig]
    ) -> [PreviewParamConfig] {
        guard let index = configs.firstIndex(where: { $0.id == id }),
              !configs[index].isDefault else { return configs }
        var result = configs
        result[index].values = overlay(current: current, declared: declared)
        return result
    }

    /// Declared values overlaid with the user's current overrides, keeping only
    /// keys the code still declares. Shared by `saving` and `updating` so both
    /// compute a config's stored values identically.
    private static func overlay(
        current: [String: PreviewParamValue], declared: [PreviewParam]
    ) -> [String: PreviewParamValue] {
        var values = declaredValues(declared)
        for (key, value) in current where values[key] != nil {
            values[key] = value
        }
        return values
    }

    static func deleting(id: UUID, from configs: [PreviewParamConfig]) -> [PreviewParamConfig] {
        guard let config = configs.first(where: { $0.id == id }), !config.isDefault else {
            return configs
        }
        return configs.filter { $0.id != id }
    }

    /// A config's values narrowed to params the source still declares, so a
    /// stale config degrades quietly instead of writing dead keys.
    static func resolvedValues(
        for config: PreviewParamConfig, declared: [PreviewParam]
    ) -> [String: PreviewParamValue] {
        let names = Set(declared.map(\.name))
        return config.values.filter { names.contains($0.key) }
    }
}

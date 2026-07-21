import Foundation

/// A named set of preview parameter values. `Default` is captured the first
/// time a config is saved and records what the source declared just before —
/// it is immutable and always sorts first.
struct PreviewParamConfig: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var values: [String: PreviewParamValue]
    var isDefault: Bool
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
        var values = declaredValues(declared)
        for (key, value) in current where values[key] != nil {
            values[key] = value
        }
        result.append(
            PreviewParamConfig(id: UUID(), name: name, values: values, isDefault: false)
        )
        return result
    }

    static func updating(
        id: UUID,
        to current: [String: PreviewParamValue],
        declared: [PreviewParam],
        in configs: [PreviewParamConfig]
    ) -> [PreviewParamConfig] {
        guard let index = configs.firstIndex(where: { $0.id == id }),
              !configs[index].isDefault else { return configs }
        var values = declaredValues(declared)
        for (key, value) in current where values[key] != nil {
            values[key] = value
        }
        var result = configs
        result[index].values = values
        return result
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

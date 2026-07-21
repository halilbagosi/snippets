import SwiftUI

/// Dispatches a snippet's resolved sources (dependencies + entry, see
/// `SnippetLinker`) to the preview engine for its language.
/// Only shown when `language.previewKind` is non-nil.
struct SnippetPreviewView: View {
    let resolution: SnippetLinker.Resolution
    let language: SupportedLanguage
    let theme: Theme

    @Binding var paramOverrides: [String: PreviewParamValue]

    private var entryCode: String { resolution.sources.last?.code ?? "" }
    private var helperCodes: [String] { resolution.sources.dropLast().map(\.code) }

    var body: some View {
        switch language.previewKind {
        case .web(let flavor):
            webPreview(flavor: flavor)
        case .metal:
            metalPreview
        case .swiftUI:
            SwiftPreviewHostView(entry: entryCode, helpers: helperCodes, theme: theme)
        case nil:
            PreviewUnavailableView(message: "No live preview for \(language.rawValue).", theme: theme)
        }
    }

    /// Previews with detectable parameters get a control bar: React props
    /// re-render the component in place (ReactBits-style); GLSL uniforms
    /// apply on the next frame.
    @ViewBuilder
    private func webPreview(flavor: WebPreviewFlavor) -> some View {
        let params = PreviewParamDetector.detect(for: language, resolution: resolution).map(\.param)
        if params.isEmpty {
            WebPreviewView(sources: resolution.sources, flavor: flavor, theme: theme)
        } else {
            VStack(spacing: 0) {
                WebPreviewView(
                    sources: resolution.sources, flavor: flavor, theme: theme,
                    propOverrides: paramOverrides
                )
                Divider()
                PreviewParamControls(params: params, overrides: $paramOverrides, theme: theme)
            }
            .onChange(of: entryCode) { paramOverrides = [:] }
        }
    }

    /// Metal previews with a `SnippetParams` struct get the same control
    /// bar; values are packed into fragment buffer(1) every frame.
    @ViewBuilder
    private var metalPreview: some View {
        let params = PreviewParamDetector.detect(for: language, resolution: resolution).map(\.param)
        if params.isEmpty {
            MetalShaderPreviewView(entry: entryCode, helpers: helperCodes, theme: theme)
        } else {
            VStack(spacing: 0) {
                MetalShaderPreviewView(
                    entry: entryCode, helpers: helperCodes, theme: theme,
                    params: params, paramValues: paramOverrides
                )
                Divider()
                PreviewParamControls(params: params, overrides: $paramOverrides, theme: theme)
            }
            .onChange(of: entryCode) { paramOverrides = [:] }
        }
    }
}

/// Native controls for a preview's tweakable parameters.
struct PreviewParamControls: View {
    let params: [PreviewParam]
    @Binding var overrides: [String: PreviewParamValue]
    let theme: Theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(params) { param in
                    control(for: param)
                }
                if !overrides.isEmpty {
                    Button("reset") { overrides = [:] }
                        .buttonStyle(.plain)
                        .font(Mono.font(size: 10, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(theme.surface.opacity(0.6))
    }

    @ViewBuilder
    private func control(for param: PreviewParam) -> some View {
        switch param.kind {
        case .number(let fallback):
            HStack(spacing: 6) {
                label(param.name)
                Slider(value: numberBinding(param.name, fallback: fallback), in: sliderRange(around: fallback))
                    .controlSize(.mini)
                    .frame(width: 90)
                Text(formatted(numberBinding(param.name, fallback: fallback).wrappedValue))
                    .font(Mono.font(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .frame(minWidth: 30, alignment: .leading)
            }
        case .integer(let fallback):
            HStack(spacing: 6) {
                label(param.name)
                Slider(
                    value: numberBinding(param.name, fallback: Double(fallback)),
                    in: sliderRange(around: Double(max(fallback, 1))),
                    step: 1
                )
                .controlSize(.mini)
                .frame(width: 90)
                Text(String(Int(numberBinding(param.name, fallback: Double(fallback)).wrappedValue.rounded())))
                    .font(Mono.font(size: 10))
                    .foregroundStyle(theme.textMuted)
                    .frame(minWidth: 30, alignment: .leading)
            }
        case .boolean(let fallback):
            Toggle(isOn: booleanBinding(param.name, fallback: fallback)) { label(param.name) }
                .toggleStyle(.switch)
                .controlSize(.mini)
        case .choice(let fallback, let options):
            HStack(spacing: 6) {
                label(param.name)
                Picker("", selection: textBinding(param.name, fallback: fallback)) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .font(Mono.font(size: 10))
            }
        case .color(let fallback):
            HStack(spacing: 6) {
                label(param.name)
                ColorPicker("", selection: colorBinding(param.name, fallbackHex: fallback), supportsOpacity: false)
                    .labelsHidden()
                    .controlSize(.small)
            }
        case .text(let fallback):
            HStack(spacing: 6) {
                label(param.name)
                TextField("", text: textBinding(param.name, fallback: fallback))
                    .textFieldStyle(.roundedBorder)
                    .font(Mono.font(size: 10))
                    .frame(width: 110)
            }
        }
    }

    private func label(_ name: String) -> some View {
        Text(name)
            .font(Mono.font(size: 10, weight: .semibold))
            .foregroundStyle(theme.textMuted)
    }

    /// 0-anchored range comfortably around the default so sliders are useful
    /// without per-param metadata: 1.4 → 0…2.8, 40 → 0…80, 0 → 0…1.
    private func sliderRange(around fallback: Double) -> ClosedRange<Double> {
        let magnitude = max(abs(fallback) * 2, 1)
        return fallback < 0 ? -magnitude...magnitude : 0...magnitude
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.2f", value)
    }

    private func numberBinding(_ name: String, fallback: Double) -> Binding<Double> {
        Binding {
            if case .number(let value) = overrides[name] { return value }
            return fallback
        } set: { overrides[name] = .number($0) }
    }

    private func booleanBinding(_ name: String, fallback: Bool) -> Binding<Bool> {
        Binding {
            if case .boolean(let value) = overrides[name] { return value }
            return fallback
        } set: { overrides[name] = .boolean($0) }
    }

    private func textBinding(_ name: String, fallback: String) -> Binding<String> {
        Binding {
            if case .string(let value) = overrides[name] { return value }
            return fallback
        } set: { overrides[name] = .string($0) }
    }

    private func colorBinding(_ name: String, fallbackHex: String) -> Binding<Color> {
        Binding {
            if case .string(let value) = overrides[name] { return Color(previewHex: value) }
            return Color(previewHex: fallbackHex)
        } set: { overrides[name] = .string($0.hexString(fallback: fallbackHex)) }
    }
}

private extension Color {
    /// #RGB / #RRGGBB parser for preview parameter defaults.
    init(previewHex hex: String) {
        var digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, let value = UInt64(digits, radix: 16) else {
            self = .white
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

/// Shared empty/error state used by the preview engines.
struct PreviewUnavailableView: View {
    let message: String
    let theme: Theme

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(theme.textMuted)
            Text(message)
                .font(Mono.font(size: 12))
                .foregroundStyle(theme.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSToken.Spacing.md)
    }
}

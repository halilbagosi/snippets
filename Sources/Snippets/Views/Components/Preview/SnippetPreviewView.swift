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

    /// Just the live preview surface. The parameter controls that drive
    /// `paramOverrides` live in a separate panel below this one (see
    /// `SnippetDetailView.paramControlsPanel`), so expanding them grows the
    /// column downward instead of squeezing the preview inside a fixed frame.
    /// Overrides still flow in here to render live: empty when the snippet has
    /// no params, which renders identically to passing none.
    @ViewBuilder
    private func webPreview(flavor: WebPreviewFlavor) -> some View {
        WebPreviewView(
            sources: resolution.sources, flavor: flavor, theme: theme,
            propOverrides: paramOverrides
        )
    }

    /// Metal previews pack `paramOverrides` into fragment buffer(1) every
    /// frame; `params` defines the buffer layout and is empty for shaders
    /// without a `SnippetParams` struct.
    @ViewBuilder
    private var metalPreview: some View {
        let params = PreviewParamDetector.detect(for: language, resolution: resolution).map(\.param)
        MetalShaderPreviewView(
            entry: entryCode, helpers: helperCodes, theme: theme,
            params: params, paramValues: paramOverrides
        )
    }
}

/// Native controls for a preview's tweakable parameters.
struct PreviewParamControls: View {
    let params: [PreviewParam]
    @Binding var overrides: [String: PreviewParamValue]
    let theme: Theme

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                // An adaptive grid wraps to as many rows as it needs, so every
                // parameter is visible at once — a horizontal strip hid all but
                // the first few behind a scroll.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190), spacing: 16, alignment: .topLeading)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(params) { param in
                        control(for: param)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .background(theme.surface.opacity(0.6))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(Mono.font(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("parameters")
                        .font(Mono.font(size: 10, weight: .semibold))
                    Text("\(params.count)")
                        .font(Mono.font(size: 10))
                        .foregroundStyle(theme.textMuted.opacity(0.7))
                }
                .foregroundStyle(theme.textMuted)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

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

    /// One grid cell: name above, control below, so every cell is the same
    /// shape regardless of which control it holds.
    private func cell<Content: View>(
        _ name: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(name)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func control(for param: PreviewParam) -> some View {
        switch param.kind {
        case .number(let fallback):
            cell(param.name) {
                HStack(spacing: 6) {
                    Slider(value: numberBinding(param.name, fallback: fallback), in: sliderRange(around: fallback))
                        .controlSize(.mini)
                    Text(formatted(numberBinding(param.name, fallback: fallback).wrappedValue))
                        .font(Mono.font(size: 10))
                        .foregroundStyle(theme.textMuted)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
        case .integer(let fallback):
            cell(param.name) {
                HStack(spacing: 6) {
                    Slider(
                        value: numberBinding(param.name, fallback: Double(fallback)),
                        in: sliderRange(around: Double(max(fallback, 1))),
                        step: 1
                    )
                    .controlSize(.mini)
                    Text(String(Int(numberBinding(param.name, fallback: Double(fallback)).wrappedValue.rounded())))
                        .font(Mono.font(size: 10))
                        .foregroundStyle(theme.textMuted)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            }
        case .boolean(let fallback):
            cell(param.name) {
                Toggle("", isOn: booleanBinding(param.name, fallback: fallback))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .choice(let fallback, let options):
            cell(param.name) {
                Picker("", selection: textBinding(param.name, fallback: fallback)) {
                    ForEach(options, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .font(Mono.font(size: 10))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .color(let fallback):
            cell(param.name) {
                ColorPicker("", selection: colorBinding(param.name, fallbackHex: fallback), supportsOpacity: false)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .text(let fallback):
            cell(param.name) {
                TextField("", text: textBinding(param.name, fallback: fallback))
                    .textFieldStyle(.roundedBorder)
                    .font(Mono.font(size: 10))
                    .frame(maxWidth: .infinity)
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

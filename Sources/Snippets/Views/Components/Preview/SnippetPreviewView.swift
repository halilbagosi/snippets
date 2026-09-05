import SwiftUI

/// Dispatches a snippet's resolved sources (dependencies + entry, see
/// `SnippetLinker`) to the preview engine for its language.
/// Only shown when `language.previewKind` is non-nil.
struct SnippetPreviewView: View {
    let resolution: SnippetLinker.Resolution
    let language: SupportedLanguage
    let theme: Theme
    /// Parameters the previewed source declares, detected once by the owning
    /// view. Deriving them here instead would re-run the detector on every
    /// override change — i.e. every frame of a slider drag.
    let params: [PreviewParam]
    /// Identifies the snippet for trust decisions (run approval, CDN grants).
    /// Nil only for snippets predating the uuid backfill, which are treated as
    /// ungranted — the conservative direction.
    var snippetID: UUID? = nil

    @Binding var paramOverrides: [String: PreviewParamValue]

    @Environment(PreviewTrust.self) private var trust

    private var entryCode: String { resolution.sources.last?.code ?? "" }
    private var helperCodes: [String] { resolution.sources.dropLast().map(\.code) }

    var body: some View {
        switch language.previewKind {
        case .web(let flavor):
            gated { webPreview(flavor: flavor) }
        case .metal:
            gated { metalPreview }
        case .swiftUI:
            // The Swift flavor keeps its own Run gate unconditionally: it
            // compiles and loads native code into this process, so it is the
            // one engine that must stay explicit even with auto-run enabled.
            SwiftPreviewHostView(entry: entryCode, helpers: helperCodes, theme: theme)
        case nil:
            PreviewUnavailableView(message: "No live preview for \(language.rawValue).", theme: theme)
        }
    }

    /// Wraps a preview engine in the consent layer: nothing executes until
    /// auto-run is on or the user has pressed Run for this snippet.
    @ViewBuilder
    private func gated<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if trust.mayRun(snippetID) {
            VStack(spacing: 0) {
                if !pendingCDNSpecifiers.isEmpty { cdnBanner }
                content()
            }
        } else {
            runPrompt
        }
    }

    private var runPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(theme.accent)
            Text("Runs this snippet's code to render the preview.")
                .font(Mono.font(size: 11))
                .foregroundStyle(theme.textMuted)
            FilterTag(label: "run", icon: "play.fill", accent: theme.accent, isSelected: true) {
                trust.approveRun(snippetID)
            }
            Text("Always run previews automatically in Settings → Preferences.")
                .font(Mono.font(size: 10))
                .foregroundStyle(theme.textMuted.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DSToken.Spacing.md)
    }

    /// npm packages this snippet wants from esm.sh, if it has not been granted
    /// them. Non-empty only for React entries — no other flavor resolves npm
    /// specifiers, so no other flavor can prompt.
    private var pendingCDNSpecifiers: [String] {
        guard case .web(let flavor) = language.previewKind, flavor == .react,
              !trust.allowsCDNModules(snippetID) else { return [] }
        return WebPreviewHTMLBuilder.cdnSpecifiers(
            linked: resolution.sources, entryFlavor: flavor
        )
    }

    /// The one place a preview can ask to reach the network. Deliberately a
    /// visible bar rather than a silent capability: allowing it both runs
    /// third-party code and opens the only channel by which snippet code can
    /// send anything out.
    private var cdnBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .font(Mono.font(size: 10, weight: .semibold))
            Text("Imports \(pendingCDNSpecifiers.joined(separator: ", ")) from esm.sh")
                .font(Mono.font(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("allow") {
                trust.setCDNModulesAllowed(true, for: snippetID)
            }
            .buttonStyle(.plain)
            .font(Mono.font(size: 10, weight: .semibold))
            .foregroundStyle(theme.accent)
        }
        .foregroundStyle(theme.textMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(theme.surface.opacity(0.6))
    }

    /// Just the live preview surface. The parameter controls that drive
    /// `paramOverrides` live in a separate panel below this one (see
    /// `SnippetDetailView.paramControlsPanel`), so expanding them grows the
    /// column downward instead of squeezing the preview inside a fixed frame.
    /// Overrides still flow in here to render live: empty when the snippet has
    /// no params, which renders identically to passing none.
    @ViewBuilder
    private func webPreview(flavor: WebPreviewFlavor) -> some View {
        WebPreviewSurface(
            sources: resolution.sources, flavor: flavor, theme: theme,
            propOverrides: paramOverrides,
            policy: trust.policy(for: snippetID)
        )
    }

    /// Metal previews pack `paramOverrides` into fragment buffer(1) every
    /// frame; `params` defines the buffer layout and is empty for shaders
    /// without a `SnippetParams` struct.
    @ViewBuilder
    private var metalPreview: some View {
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

    // The whole strip is the toggle — a 10pt label and a 9pt chevron make far
    // too small a hit target, and the empty space beside them reads as part of
    // the same control. "reset" is a nested button, so it swallows its own taps.
    private var header: some View {
        HStack(spacing: 6) {
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
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(DSToken.Motion.reveal) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Parameters")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
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

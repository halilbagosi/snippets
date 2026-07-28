import SwiftUI

/// Appearance pane in the Settings window.
/// Controls colour scheme, focused mode, hover effects, and theme accent colour.
struct AppearanceView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    /// Preset accent colour palette.
    private static let presetColors: [(name: String, hex: String)] = [
        ("Green",  "#51C278"),
        ("Blue",   "#0A84FF"),
        ("Indigo", "#5E5CE6"),
        ("Purple", "#BF5AF2"),
        ("Pink",   "#FF375F"),
        ("Orange", "#FF9F0A"),
        ("Teal",   "#64D2FF"),
        ("Red",    "#FF453A"),
    ]

    private enum SchemeOption: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: return "System"
            case .light: return "Light"
            case .dark: return "Dark"
            }
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            schemeCard
            behaviorCard
            accentCard
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSToken.Spacing.md)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            shadowRadius: 12,
            shadowY: 6
        )
    }

    // MARK: - Color Scheme

    private var schemeCard: some View {
        glassCard {
            sectionLabel("Appearance")

            HStack(spacing: 18) {
                Spacer(minLength: 0)
                ForEach(SchemeOption.allCases) { option in
                    schemeTile(option)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func schemeTile(_ option: SchemeOption) -> some View {
        let isSelected = appearanceSettings.preferredColorScheme == option.rawValue
        return Button {
            withAnimation(DSToken.Motion.toggle) {
                appearanceSettings.preferredColorScheme = option.rawValue
            }
        } label: {
            VStack(spacing: 8) {
                schemePreview(option)
                    .frame(width: 104, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isSelected ? accent : theme.border,
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
                    .shadow(
                        color: .black.opacity(isSelected ? 0.18 : 0.08),
                        radius: isSelected ? 8 : 4,
                        y: 3
                    )
                    .scaleEffect(isSelected ? 1.0 : 0.97)

                Text(option.label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color scheme: \(option.label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func schemePreview(_ option: SchemeOption) -> some View {
        switch option {
        case .light:
            miniWindow(dark: false)
        case .dark:
            miniWindow(dark: true)
        case .system:
            ZStack {
                miniWindow(dark: false)
                miniWindow(dark: true)
                    .mask(TrailingDiagonalHalf())
            }
        }
    }

    /// A miniature mock of the app window — canvas, traffic lights, and one
    /// snippet card — mirroring the System Settings appearance-tile idiom.
    private func miniWindow(dark: Bool) -> some View {
        let t = Theme.current(dark ? .dark : .light)
        return ZStack {
            t.canvas
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2.5) {
                    Circle().fill(t.trafficRed).frame(width: 4, height: 4)
                    Circle().fill(t.trafficYellow).frame(width: 4, height: 4)
                    Circle().fill(t.trafficGreen).frame(width: 4, height: 4)
                    Spacer(minLength: 0)
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(t.surface)
                    .overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 3) {
                            Capsule().fill(accent.opacity(0.9)).frame(width: 20, height: 3.5)
                            Capsule().fill(t.textFaint.opacity(0.55)).frame(width: 34, height: 2.5)
                            Capsule().fill(t.textFaint.opacity(0.35)).frame(width: 26, height: 2.5)
                        }
                        .padding(6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(t.border, lineWidth: 0.5)
                    }
            }
            .padding(7)
        }
    }

    // MARK: - Behavior

    private var behaviorCard: some View {
        @Bindable var settings = appearanceSettings

        return glassCard {
            sectionLabel("Behavior")

            behaviorRow(
                icon: "scope",
                title: "Focused Mode",
                caption: "Hide the animated color gradient behind the gallery",
                isOn: $settings.focusedMode
            )

            Divider().opacity(0.5)

            behaviorRow(
                icon: "cursorarrow.motionlines",
                title: "Disable Hover Effects",
                caption: "Turn off hover animations on snippet cards",
                isOn: $settings.disableHoverEffects
            )

            Divider().opacity(0.5)

            behaviorRow(
                icon: "exclamationmark.triangle",
                title: "Confirm Snippet Deletion",
                caption: "Show a confirmation dialogue when deleting a snippet",
                isOn: $settings.confirmSnippetDeletion
            )

            Divider().opacity(0.5)

            behaviorPickerRow(
                icon: "folder.badge.minus",
                title: "Collection Deletion Behavior",
                caption: "What to delete when deleting a collection",
                selection: $settings.collectionDeletionBehavior
            )
        }
    }

    private func behaviorPickerRow(icon: String, title: String, caption: String, selection: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.safeAccentText(accent))
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    tint: accent.opacity(0.12),
                    shadowRadius: 3,
                    shadowY: 1
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 12)

            Picker("", selection: selection) {
                Text("Ask every time").tag("ask")
                Text("Delete Collection only").tag("collectionOnly")
                Text("Delete Collection & contents").tag("collectionAndContents")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 180)
            .tint(accent)
        }
    }

    private func behaviorRow(icon: String, title: String, caption: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.safeAccentText(accent))
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous),
                    tint: accent.opacity(0.12),
                    shadowRadius: 3,
                    shadowY: 1
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(caption)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
            }

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(accent)
        }
    }

    // MARK: - Accent Color

    private var accentCard: some View {
        glassCard {
            sectionLabel("Accent Color")

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                ForEach(Self.presetColors, id: \.hex) { preset in
                    presetSwatch(preset)
                }
                customColorWell
                Spacer(minLength: 0)
            }
        }
    }

    private func presetSwatch(_ preset: (name: String, hex: String)) -> some View {
        let swatchColor = Color(hex: preset.hex) ?? theme.accent
        let isActive = appearanceSettings.themeColorHex.lowercased() == preset.hex.lowercased()
        return Button {
            withAnimation(DSToken.Motion.toggle) {
                appearanceSettings.themeColorHex = preset.hex
            }
        } label: {
            ZStack {
                Circle()
                    .fill(swatchColor.opacity(0.35))
                    .frame(width: 38, height: 38)
                    .blur(radius: 6)
                    .opacity(isActive ? 1 : 0)

                Circle()
                    .fill(swatchColor)
                    .frame(width: 28, height: 28)

                Circle()
                    .strokeBorder(.white, lineWidth: 2.5)
                    .frame(width: 28, height: 28)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(width: 38, height: 38)
            .scaleEffect(isActive ? 1.08 : 1.0)
            .animation(DSToken.Motion.toggle, value: isActive)
        }
        .buttonStyle(.plain)
        .help(preset.name)
        .accessibilityLabel("Theme color: \(preset.name)")
    }

    /// Custom colour affordance — same rainbow-ring recipe as the Collection
    /// editor's colour strip. Shows the current colour when a custom (non-
    /// preset) accent is active.
    private var customColorWell: some View {
        @Bindable var settings = appearanceSettings
        let isCustomActive = !Self.presetColors.contains {
            $0.hex.lowercased() == settings.themeColorHex.lowercased()
        }

        return ZStack {
            Circle()
                .fill(accent.opacity(0.35))
                .frame(width: 38, height: 38)
                .blur(radius: 6)
                .opacity(isCustomActive ? 1 : 0)

            ColorPicker("", selection: Binding(
                get: { settings.themeColor },
                set: { newColor in
                    settings.themeColorHex = newColor.hexString(fallback: "#51C278")
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 28, height: 28)
            .clipShape(Circle())
            .overlay {
                ZStack {
                    Circle().fill(theme.surface)
                    if isCustomActive {
                        Circle().fill(accent)
                        Circle().strokeBorder(.white, lineWidth: 2.5)
                    } else {
                        Circle().fill(accent.opacity(0.15))
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(colorScheme == .dark ? .white : .black)
                    }
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                center: .center
                            ),
                            lineWidth: 2.0
                        )
                }
                .frame(width: 28, height: 28)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 38, height: 38)
        .scaleEffect(isCustomActive ? 1.08 : 1.0)
        .animation(DSToken.Motion.toggle, value: isCustomActive)
        .help("Custom color")
        .accessibilityLabel("Custom theme color")
    }
}

/// Right-leaning diagonal half used by the "System" scheme tile
/// (light on the left, dark on the right).
private struct TrailingDiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

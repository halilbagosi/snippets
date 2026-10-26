import SwiftUI

/// System / Light / Dark as three miniature windows. Shared by the
/// Appearance tab and the welcome tour, so both pick the same way.
struct ColorSchemePicker: View {
    /// The miniature window's size; the tour draws them smaller.
    var tileSize = CGSize(width: 104, height: 68)
    var spacing: CGFloat = 18

    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    enum Option: String, CaseIterable, Identifiable {
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
        HStack(spacing: spacing) {
            ForEach(Option.allCases) { option in
                tile(option)
            }
        }
    }

    private func tile(_ option: Option) -> some View {
        let isSelected = appearanceSettings.preferredColorScheme == option.rawValue
        return Button {
            withAnimation(DSToken.Motion.toggle) {
                appearanceSettings.preferredColorScheme = option.rawValue
            }
        } label: {
            VStack(spacing: 8) {
                preview(option)
                    .frame(width: tileSize.width, height: tileSize.height)
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
    private func preview(_ option: Option) -> some View {
        switch option {
        case .light:
            miniWindow(dark: false)
        case .dark:
            miniWindow(dark: true)
        case .system:
            // Each window only where it shows. With the whole light window
            // under the dark half, the light one's anti-aliased edges showed
            // through the dark half's as a thin white rim in dark mode. The
            // light half reaches a point past the diagonal so the seam is
            // covered by the dark half rather than left open.
            ZStack {
                miniWindow(dark: false)
                    .mask(DiagonalHalf(side: .leading, overlap: 1))
                miniWindow(dark: true)
                    .mask(DiagonalHalf(side: .trailing))
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
}

/// One side of the "System" scheme tile's right-leaning diagonal (light on
/// the left, dark on the right). `overlap` moves the edge that far into the
/// other side.
private struct DiagonalHalf: Shape {
    enum Side { case leading, trailing }

    var side: Side
    var overlap: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let shift = side == .leading ? overlap : -overlap
        let top = CGPoint(x: rect.minX + rect.width * 0.62 + shift, y: rect.minY)
        let bottom = CGPoint(x: rect.minX + rect.width * 0.38 + shift, y: rect.maxY)
        var path = Path()
        switch side {
        case .leading:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: top)
            path.addLine(to: bottom)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .trailing:
            path.move(to: top)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: bottom)
        }
        path.closeSubpath()
        return path
    }
}

/// The preset accent swatches, plus a colour well for anything else.
/// Shared by the Appearance tab and the welcome tour.
struct AccentColorPicker: View {
    var spacing: CGFloat = 10

    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(AppearanceView.presetColors, id: \.hex) { preset in
                presetSwatch(preset)
            }
            customColorWell
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
        let isCustomActive = !AppearanceView.presetColors.contains {
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
                    settings.themeColorHex = newColor.hexString(fallback: AppearanceSettings.defaultThemeColorHex)
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

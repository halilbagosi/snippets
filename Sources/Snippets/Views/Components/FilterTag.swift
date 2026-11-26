import SwiftUI

struct FilterTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let icon: String
    let accent: Color
    var foregroundAccent: Color? = nil
    var selectedFillAccent: Color? = nil
    let isSelected: Bool
    /// Text whose width the label always takes, so a label that changes
    /// (`collections:none` ↔ `collections:all`) never resizes the chip and
    /// shifts its neighbours.
    var reservedLabel: String? = nil
    let action: () -> Void

    private var theme: Theme { Theme.current(colorScheme) }

    private var resolvedForeground: Color {
        if isSelected {
            return colorScheme == .dark ? .white : (foregroundAccent ?? theme.safeAccentText(accent))
        }
        if let foregroundAccent { return foregroundAccent }
        if colorScheme == .dark { 
            return .primary.opacity(0.85)
        }
        return theme.safeAccentText(accent)
    }

    private var resolvedFill: Color {
        if isSelected {
            if let fill = selectedFillAccent {
                return fill
            }
            if colorScheme == .light {
                return foregroundAccent ?? accent
            }
            return accent
        }
        return accent.opacity(0.18)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(Mono.font(size: 10, weight: .semibold))
                // The hidden reserved text sizes the ZStack; the real label
                // sits on its leading edge.
                ZStack(alignment: .leading) {
                    if let reservedLabel {
                        Text(reservedLabel).hidden()
                    }
                    Text(label)
                }
                .font(Mono.font(size: 11, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .foregroundStyle(resolvedForeground)
            // No fill under the glass: like a rim, it is a static layer that
            // doesn't follow the glass as it morphs. The glass tint alone
            // carries the selected state.
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 7, style: .continuous),
                interactive: true,
                // No rim and no fills: SwiftUI draws those on the static
                // frame, so they stay put while the glass morphs under them.
                // All colour comes from tinting the glass itself.
                borderOpacity: 0,
                shadowRadius: 0,
                shadowY: 0,
                glassTint: isSelected
                    ? resolvedFill.opacity(colorScheme == .dark ? 0.6 : 0.5)
                    : accent.opacity(colorScheme == .dark ? 0.14 : 0.08),
                drawsFills: false
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(FilterTagButtonStyle(isSelected: isSelected, accent: selectedFillAccent ?? accent))
        .animation(DSToken.Motion.selection, value: isSelected)
    }
}

/// The gallery chips' press: a quick 0.95 squeeze on `DSToken.Motion.press`.
/// Glass buttons elsewhere use it so every button gives the same feel.
struct GlassPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DSToken.Motion.press, value: configuration.isPressed)
    }
}

private struct FilterTagButtonStyle: ButtonStyle {
    let isSelected: Bool
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .shadow(color: isSelected || configuration.isPressed ? accent.opacity(0.40) : .clear, radius: 8, x: 0, y: 0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(DSToken.Motion.press, value: configuration.isPressed)
    }
}

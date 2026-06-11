import SwiftUI

struct FilterTag: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let icon: String
    let accent: Color
    var foregroundAccent: Color? = nil
    var selectedFillAccent: Color? = nil
    let isSelected: Bool
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
                Text(label)
                    .font(Mono.font(size: 11, weight: .semibold))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(resolvedForeground)
            .background {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(resolvedFill.opacity(isSelected ? (colorScheme == .dark ? 0.35 : 0.12) : (colorScheme == .dark ? 0.15 : 0.03)))
            }
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: 7, style: .continuous),
                tint: resolvedFill,
                interactive: true,
                borderOpacity: isSelected ? 0.44 : (colorScheme == .dark ? 0.30 : 0.38),
                shadowRadius: colorScheme == .dark ? 8 : 0,
                shadowY: colorScheme == .dark ? 4 : 0
            )
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(accent.opacity(isSelected ? 0.50 : (colorScheme == .dark ? 0.28 : 0.30)), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .shadow(
            color: colorScheme == .dark ? accent.opacity(isSelected ? 0.45 : 0.22) : .clear,
            radius: isSelected ? 10 : 6,
            x: 0,
            y: isSelected ? 3 : 2
        )
        .animation(.snappy(duration: 0.12), value: isSelected)
    }
}

#Preview("FilterTag") {
    HStack {
        FilterTag(label: "Swift", icon: "swift", accent: .orange, isSelected: false, action: {})
        FilterTag(label: "Selected", icon: "checkmark", accent: .green, isSelected: true, action: {})
    }
    .padding()
}

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct LanguageBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let language: SupportedLanguage
    var compact: Bool = false

    private var baseAccent: Color { Color(hex: language.accentHex) ?? Theme.current(colorScheme).accent }
    private var accent: Color { baseAccent.saturation(3.0).brightness(0.22) }
    private var selectedFillAccent: Color {
        (Color(hex: language.accentHexSelectedFill) ?? accent)
            .saturation(2.5)
            .brightness(0.15)
    }
    
    private var foregroundAccent: Color {
        colorScheme == .dark ? accent : accent.blended(with: .black, ratio: 0.18)
    }

    private var resolvedForeground: Color {
        colorScheme == .dark ? .white : foregroundAccent
    }

    private var resolvedFill: Color {
        selectedFillAccent
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        HStack(spacing: 5) {
            Image(systemName: language.symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(Mono.font(size: compact ? 9 : 10, weight: .semibold))
            Text(language.rawValue.lowercased())
                .font(Mono.font(size: compact ? 10 : 11, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .foregroundStyle(resolvedForeground)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(resolvedFill.opacity(colorScheme == .dark ? 0.20 : 0.12))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(accent.opacity(0.50), lineWidth: 1)
                }
        }
        .accessibilityLabel(language.rawValue)
        .compositingGroup()
        .opacity(theme.scheme == .dark ? 1 : 1)
    }
}

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix("#") { clean.removeFirst() }
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        self = Color(red: r, green: g, blue: b)
    }

    func hexString(fallback: String = "#0A84FF") -> String {
        #if canImport(AppKit)
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return fallback }
        let red = Int(round(max(0, min(color.redComponent, 1)) * 255))
        let green = Int(round(max(0, min(color.greenComponent, 1)) * 255))
        let blue = Int(round(max(0, min(color.blueComponent, 1)) * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
        #else
        return fallback
        #endif
    }

    func blended(with other: Color, ratio: Double) -> Color {
        #if canImport(AppKit)
        guard
            let base = NSColor(self).usingColorSpace(.sRGB),
            let target = NSColor(other).usingColorSpace(.sRGB)
        else { return self }

        let amount = max(0, min(ratio, 1))
        let inverse = 1 - amount
        return Color(
            red: Double(base.redComponent * inverse + target.redComponent * amount),
            green: Double(base.greenComponent * inverse + target.greenComponent * amount),
            blue: Double(base.blueComponent * inverse + target.blueComponent * amount),
            opacity: Double(base.alphaComponent * inverse + target.alphaComponent * amount)
        )
        #else
        return self
        #endif
    }
}

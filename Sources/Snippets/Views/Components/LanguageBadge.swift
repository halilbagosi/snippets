import SwiftUI

struct LanguageBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let language: SupportedLanguage
    var compact: Bool = false

    private var accent: Color { Color(hex: language.accentHex) ?? .accentColor }

    var body: some View {
        let theme = Theme.current(colorScheme)
        HStack(spacing: 5) {
            Image(systemName: language.symbolName)
                .font(Mono.font(size: compact ? 9 : 10, weight: .semibold))
            Text(language.rawValue.lowercased())
                .font(Mono.font(size: compact ? 10 : 11, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 3 : 4)
        .foregroundStyle(accent)
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.16 : 0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(accent.opacity(0.32), lineWidth: 1)
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
}

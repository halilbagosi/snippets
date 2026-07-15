import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct CollectionIconView: View {
    let iconName: String
    let color: Color
    var size: CGFloat = 18
    var isSelected: Bool = false

    private var resolvedIconName: String {
        SnippetCollection.validSFSymbolName(iconName)
    }

    var body: some View {
        Image(systemName: resolvedIconName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(isSelected ? 0.34 : 0.0), radius: 5, x: 0, y: 2)
        .accessibilityLabel("Collection")
    }
}

extension SnippetCollection {
    var displayColor: Color {
        let lightColor = Color(hex: colorHex) ?? Color(hex: Self.defaultColorHex) ?? .accentColor
        guard let darkHex = colorHexDark, let darkColor = Color(hex: darkHex) else {
            return lightColor
        }
        
        #if canImport(AppKit)
        let nsLight = NSColor(lightColor)
        let nsDark = NSColor(darkColor)
        let dynamicNSColor = NSColor(name: nil, dynamicProvider: { appearance in
            switch appearance.name {
            case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
                return nsDark
            default:
                return nsLight
            }
        })
        return Color(nsColor: dynamicNSColor)
        #else
        return lightColor
        #endif
    }

    var displayIconName: String {
        Self.validSFSymbolName(iconName)
    }

    static func validSFSymbolName(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultIconName }
        if trimmed == "folder" || trimmed == "folder.fill" { return defaultIconName }
        guard isValidSFSymbolName(trimmed) else { return defaultIconName }
        return trimmed
    }

    static func isValidSFSymbolName(_ rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        #if canImport(AppKit)
        return NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil
        #else
        return true
        #endif
    }
}

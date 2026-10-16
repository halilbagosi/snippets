import SwiftUI

struct Theme {
    let scheme: ColorScheme

    /// User-chosen accent colour override (set by AppearanceSettings).
    @MainActor static var userAccent: Color? = nil

    static func current(_ scheme: ColorScheme) -> Theme { Theme(scheme: scheme) }

    var canvas: Color {
        scheme == .dark
            ? Color(red: 0.055, green: 0.063, blue: 0.078)
            : Color(red: 0.961, green: 0.965, blue: 0.973)
    }
    var canvasDeep: Color {
        scheme == .dark
            ? Color(red: 0.035, green: 0.043, blue: 0.055)
            : Color(red: 0.945, green: 0.949, blue: 0.961)
    }
    var surface: Color {
        scheme == .dark ? Color(red: 0.05, green: 0.05, blue: 0.05) : .white
    }
    var surfaceElevated: Color {
        scheme == .dark
            ? Color(red: 0.110, green: 0.129, blue: 0.157)
            : Color(red: 0.973, green: 0.976, blue: 0.984)
    }
    var inset: Color {
        scheme == .dark
            ? Color(red: 0.039, green: 0.047, blue: 0.063)
            : Color(red: 0.929, green: 0.937, blue: 0.949)
    }

    var border: Color {
        scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.08)
    }
    var borderStrong: Color {
        scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.16)
    }

    var text: Color {
        scheme == .dark
            ? Color(red: 0.902, green: 0.929, blue: 0.953)
            : Color(red: 0.141, green: 0.161, blue: 0.184)
    }
    var textMuted: Color {
        scheme == .dark
            ? Color(red: 0.580, green: 0.612, blue: 0.651)
            : Color(red: 0.239, green: 0.267, blue: 0.298)
    }
    var textFaint: Color {
        scheme == .dark ? Color.white.opacity(0.30) : Color.black.opacity(0.50)
    }

    var accent: Color {
        let fallback = Color(hex: AppearanceSettings.defaultThemeColorHex)!
        return MainActor.assumeIsolated { Theme.userAccent ?? fallback }
    }
    var keyword: Color { Color(red: 1.0, green: 0.482, blue: 0.447) }
    var string: Color { Color(red: 0.949, green: 0.800, blue: 0.376) }
    var symbol: Color { Color(red: 0.475, green: 0.753, blue: 1.0) }
    var comment: Color {
        scheme == .dark
            ? Color(red: 0.435, green: 0.502, blue: 0.580)
            : Color(red: 0.494, green: 0.529, blue: 0.569)
    }

    var trafficRed: Color { Color(red: 1.00, green: 0.373, blue: 0.337) }
    var trafficYellow: Color { Color(red: 1.00, green: 0.741, blue: 0.231) }
    var trafficGreen: Color { Color(red: 0.157, green: 0.788, blue: 0.345) }

    func accentColor(for language: SupportedLanguage) -> Color {
        Color(hex: language.accentHex) ?? accent
    }

    func accentColor(for rawLanguage: String) -> Color {
        guard let language = SupportedLanguage(rawValue: rawLanguage) else { return accent }
        return accentColor(for: language)
    }

    /// The accent as a text colour. Light mode darkens it by at least 35%,
    /// and further for bright accents (yellow, teal) until it reaches 4.5:1
    /// against the light canvas.
    func safeAccentText(_ accent: Color) -> Color {
        guard scheme == .light else { return accent }
        var ratio = 0.35
        var text = accent.blended(with: .black, ratio: ratio)
        while let luminance = text.relativeLuminance,
              luminance > Self.maxLightTextLuminance, ratio < 0.9 {
            ratio += 0.05
            text = accent.blended(with: .black, ratio: ratio)
        }
        return text
    }

    /// Highest WCAG relative luminance with 4.5:1 contrast against the light
    /// canvas: (L_canvas + 0.05) / 4.5 - 0.05, with L_canvas ≈ 0.922.
    static let maxLightTextLuminance = 0.166
}

enum Mono {
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum Sans {
    static func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

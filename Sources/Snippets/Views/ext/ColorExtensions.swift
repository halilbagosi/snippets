import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension Bundle {
    static var snippetsResources: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}

extension Color {
    func saturation(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #endif
        return Color(hue: h, saturation: min(s * amount, 1.0), brightness: b, opacity: a)
    }

    func brightness(_ amount: Double) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit)
        NSColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #endif
        return Color(hue: h, saturation: s, brightness: min(b + amount, 1.0), opacity: a)
    }
}

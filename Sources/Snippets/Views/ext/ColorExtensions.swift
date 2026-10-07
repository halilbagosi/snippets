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
        return Color(hue: h, saturation: s, brightness: max(min(b + amount, 1.0), 0.0), opacity: a)
    }

    var luminance: Double {
        #if canImport(AppKit)
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return 0.5 }
        let r = Double(nsColor.redComponent)
        let g = Double(nsColor.greenComponent)
        let b = Double(nsColor.blueComponent)
        
        func adjust(_ component: Double) -> Double {
            return component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        
        return 0.2126 * adjust(r) + 0.7152 * adjust(g) + 0.0722 * adjust(b)
        #else
        return 0.5
        #endif
    }

    func contrastRatio(with other: Color) -> Double {
        let l1 = self.luminance
        let l2 = other.luminance
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}

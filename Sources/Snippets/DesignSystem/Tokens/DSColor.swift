import SwiftUI

public extension DSToken {
    struct Color {
        public static let surface = SwiftUI.Color.white.opacity(0.1)
        #if os(macOS)
        public static let background = SwiftUI.Color(NSColor.windowBackgroundColor)
        #else
        public static let background = SwiftUI.Color(UIColor.systemBackground)
        #endif
        public static let textPrimary = SwiftUI.Color.primary
        public static let textSecondary = SwiftUI.Color.secondary
        public static let tint = SwiftUI.Color.accentColor
        
        public struct LiquidGlass {
            public static func fill(isDark: Bool) -> SwiftUI.Color {
                return .white.opacity(isDark ? 0.035 : 0.16)
            }
            
            public static func border(isDark: Bool) -> SwiftUI.Color {
                return .white.opacity(isDark ? 0.18 : 0.42)
            }
            
            public static func tintFill(tint: SwiftUI.Color, isDark: Bool) -> SwiftUI.Color {
                return tint.opacity(isDark ? 0.10 : 0.07)
            }
            
            public static func shadow(isDark: Bool) -> SwiftUI.Color {
                return .black.opacity(isDark ? 0.24 : 0.10)
            }
        }
    }
}

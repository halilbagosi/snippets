import SwiftUI

public struct DSGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public let shape: S
    public let tint: Color?
    public let interactive: Bool
    public let borderOpacity: Double?
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat
    
    public init(shape: S, tint: Color? = nil, interactive: Bool = false, borderOpacity: Double? = nil, shadowRadius: CGFloat = DSToken.Shadow.liquidRadius, shadowY: CGFloat = DSToken.Shadow.liquidY) {
        self.shape = shape
        self.tint = tint
        self.interactive = interactive
        self.borderOpacity = borderOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let resolvedBorderOpacity = borderOpacity ?? (isDark ? 0.18 : 0.42)

        if #available(macOS 26.0, *) {
            // Assume glassEffect is available in this future OS version.
            // Using AnyView to bypass compile error if this modifier does not exist locally.
            // Actually, we keep it as it was in GlassCard.swift.
            decorated(
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape),
                borderOpacity: resolvedBorderOpacity,
                isDark: isDark
            )
        } else {
            decorated(
                content.background(shape.fill(.ultraThinMaterial)),
                borderOpacity: resolvedBorderOpacity,
                isDark: isDark
            )
        }
    }

    private func decorated<V: View>(_ view: V, borderOpacity: Double, isDark: Bool) -> some View {
        view
            .overlay {
                shape
                    .fill(DSToken.Color.LiquidGlass.fill(isDark: isDark))
                    .allowsHitTesting(false)
            }
            .overlay {
                if let tint {
                    shape
                        .fill(DSToken.Color.LiquidGlass.tintFill(tint: tint, isDark: isDark))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                shape
                    .stroke(.white.opacity(borderOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: (shadowRadius > 0 || shadowY > 0) ? DSToken.Color.LiquidGlass.shadow(isDark: isDark) : .clear,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }
}

public extension View {
    func liquidGlassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        borderOpacity: Double? = nil,
        shadowRadius: CGFloat = DSToken.Shadow.liquidRadius,
        shadowY: CGFloat = DSToken.Shadow.liquidY
    ) -> some View {
        modifier(
            DSGlassModifier(
                shape: shape,
                tint: tint,
                interactive: interactive,
                borderOpacity: borderOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

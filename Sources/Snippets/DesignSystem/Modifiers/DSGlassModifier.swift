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

/// Chrome-bar Liquid Glass for window-edge strips (search header, status bar).
///
/// Mirrors how Xcode and Finder render their bars: the same glass material as
/// the rest of the chrome, but with a subtle darker tint so the strip reads as
/// window chrome rather than content, separated by a hairline system divider.
public struct DSGlassBarModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public enum DividerEdge {
        case top
        case bottom
    }

    public let dividerEdge: DividerEdge?

    public init(dividerEdge: DividerEdge? = nil) {
        self.dividerEdge = dividerEdge
    }

    public func body(content: Content) -> some View {
        content
            .background {
                barSurface
                    .ignoresSafeArea()
            }
    }

    @ViewBuilder
    private var barSurface: some View {
        Group {
            if #available(macOS 26.0, *) {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular.tint(barTint), in: Rectangle())
            } else {
                Rectangle()
                    .fill(.bar)
                    .overlay {
                        Rectangle().fill(barTint)
                    }
            }
        }
        .overlay(alignment: dividerEdge == .top ? .top : .bottom) {
            if dividerEdge != nil {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
            }
        }
    }

    /// Darker tint, similar to the bottom bar in Xcode or the path bar in Finder.
    private var barTint: SwiftUI.Color {
        .black.opacity(colorScheme == .dark ? 0.34 : 0.08)
    }
}

public extension View {
    /// Darker-tinted Liquid Glass chrome bar (Xcode/Finder-style strip).
    func liquidGlassBar(divider edge: DSGlassBarModifier.DividerEdge? = nil) -> some View {
        modifier(DSGlassBarModifier(dividerEdge: edge))
    }

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

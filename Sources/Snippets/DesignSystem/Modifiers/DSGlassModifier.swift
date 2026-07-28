import SwiftUI

public struct DSGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public let shape: S
    public let tint: Color?
    public let interactive: Bool
    public let borderOpacity: Double?
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat
    public let glassID: String?
    public let glassNamespace: Namespace.ID?

    public init(shape: S, tint: Color? = nil, interactive: Bool = false, borderOpacity: Double? = nil, shadowRadius: CGFloat = DSToken.Shadow.liquidRadius, shadowY: CGFloat = DSToken.Shadow.liquidY, glassID: String? = nil, glassNamespace: Namespace.ID? = nil) {
        self.shape = shape
        self.tint = tint
        self.interactive = interactive
        self.borderOpacity = borderOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        self.glassID = glassID
        self.glassNamespace = glassNamespace
    }

    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let resolvedBorderOpacity = borderOpacity ?? (isDark ? 0.18 : 0.42)

        if #available(macOS 26.0, *) {
            // Assume glassEffect is available in this future OS version.
            // Using AnyView to bypass compile error if this modifier does not exist locally.
            // Actually, we keep it as it was in GlassCard.swift.
            decorated(
                identified(content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)),
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

    /// Give the glass a stable identity inside its `GlassEffectContainer`.
    ///
    /// Without one, a surface that is inserted or removed is a brand-new shape
    /// to the container: it re-resolves the merged glass geometry on its own
    /// schedule, while the stroke and shadow below are drawn by SwiftUI
    /// immediately. The two land on different frames and the rim shows up
    /// before the material fills it in. With an ID the container morphs the
    /// member as one piece.
    @available(macOS 26.0, *)
    @ViewBuilder
    private func identified<V: View>(_ view: V) -> some View {
        if let glassID, let glassNamespace {
            view.glassEffectID(glassID, in: glassNamespace)
        } else {
            view
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

/// Liquid Glass chrome for a panel whose *content pixels are the point* — a
/// running preview, a shader canvas, a rendered page.
///
/// `DSGlassModifier` composites its material and two full-area fills **above**
/// the content: in light mode that is `.white.opacity(0.16)` plus the tint over
/// every pixel, and the system glass backdrop paints after the content as well.
/// For chrome that is the intended look. Over a live preview it is a veil — the
/// panel reads as a washed-out bright rectangle, most obviously in the window
/// between the preview mounting and its engine's first frame, where the veil is
/// the brightest thing on screen.
///
/// This variant keeps the identical material recipe but places all of it
/// *behind* the content, so only the hairline rim and the drop shadow sit on
/// top. A preview that has started shows true pixels; one that has not shows
/// its own opaque backdrop rather than glass.
public struct DSGlassWellModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    public let shape: S
    public let tint: Color?
    public let borderOpacity: Double?
    public let shadowRadius: CGFloat
    public let shadowY: CGFloat

    public init(
        shape: S,
        tint: Color? = nil,
        borderOpacity: Double? = nil,
        shadowRadius: CGFloat = DSToken.Shadow.liquidRadius,
        shadowY: CGFloat = DSToken.Shadow.liquidY
    ) {
        self.shape = shape
        self.tint = tint
        self.borderOpacity = borderOpacity
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
    }

    public func body(content: Content) -> some View {
        let isDark = colorScheme == .dark
        let resolvedBorderOpacity = borderOpacity ?? (isDark ? 0.18 : 0.42)

        return content
            .background { material(isDark: isDark) }
            .clipShape(shape)
            .overlay {
                shape
                    .stroke(.white.opacity(resolvedBorderOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: (shadowRadius > 0 || shadowY > 0) ? DSToken.Color.LiquidGlass.shadow(isDark: isDark) : .clear,
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }

    @ViewBuilder
    private func material(isDark: Bool) -> some View {
        Group {
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
            }
        }
        .overlay {
            shape.fill(DSToken.Color.LiquidGlass.fill(isDark: isDark))
        }
        .overlay {
            if let tint {
                shape.fill(DSToken.Color.LiquidGlass.tintFill(tint: tint, isDark: isDark))
            }
        }
        .allowsHitTesting(false)
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

    /// Liquid Glass panel for live content — material strictly behind, only a
    /// hairline rim on top. Use for anything whose own pixels must be shown
    /// faithfully (previews); use `liquidGlassSurface` for chrome.
    func liquidGlassWell<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        borderOpacity: Double? = nil,
        shadowRadius: CGFloat = DSToken.Shadow.liquidRadius,
        shadowY: CGFloat = DSToken.Shadow.liquidY
    ) -> some View {
        modifier(
            DSGlassWellModifier(
                shape: shape,
                tint: tint,
                borderOpacity: borderOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    /// - Parameters:
    ///   - glassID: Identity for this surface within its enclosing
    ///     `GlassEffectContainer`. Pass one (with `glassNamespace`) whenever the
    ///     surface can be inserted or removed while the container stays on
    ///     screen, so the material and the rim appear on the same frame.
    func liquidGlassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        borderOpacity: Double? = nil,
        shadowRadius: CGFloat = DSToken.Shadow.liquidRadius,
        shadowY: CGFloat = DSToken.Shadow.liquidY,
        glassID: String? = nil,
        glassNamespace: Namespace.ID? = nil
    ) -> some View {
        modifier(
            DSGlassModifier(
                shape: shape,
                tint: tint,
                interactive: interactive,
                borderOpacity: borderOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY,
                glassID: glassID,
                glassNamespace: glassNamespace
            )
        )
    }
}

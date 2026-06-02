import SwiftUI

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 22
    var tint: Color? = nil
    var isInteractive: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .liquidGlassSurface(
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                tint: tint,
                interactive: isInteractive,
                shadowRadius: 18,
                shadowY: 12
            )
    }
}

private struct LiquidGlassSurfaceModifier<S: Shape>: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let shape: S
    let tint: Color?
    let interactive: Bool
    let borderOpacity: Double?
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        let resolvedBorderOpacity = borderOpacity ?? (colorScheme == .dark ? 0.18 : 0.42)

        content
            .glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
            .overlay {
                shape
                    .fill(.white.opacity(colorScheme == .dark ? 0.035 : 0.16))
                    .allowsHitTesting(false)
            }
            .overlay {
                if let tint {
                    shape
                        .fill(tint.opacity(colorScheme == .dark ? 0.10 : 0.07))
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                shape
                    .stroke(.white.opacity(resolvedBorderOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.24 : 0.10),
                radius: shadowRadius,
                x: 0,
                y: shadowY
            )
    }
}

extension View {
    func liquidGlassSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        borderOpacity: Double? = nil,
        shadowRadius: CGFloat = 14,
        shadowY: CGFloat = 8
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
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

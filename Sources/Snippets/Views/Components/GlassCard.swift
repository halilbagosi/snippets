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

struct LiquidGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
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

        if #available(macOS 26.0, *) {
            decorated(
                content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape),
                borderOpacity: resolvedBorderOpacity
            )
        } else {
            decorated(
                content.background(shape.fill(.ultraThinMaterial)),
                borderOpacity: resolvedBorderOpacity
            )
        }
    }

    private func decorated<V: View>(_ view: V, borderOpacity: Double) -> some View {
        view
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
                    .stroke(.white.opacity(borderOpacity), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: (shadowRadius > 0 || shadowY > 0) ? .black.opacity(colorScheme == .dark ? 0.24 : 0.10) : .clear,
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

#Preview("GlassCard") {
    ZStack {
        Color.blue.ignoresSafeArea()
        GlassCard {
            Text("Glass Card Content")
                .padding(40)
                .foregroundStyle(.white)
        }
        .padding()
    }
}

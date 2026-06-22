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

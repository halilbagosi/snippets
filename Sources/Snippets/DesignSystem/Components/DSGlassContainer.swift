import SwiftUI

public struct DSGlassContainer<Content: View>: View {
    public let spacing: CGFloat
    @ViewBuilder public var content: () -> Content

    public init(spacing: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        GlassEffectContainer(spacing: spacing) {
            content()
        }
    }
}

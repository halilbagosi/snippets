import SwiftUI

public struct DSGlassCard<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(DSToken.Spacing.md)
            .liquidGlassSurface(in: RoundedRectangle(cornerRadius: DSToken.Radius.md, style: .continuous))
    }
}

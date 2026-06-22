import SwiftUI

public struct DSIconButton: View {
    public var icon: String
    public var action: () -> Void

    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    public init(icon: String, action: @escaping () -> Void) {
        self.icon = icon
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(DSToken.Typography.body)
                .foregroundColor(DSToken.Color.textPrimary)
                .padding(DSToken.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: DSToken.Radius.md)
                        .fill(isHovered ? DSToken.Color.surface : Color.clear)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

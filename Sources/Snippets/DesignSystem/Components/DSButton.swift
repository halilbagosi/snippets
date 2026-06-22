import SwiftUI

public enum DSButtonStyle {
    case primary
    case secondary
    case ghost
    case destructive
}

public struct DSButton: View {
    public var title: String
    public var style: DSButtonStyle
    public var action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    public init(title: String, style: DSButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSToken.Typography.body)
                .padding(.horizontal, DSToken.Spacing.md)
                .padding(.vertical, DSToken.Spacing.sm)
                .frame(maxWidth: .infinity)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(DSToken.Radius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DSToken.Radius.md)
                        .stroke(borderColor, lineWidth: 1)
                )
                .opacity(isEnabled ? 1.0 : 0.5)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return DSToken.Color.primary
        case .secondary:
            return DSToken.Color.surface
        case .ghost:
            return Color.clear
        case .destructive:
            return DSToken.Color.destructive
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive:
            return Color.white
        case .secondary, .ghost:
            return DSToken.Color.primary
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary:
            return DSToken.Color.primary.opacity(0.2)
        default:
            return Color.clear
        }
    }
}

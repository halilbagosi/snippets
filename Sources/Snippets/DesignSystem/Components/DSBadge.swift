import SwiftUI

public struct DSBadge: View {
    let text: String
    let color: Color

    public init(text: String, color: Color = DSToken.Color.textPrimary) {
        self.text = text
        self.color = color
    }

    public var body: some View {
        Text(text)
            .font(DSToken.Typography.caption2)
            .padding(.horizontal, DSToken.Spacing.xs)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(DSToken.Radius.xs)
    }
}

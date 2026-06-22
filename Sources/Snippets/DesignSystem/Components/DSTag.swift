import SwiftUI

public struct DSTag: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void = {}) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSToken.Typography.caption)
                .padding(.horizontal, DSToken.Spacing.sm)
                .padding(.vertical, DSToken.Spacing.xs)
                .background(isSelected ? DSToken.Color.textPrimary : DSToken.Color.surface)
                .foregroundColor(isSelected ? DSToken.Color.background : DSToken.Color.textPrimary)
                .cornerRadius(DSToken.Radius.sm)
                .overlay(
                    RoundedRectangle(cornerRadius: DSToken.Radius.sm)
                        .stroke(isSelected ? Color.clear : DSToken.Color.textSecondary, lineWidth: 1)
                )
        }
    }
}

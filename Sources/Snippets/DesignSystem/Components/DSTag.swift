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
                .font(DSToken.Font.caption)
                .padding(.horizontal, DSToken.Spacing.s)
                .padding(.vertical, DSToken.Spacing.xs)
                .background(isSelected ? DSToken.Color.primary : DSToken.Color.surface)
                .foregroundColor(isSelected ? DSToken.Color.onPrimary : DSToken.Color.textPrimary)
                .cornerRadius(DSToken.Radius.s)
                .overlay(
                    RoundedRectangle(cornerRadius: DSToken.Radius.s)
                        .stroke(isSelected ? Color.clear : DSToken.Color.border, lineWidth: 1)
                )
        }
    }
}

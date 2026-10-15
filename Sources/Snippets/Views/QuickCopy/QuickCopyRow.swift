import SwiftUI

/// One result row: title, trailing language badge, and a confirmation state.
///
/// Single-line by design — the densest layout that still lets two same-named
/// snippets be told apart.
struct QuickCopyRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let snippet: Snippet
    let isSelected: Bool
    let isConfirming: Bool
    /// Shared with the panel so the highlight slides between rows instead of
    /// cross-fading — the motion points where the selection is heading.
    let namespace: Namespace.ID

    private var language: SupportedLanguage {
        SupportedLanguage(rawValue: snippet.language) ?? .unknown
    }

    private var displayTitle: String {
        snippet.title.isEmpty ? "Untitled" : snippet.title
    }

    var body: some View {
        HStack(spacing: DSToken.Spacing.xs) {
            Image(systemName: isConfirming ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isConfirming ? Color.green : Color.secondary)
                .frame(width: 14)
                // The token's own doc names "copy confirmations" as its use.
                .animation(DSToken.Motion.toggle, value: isConfirming)

            Text(displayTitle)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: DSToken.Spacing.xs)

            LanguageBadge(language: language, compact: true)
        }
        .padding(.horizontal, DSToken.Spacing.sm)
        .padding(.vertical, DSToken.Spacing.xxs + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: DSToken.Radius.sm, style: .continuous)
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.28 : 0.16))
                    .matchedGeometryEffect(id: "quickCopySelection", in: namespace)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(displayTitle))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

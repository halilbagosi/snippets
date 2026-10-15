import SwiftUI

struct StatusBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let segments: [Segment]
    var contentLeadingInset: CGFloat = 0

    struct Segment: Identifiable {
        let id = UUID()
        var icon: String? = nil
        var label: String
        var tint: Color? = nil
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        if let icon = segment.icon {
                            Image(systemName: icon)
                                .font(Mono.font(size: 10, weight: .semibold))
                                .foregroundStyle(foreground(for: segment, theme: theme))
                        }
                        Text(segment.label)
                            .font(Mono.font(size: 11, weight: .medium))
                            .foregroundStyle(foreground(for: segment, theme: theme))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.leading, 18 + contentLeadingInset)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
        }
        .scrollClipDisabled()
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassBar(divider: .top)
    }

    /// Tints are accent colours — a language's, a collection's — picked to
    /// read on dark glass. On light glass the pale ones (React's cyan,
    /// JavaScript's yellow) wash out at this size, so they are darkened the
    /// same way `LanguageBadge` darkens its text.
    private func foreground(for segment: Segment, theme: Theme) -> Color {
        guard let tint = segment.tint else { return theme.textMuted }
        return colorScheme == .dark ? tint : tint.blended(with: .black, ratio: 0.45)
    }
}

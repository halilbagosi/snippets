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
                                .foregroundStyle(segment.tint ?? theme.textMuted)
                        }
                        Text(segment.label)
                            .font(Mono.font(size: 11, weight: .medium))
                            .foregroundStyle(segment.tint ?? theme.textMuted)
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
}

#Preview("StatusBar") {
    StatusBar(segments: [
        StatusBar.Segment(icon: "checkmark", label: "Ready", tint: .green),
        StatusBar.Segment(label: "10 items")
    ])
}

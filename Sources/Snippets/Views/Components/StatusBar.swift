import SwiftUI

struct StatusBar: View {
    @Environment(\.colorScheme) private var colorScheme
    let segments: [Segment]

    struct Segment: Identifiable {
        let id = UUID()
        var icon: String? = nil
        var label: String
        var tint: Color? = nil
    }

    var body: some View {
        let theme = Theme.current(colorScheme)
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
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Circle().fill(theme.accent).frame(width: 7, height: 7)
                Text("ready")
                    .font(Mono.font(size: 11, weight: .medium))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(theme.surfaceElevated)
                .overlay(alignment: .top) {
                    Rectangle().fill(theme.border).frame(height: 1)
                }
        }
    }
}

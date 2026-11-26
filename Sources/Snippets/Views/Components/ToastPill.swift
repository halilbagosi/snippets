import SwiftUI

/// The one look every toast shares — deletion, move and undo toasts, rating
/// rows, "+N more" and the collapsed rating pill: a continuous capsule
/// (superellipse curvature, no corner kinks), the same height, padding and
/// mono type, on plain interactive glass with no rim, fill or shadow.
///
/// Layout is the same everywhere too: the icon leads, the message follows,
/// and actions ("Undo", "Retry", ✕) trail.
struct ToastPillModifier: ViewModifier {
    static let height: CGFloat = 36
    static let iconSize: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .font(Mono.font(size: 12, weight: .semibold))
            .padding(.horizontal, 16)
            // Min, not fixed: text that has to wrap in a narrow column grows
            // the pill instead of being cut off.
            .padding(.vertical, 7)
            .frame(minHeight: Self.height)
            .liquidGlassSurface(
                in: Capsule(style: .continuous),
                interactive: true,
                borderOpacity: 0,
                shadowRadius: 0,
                shadowY: 0,
                drawsFills: false
            )
            .contentShape(Capsule(style: .continuous))
    }
}

extension View {
    func toastPill() -> some View { modifier(ToastPillModifier()) }
}

/// A toast's leading SF Symbol, in the shared icon size.
struct ToastIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: ToastPillModifier.iconSize - 1, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: ToastPillModifier.iconSize + 2, height: ToastPillModifier.iconSize + 2)
    }
}

/// A toast's inline action ("Undo", "Retry"): accent text in the pill's type.
struct ToastActionButton: View {
    let title: String
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Mono.font(size: 12, weight: .bold))
                .foregroundStyle(accent)
        }
        .buttonStyle(GlassPressButtonStyle())
    }
}

/// A toast's trailing ✕ (dismiss, or stop a running rating).
struct ToastCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(GlassPressButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

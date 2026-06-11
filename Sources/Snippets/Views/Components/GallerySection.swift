import SwiftUI

struct GallerySection<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int
    let icon: String
    let tint: Color
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil
    @Binding var isExpanded: Bool
    var animation: Animation = .interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12)
    let content: Content

    init(
        title: String,
        count: Int,
        icon: String,
        tint: Color,
        actionIcon: String? = nil,
        action: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        animation: Animation = .interactiveSpring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.12),
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.count = count
        self.icon = icon
        self.tint = tint
        self.actionIcon = actionIcon
        self.action = action
        self._isExpanded = isExpanded
        self.animation = animation
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GallerySectionHeader(
                title: title,
                count: count,
                icon: icon,
                tint: tint,
                actionIcon: actionIcon,
                action: action,
                isExpanded: $isExpanded
            )

            CollapsibleSectionContent(isExpanded: isExpanded, animation: animation) {
                content
            }
        }
    }
}

struct GallerySectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let count: Int
    let icon: String
    let tint: Color
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil
    @Binding var isExpanded: Bool

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.96, blendDuration: 0.06)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(Sans.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 14)

                    Image(systemName: icon)
                        .font(Sans.font(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 16)

                    Text(title)
                        .font(Sans.font(size: 15, weight: .semibold))
                        .foregroundStyle(theme.text)

                    Text("\(count)")
                        .font(Mono.font(size: 11, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background {
                            Capsule(style: .continuous)
                                .fill(tint.opacity(colorScheme == .dark ? 0.16 : 0.11))
                        }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(theme.border)
                .frame(height: 1)
            
            if let actionIcon, let action {
                Button(action: action) {
                    Image(systemName: actionIcon)
                        .font(Sans.font(size: 14, weight: .semibold))
                        .foregroundStyle(theme.textMuted)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            tint: tint,
            interactive: true,
            borderOpacity: colorScheme == .dark ? 0.14 : 0.30,
            shadowRadius: 5,
            shadowY: 2
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(count), \(isExpanded ? "expanded" : "collapsed")")
        .accessibilityAddTraits(.isButton)
    }
}

struct CollapsibleSectionContent<Content: View>: View {
    let isExpanded: Bool
    let animation: Animation
    let content: Content

    @State private var measuredHeight: CGFloat = 0

    init(
        isExpanded: Bool,
        animation: Animation,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.animation = animation
        self.content = content()
    }

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: CollapsibleSectionHeightKey.self, value: proxy.size.height)
                }
            }
            .opacity(isExpanded ? 1 : 0)
            .offset(y: isExpanded ? 0 : -6)
            .frame(height: isExpanded ? measuredHeight : 0, alignment: .top)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .clipped()
            .animation(animation, value: isExpanded)
            .onPreferenceChange(CollapsibleSectionHeightKey.self) { height in
                measuredHeight = height
            }
    }
}

private struct CollapsibleSectionHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("GallerySection") {
    struct PreviewWrapper: View {
        @State private var isExpanded = true
        var body: some View {
            GallerySection(
                title: "Files",
                count: 5,
                icon: "folder",
                tint: .blue,
                isExpanded: $isExpanded
            ) {
                Text("Item 1")
                Text("Item 2")
            }
            .padding()
        }
    }
    return PreviewWrapper()
}

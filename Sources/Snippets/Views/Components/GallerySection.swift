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
    var animation: Animation = DSToken.Motion.collapse
    let content: Content

    init(
        title: String,
        count: Int,
        icon: String,
        tint: Color,
        actionIcon: String? = nil,
        action: (() -> Void)? = nil,
        isExpanded: Binding<Bool>,
        animation: Animation = DSToken.Motion.collapse,
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

            CollapsibleSectionContent(isExpanded: isExpanded) {
                content
            }
        }
        // The collapse animation has to be owned here, by the view that holds
        // the `if`. Inside `CollapsibleSectionContent` the flag is always true,
        // so an `.animation(_:value: isExpanded)` down there never fires and
        // the caller's `animation:` argument was silently ignored.
        .animation(animation, value: isExpanded)
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
                // No `withAnimation` here — the owning `GallerySection`
                // applies the caller-supplied collapse animation, so hardcoding
                // one here would override whatever the caller asked for.
                isExpanded.toggle()
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
            .frame(width: 180, alignment: .leading)

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
            } else {
                Spacer()
                    .frame(width: 20, height: 20)
            }
        }
        .frame(height: 24)
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

/// Signals to a section's descendants that the section is folding shut, so they
/// can play their own exit before the section takes them out of the hierarchy.
///
/// A `.transition` cannot do this job: when a container is removed, SwiftUI
/// applies that container's transition to the whole subtree and never consults
/// the children's, so per-child stagger is not expressible as a transition.
private struct SectionCollapsingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSectionCollapsing: Bool {
        get { self[SectionCollapsingKey.self] }
        set { self[SectionCollapsingKey.self] = newValue }
    }
}

struct CollapsibleSectionContent<Content: View>: View {
    let isExpanded: Bool
    let content: Content

    /// Stays true through the exit animation, after `isExpanded` goes false, so
    /// the cards are still on screen to animate out.
    @State private var isMounted: Bool
    @State private var unmountTask: Task<Void, Never>? = nil

    init(
        isExpanded: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.isExpanded = isExpanded
        self.content = content()
        _isMounted = State(initialValue: isExpanded)
    }

    var body: some View {
        Group {
            if isMounted {
                content
                    .environment(\.isSectionCollapsing, !isExpanded)
                    // Collapsing content is on its way out; it should not take
                    // clicks or show up in the accessibility tree meanwhile.
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
        }
        .onChange(of: isExpanded) { _, expanded in
            unmountTask?.cancel()
            guard !expanded else {
                withAnimation(DSToken.Motion.collapse) { isMounted = true }
                return
            }
            unmountTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(DSToken.Motion.staggeredExitWindow))
                guard !Task.isCancelled else { return }
                // The height has to animate on `isMounted`, not `isExpanded`:
                // by now the exit stagger has finished and the section's own
                // `.animation(_:value: isExpanded)` is long since done, so
                // without this the layout below would snap shut.
                withAnimation(DSToken.Motion.collapse) { isMounted = false }
            }
        }
        .onDisappear { unmountTask?.cancel() }
    }
}

/// Wraps one card in a collapsible section so the grid empties card by card
/// instead of the whole slab cross-fading at once.
///
/// Entry and exit share a single visibility flag, so there is one opacity gate
/// rather than two multiplying, and re-expanding mid-collapse retargets from
/// wherever the card currently is instead of restarting from zero.
///
/// `hasEntered` is supplied by the grid rather than read from an `onAppear`
/// here: inside a `LazyVGrid`, `onAppear` fires every time a cell scrolls into
/// view, which would replay the entrance on every scroll.
struct CollapsingSectionItem<Content: View>: View {
    @Environment(\.isSectionCollapsing) private var isSectionCollapsing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Position in the grid, in reading order.
    let index: Int
    /// Total items, so the exit can run in reverse.
    let count: Int
    /// Whether the gallery has played its one-time entrance.
    let hasEntered: Bool
    let content: Content

    init(index: Int, count: Int, hasEntered: Bool, @ViewBuilder content: () -> Content) {
        self.index = index
        self.count = count
        self.hasEntered = hasEntered
        self.content = content()
    }

    private var isVisible: Bool { hasEntered && !isSectionCollapsing }

    private var animation: Animation {
        guard !reduceMotion else { return DSToken.Motion.collapse }
        return isVisible
            ? DSToken.Motion.staggeredEntrance(index: index)
            // Reversed: the furthest card leaves first, so the grid empties
            // toward the header it is folding into.
            : DSToken.Motion.staggeredCollapse(index: max(count - 1 - index, 0))
    }

    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            // 0.96, never 0 — the card recedes like an object rather than
            // vanishing into nothing. Reduce Motion keeps the fade only.
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.96)
            .animation(animation, value: isVisible)
    }
}

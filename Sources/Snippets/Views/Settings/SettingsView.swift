import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Top-level settings view, displayed as the macOS Settings window.
///
/// De-chromed Liquid Glass window matching the app's modal family: transparent
/// titlebar, dot-grid backdrop, and glass-card panes instead of grouped forms.
/// App info lives in the standard About panel (Snippets ▸ About Snippets).
struct SettingsView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private static let windowWidth: CGFloat = 520
    /// The panes outgrew a window sized to its content — the last card
    /// (Debug) ended up below the bottom of the screen — so the height is the
    /// user's, down to this, with the panes scrolling. The scene opens it at
    /// `SnippetsApp.settingsDefaultHeight`.
    static let minimumHeight: CGFloat = 320
    private var accent: Color { appearanceSettings.themeColor }

    /// Whether the panes have scrolled away from the top, which is when they
    /// start sliding under the tab bar and the titlebar above it.
    @State private var isScrolled = false

    /// Reopening Settings returns to the tab it was left on, as macOS
    /// Settings windows do.
    @AppStorage("settings.selectedPane") private var pane: SettingsPane = .general

    /// The titlebar strip swallows clicks, so the tab bar sits just below it.
    private static let tabBarTop: CGFloat = 34

    var body: some View {
        DSGlassContainer(spacing: 20) {
            ZStack {
                paneScroll(pane)
                    // A new tab is a new scroll view: it starts at its top,
                    // not at the old tab's offset.
                    .id(pane)
                    .transition(Self.paneTransition(pane))
            }
        }
        .overlay(alignment: .top) {
            ScrollEdgeVeil()
                .opacity(isScrolled ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) {
            SettingsTabBar(selection: $pane, accent: accent)
                .padding(.top, Self.tabBarTop)
                .ignoresSafeArea(edges: .top)
        }
        .background {
            ZStack {
                Color.clear.ignoresSafeArea()
                DotGridBackground(gradientPalette: [accent], lightModeStrength: 0.5)
                    .opacity(colorScheme == .dark ? 0.12 : 0.10)
                    .ignoresSafeArea()
            }
        }
        // Resizable both ways: the cards stretch with the width, and the
        // panes scroll once the height is shorter than they are.
        .frame(minWidth: Self.windowWidth, maxWidth: .infinity, minHeight: Self.minimumHeight, maxHeight: .infinity)
        #if canImport(AppKit)
        .background(SettingsWindowConfigurator())
        #endif
    }

    private func paneScroll(_ pane: SettingsPane) -> some View {
        ScrollView {
            AppearanceView(pane: pane)
                .padding(.horizontal, 24)
                // Clears the titlebar strip and the tab bar below it.
                .padding(.top, 62)
                .padding(.bottom, 28)
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        // The titlebar's default edge is the hard style: a rule and a
        // flat band the panes cut off against. Soft drops both and lets
        // the panes pass under the tab bar, where the veil behind it
        // blurs and fades them.
        .scrollEdgeEffectStyle(.soft, for: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, scrolled in
            withAnimation(DSToken.Motion.hover) { isScrolled = scrolled }
        }
    }

    /// Each pane comes in from, and leaves toward, its own tab's side, so
    /// the content travels the way the selection pill does. Fixed per pane
    /// rather than per switch: a removed view keeps the transition it was
    /// last drawn with, so one that depended on the switch's direction
    /// would leave the wrong way. With the tabs in a row, a pane left of
    /// the one you pick is always on that side of it, so this never lies.
    /// No pane hosts an `NSViewRepresentable`, so fading them is safe.
    private static func paneTransition(_ pane: SettingsPane) -> AnyTransition {
        let middle = Double(SettingsPane.allCases.count - 1) / 2
        let side = Double(pane.index) < middle ? -1.0 : 1.0
        return .offset(x: side * 36).combined(with: .opacity)
    }
}

// MARK: - Tab bar

/// The Settings window's tabs: a glass capsule whose accent-tinted pill
/// slides to the selected tab. Custom rather than a segmented `Picker`,
/// which renders as a flat system control and, in a titlebar strip, never
/// sees a click.
private struct SettingsTabBar: View {
    @Binding var selection: SettingsPane
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    @State private var hovered: SettingsPane?

    private var theme: Theme { Theme.current(colorScheme) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SettingsPane.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(3)
        .liquidGlassSurface(in: Capsule(), shadowRadius: 8, shadowY: 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings tabs")
    }

    private func tabButton(_ tab: SettingsPane) -> some View {
        let isSelected = selection == tab
        let isHovered = hovered == tab && !isSelected

        return Button {
            guard !isSelected else { return }
            // Settings tabs change a few times a session, not hundreds of
            // times an hour, so they get the toggle spring rather than the
            // high-frequency selection curve: the pill and the pane settle
            // together instead of snapping.
            withAnimation(reduceMotion ? nil : DSToken.Motion.toggle) { selection = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(tab.title)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? theme.safeAccentText(accent) : isHovered ? theme.text : theme.textMuted)
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background {
                if isSelected {
                    Capsule()
                        .fill(accent.opacity(colorScheme == .dark ? 0.24 : 0.16))
                        .overlay { Capsule().strokeBorder(accent.opacity(0.38), lineWidth: 1) }
                        .shadow(color: accent.opacity(0.22), radius: 6, y: 2)
                        // One pill that slides, not two that cross-fade.
                        .matchedGeometryEffect(id: "selectedTab", in: pill)
                } else if isHovered {
                    Capsule().fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(TabPressStyle())
        .onHover { inside in
            withAnimation(DSToken.Motion.hover) {
                if inside { hovered = tab } else if hovered == tab { hovered = nil }
            }
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Presses in slightly, and lets go a little slower than it went down.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(configuration.isPressed ? DSToken.Motion.press : DSToken.Motion.release, value: configuration.isPressed)
    }
}

// MARK: - Scroll edge

/// Blurs and fades the panes as they scroll under the transparent titlebar,
/// so a card passing behind the traffic lights softens away instead of
/// colliding with them. Material for the blur, the window colour for the
/// fade, both dissolving downward.
private struct ScrollEdgeVeil: View {
    /// The titlebar strip and the tab bar, plus room for the fade to
    /// finish below them.
    private static let height: CGFloat = 92

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.45),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor).opacity(0.75), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .frame(height: Self.height)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Window Chrome

#if canImport(AppKit)
/// De-chromes the hosting Settings window — hidden title, transparent titlebar,
/// content extending under it — same treatment as the main window — and
/// makes it resizable.
///
/// SwiftUI owns this window's sizing. The scene supplies the default and
/// minimum size; setting a `contentMaxSize` or calling `setFrame` from here
/// makes it drop `.resizable` again, so nothing else is set.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeView { ChromeView() }

    func updateNSView(_ nsView: ChromeView, context: Context) {}

    @MainActor
    final class ChromeView: NSView {
        private weak var configuredWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window

            applyChrome()

            // SwiftUI reasserts some window properties on scene updates.
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(applyChrome),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
        }

        @objc private func applyChrome() {
            guard let window = configuredWindow else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            // While a tab switch has two scroll views on screen, AppKit can
            // fall back to drawing its titlebar rule over the tab bar.
            window.titlebarSeparatorStyle = .none
            window.styleMask.insert(.fullSizeContentView)
            // Settings windows come up fixed-size whatever the scene's
            // resizability says.
            window.styleMask.insert(.resizable)
        }
    }
}
#endif

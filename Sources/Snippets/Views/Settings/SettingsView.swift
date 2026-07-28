import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Top-level settings view, displayed as the macOS Settings window.
///
/// De-chromed Liquid Glass window matching the app's modal family: transparent
/// titlebar, dot-grid backdrop, a centered glass tab switcher instead of the
/// stock preferences toolbar, and glass-card panes instead of grouped forms.
struct SettingsView: View {
    @Environment(AppearanceSettings.self) private var appearanceSettings
    @Environment(\.colorScheme) private var colorScheme

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case appearance = "Preferences"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .appearance: return "gear"
            case .about: return "info.circle.fill"
            }
        }
    }

    @Namespace private var tabNamespace
    @State private var selectedTab: SettingsTab = .appearance

    /// Laid-out height of each pane's content, keyed by tab.
    ///
    /// The window height follows the *selected* pane's entry. Panes are keyed
    /// individually rather than measured through one shared container because
    /// both are on screen during the cross-fade — measuring the container would
    /// size the window to the union of the two mid-transition, so every tab
    /// switch would bulge to the taller pane before settling.
    @State private var paneHeights: [SettingsTab: CGFloat] = [:]

    /// Height of the pane currently on screen — what an as-yet-unmeasured pane
    /// falls back to. A pane reports its height one layout pass after it
    /// appears, and holding the current height across that pass is what keeps
    /// the first visit to a tab from resizing twice (estimate, then truth).
    @State private var currentPaneHeight: CGFloat = Self.estimatedPaneHeight

    /// Measured rather than assumed: the tab switcher's height depends on the
    /// rendered capsule, which follows the user's text size.
    @State private var headerHeight: CGFloat = Self.estimatedHeaderHeight

    private static let windowWidth: CGFloat = 520
    /// Stand-ins for the first frame, before anything has been measured — set
    /// to the measured height of the header and of the default (Preferences)
    /// pane, so the window opens at its real size rather than resizing once
    /// on the frame after it appears.
    private static let estimatedHeaderHeight: CGFloat = 105
    private static let estimatedPaneHeight: CGFloat = 616

    private var theme: Theme { Theme.current(colorScheme) }
    private var accent: Color { appearanceSettings.themeColor }

    /// Window height: the selected pane's content, clamped so a tall pane on a
    /// short display scrolls inside the window instead of overflowing it.
    private var windowHeight: CGFloat {
        let content = headerHeight + (paneHeights[selectedTab] ?? currentPaneHeight)
        return min(content, maxWindowHeight)
    }

    /// Height handed to the scrolling container.
    ///
    /// Stated explicitly because a greedy scroll view here is circular: it
    /// proposes its viewport height to the pane, the pane's measurement is what
    /// `windowHeight` is derived from, and the window then feeds its own
    /// height. Measured collapsing 689 → 403 → 105 (the header alone) over
    /// three tab switches.
    private var paneViewportHeight: CGFloat {
        max(windowHeight - headerHeight, 0)
    }

    private var maxWindowHeight: CGFloat {
        #if canImport(AppKit)
        if let visible = NSScreen.main?.visibleFrame.height {
            return visible - 40
        }
        #endif
        return 900
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader
                .background { HeightReader { headerHeight = $0 } }

            // Height stated, never greedy. A greedy scroll view here proposes
            // its viewport to the pane, the pane reports that back as its
            // measured height, and the window height feeds itself: it collapses
            // to the header alone (measured: 689 → 403 → 105) within three tab
            // switches.
            ScrollView {
                DSGlassContainer(spacing: 20) {
                    Group {
                        if selectedTab == .appearance {
                            pane(.appearance) { AppearanceView() }
                        } else if selectedTab == .about {
                            pane(.about) { AboutView() }
                        }
                    }
                }
            }
            .frame(height: paneViewportHeight)
        }
        .background {
            ZStack {
                Color.clear.ignoresSafeArea()
                DotGridBackground(gradientPalette: [accent], lightModeStrength: 0.5)
                    .opacity(colorScheme == .dark ? 0.12 : 0.10)
                    .ignoresSafeArea()
            }
        }
        // Fixed width — only the height is content-driven. Fixing it here
        // rather than letting the window take it from the content keeps the
        // panes out of it: their minimum widths differ by 2pt, enough to twitch
        // the window edge on every tab switch.
        .frame(width: Self.windowWidth)
        // Height *fills* the window and pins the content to the top, instead of
        // being a fixed frame SwiftUI sizes the window from. A fixed frame is
        // the obvious approach and the one that jumps: the window height and
        // the content height are applied on different frames, and for the ones
        // in between the hosting view centres the shorter of the two, dropping
        // the tab switcher down the window and snapping it back. Filling leaves
        // nothing to centre, so the switcher cannot move.
        .frame(maxHeight: .infinity, alignment: .top)
        #if canImport(AppKit)
        // With no fixed root frame to size itself from, the window is sized
        // here instead — see `SettingsWindowConfigurator`.
        .background(SettingsWindowConfigurator(contentSize: CGSize(width: Self.windowWidth, height: windowHeight)))
        #endif
    }

    /// One settings pane: its own padding, its own measurement, its own
    /// cross-fade. The padding lives here so the reported height is the height
    /// the window actually has to be.
    private func pane<Content: View>(
        _ tab: SettingsTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .background {
                HeightReader { height in
                    paneHeights[tab] = height
                    if tab == selectedTab { currentPaneHeight = height }
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .center)))
    }

    // MARK: - Glass Tab Switcher

    private var settingsHeader: some View {
        HStack {
            Spacer()
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(4)
            .liquidGlassSurface(
                in: Capsule(style: .continuous),
                shadowRadius: 6,
                shadowY: 3
            )
            Spacer()
        }
        // Clears the (transparent) titlebar strip and its traffic lights.
        .padding(.top, 24)
        .padding(.bottom, 14)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            // The window height is not in this transaction: it reaches the
            // window through `SettingsWindowConfigurator`, and SwiftUI hands a
            // representable the final value rather than interpolating it. So
            // this animates the capsule and the pane cross-fade only — which a
            // scoped `.animation(_:value:)` on the header did not do at all,
            // leaving the capsule to jump between tabs.
            withAnimation(DSToken.Motion.reveal) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.safeAccentText(accent) : theme.textMuted)
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? theme.text : theme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Capsule(style: .continuous))
            .background {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(accent.opacity(colorScheme == .dark ? 0.26 : 0.18))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(.white.opacity(colorScheme == .dark ? 0.18 : 0.35), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "selectedSettingsTab", in: tabNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Height Measurement

/// Reports the height it is laid out at — i.e. the height of whatever view it
/// is used as the background of.
///
/// Transform-only transitions (`.scale`, `.offset`) do not affect layout, so a
/// pane mid-cross-fade still reports its settled height.
private struct HeightReader: View {
    let onChange: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onChange(of: proxy.size.height, initial: true) { _, height in
                    onChange(height)
                }
        }
    }
}

// MARK: - Window Chrome

#if canImport(AppKit)
/// De-chromes the hosting Settings window — hidden title, transparent titlebar,
/// content extending under it, same treatment as the main window — and sizes it
/// to `contentSize`.
///
/// Sizing lives here because the SwiftUI root deliberately fills the window
/// instead of being a fixed size (see the frame in `SettingsView.body`), which
/// leaves nothing for SwiftUI to size the window from. Resizes keep the window's
/// **top-left** corner fixed: the titlebar and the tab switcher under it are the
/// one thing that must not move when a taller or shorter pane is selected.
private struct SettingsWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize

    func makeNSView(context: Context) -> ChromeView { ChromeView() }

    func updateNSView(_ nsView: ChromeView, context: Context) {
        nsView.apply(contentSize: contentSize)
    }

    @MainActor
    final class ChromeView: NSView {
        private weak var configuredWindow: NSWindow?
        private var pendingContentSize: CGSize?
        private var isResizeScheduled = false

        /// Requests a resize to `contentSize`, applied on the next turn of the
        /// run loop.
        ///
        /// The hop off the current turn is required, not tidiness: SwiftUI calls
        /// this from inside AppKit's layout display cycle, and resizing the
        /// window there throws an uncaught exception out of
        /// `NSDisplayCycleFlush` (SIGABRT on the first tab switch). Deferring
        /// also means SwiftUI has committed the new layout before the window
        /// changes size, so the two never disagree mid-render.
        func apply(contentSize: CGSize) {
            pendingContentSize = contentSize
            guard configuredWindow != nil, !isResizeScheduled else { return }
            isResizeScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isResizeScheduled = false
                if let size = self.pendingContentSize {
                    self.resize(to: size)
                }
            }
        }

        /// Resizes the hosting window, anchored at its top-left corner. No-ops
        /// unless the size really changed — an unconditional `setFrame` would
        /// fight the user dragging the window.
        private func resize(to contentSize: CGSize) {
            guard let window = configuredWindow else { return }
            guard contentSize.width > 0, contentSize.height > 0 else { return }

            // The window is `.fullSizeContentView` with a transparent titlebar,
            // so its frame *is* its content area and the size can be set
            // directly. Going through `contentRect(forFrameRect:)` instead is
            // what makes the width drift by the border width on every resize.
            let current = window.frame
            guard abs(contentSize.width - current.width) > 0.5
                || abs(contentSize.height - current.height) > 0.5 else { return }

            window.setFrame(
                NSRect(
                    x: current.minX,
                    y: current.maxY - contentSize.height,  // keep the top edge put
                    width: contentSize.width,
                    height: contentSize.height
                ),
                display: true
            )
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window !== configuredWindow else { return }
            configuredWindow = window

            applyChrome()
            // Synchronously for the first size only, so the window is never
            // shown at SwiftUI's default size before snapping to the content's.
            // Later resizes go through `apply(contentSize:)` and its run-loop
            // hop; this one runs before the window is on screen.
            if let pendingContentSize {
                resize(to: pendingContentSize)
            }

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
            window.styleMask.insert(.fullSizeContentView)
            // A settings window has one right size, and now that the root view
            // fills whatever it is given, SwiftUI would otherwise let it be
            // dragged to any other one.
            window.styleMask.remove(.resizable)
        }
    }
}
#endif

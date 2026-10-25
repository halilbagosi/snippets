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
    /// start sliding under the titlebar and its traffic lights.
    @State private var isScrolled = false

    /// Reopening Settings returns to the tab it was left on, as macOS
    /// Settings windows do.
    @AppStorage("settings.selectedPane") private var pane: SettingsPane = .general

    var body: some View {
        DSGlassContainer(spacing: 20) {
            ScrollView {
                AppearanceView(pane: pane)
                    .padding(.horizontal, 24)
                    // Clears the (transparent) titlebar strip, where the tab
                    // picker sits beside the traffic lights.
                    .padding(.top, 48)
                    .padding(.bottom, 28)
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
            // The titlebar's default edge is the hard style: a rule and a
            // flat band the panes cut off against. Soft drops both and lets
            // the panes pass under the traffic lights, where the veil below
            // blurs and fades them.
            .scrollEdgeEffectStyle(.soft, for: .top)
            // A new tab starts at its top, not at the old tab's offset.
            .id(pane)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > 1
            } action: { _, scrolled in
                withAnimation(DSToken.Motion.hover) { isScrolled = scrolled }
            }
        }
        .overlay(alignment: .top) {
            ScrollEdgeVeil()
                .opacity(isScrolled ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .top) { panePicker }
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
}

extension SettingsView {
    /// Centred in the titlebar strip, level with the traffic lights, so it
    /// stays put while the panes scroll under it.
    private var panePicker: some View {
        Picker("Settings tab", selection: $pane) {
            ForEach(SettingsPane.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .padding(.top, 4)
        .ignoresSafeArea(edges: .top)
    }
}

// MARK: - Scroll edge

/// Blurs and fades the panes as they scroll under the transparent titlebar,
/// so a card passing behind the traffic lights softens away instead of
/// colliding with them. Material for the blur, the window colour for the
/// fade, both dissolving downward.
private struct ScrollEdgeVeil: View {
    /// The titlebar strip plus room for the fade to finish below it.
    private static let height: CGFloat = 64

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
            window.styleMask.insert(.fullSizeContentView)
            // Settings windows come up fixed-size whatever the scene's
            // resizability says.
            window.styleMask.insert(.resizable)
        }
    }
}
#endif

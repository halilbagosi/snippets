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
    /// A stable window frame: the ScrollView below owns overflow instead of
    /// asking AppKit to resize during a SwiftUI layout pass.
    private static let windowHeight: CGFloat = 720

    private var accent: Color { appearanceSettings.themeColor }

    var body: some View {
        ScrollView {
            DSGlassContainer(spacing: 20) {
                AppearanceView()
                    .padding(.horizontal, 24)
                    // Clears the (transparent) titlebar strip and its traffic lights.
                    .padding(.top, 44)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                Color.clear.ignoresSafeArea()
                DotGridBackground(gradientPalette: [accent], lightModeStrength: 0.5)
                    .opacity(colorScheme == .dark ? 0.12 : 0.10)
                    .ignoresSafeArea()
            }
        }
        .frame(width: Self.windowWidth, height: Self.windowHeight, alignment: .top)
        #if canImport(AppKit)
        .background(SettingsWindowConfigurator())
        #endif
    }
}

// MARK: - Window Chrome

#if canImport(AppKit)
/// De-chromes the hosting Settings window — hidden title, transparent titlebar,
/// content extending under it — same treatment as the main window.
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
            // The root view owns one stable size, so the settings window should
            // not be dragged to a different size underneath it.
            window.styleMask.remove(.resizable)
        }
    }
}
#endif

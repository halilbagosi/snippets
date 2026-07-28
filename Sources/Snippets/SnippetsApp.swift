import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

#if targetEnvironment(macCatalyst)
#error("Snippets is a native macOS app. In Xcode, select the run destination 'My Mac' (not Mac Catalyst or Designed for iPad).")
#endif

#if canImport(AppKit)
/// Invisible helper view that configures the hosting `NSWindow`: hides the
/// window title, and hides the traffic lights only while in full screen
/// (they stay visible in normal windowed mode).
struct WindowChromeConfigurator: NSViewRepresentable {
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

            // SwiftUI reasserts some window properties during scene updates,
            // so reapply the chrome on key/full-screen transitions.
            let notifications: [NSNotification.Name] = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didEnterFullScreenNotification,
                NSWindow.didExitFullScreenNotification,
            ]
            for name in notifications {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(applyChrome),
                    name: name,
                    object: window
                )
            }
        }

        @objc private func applyChrome() {
            guard let window = configuredWindow else { return }
            window.titleVisibility = .hidden

            // Match windowed mode's translucent chrome in full screen too:
            // without this, the full-screen auto-hide titlebar strip falls
            // back to the OS's default opaque titlebar material, because it's
            // a separate AppKit-drawn surface that SwiftUI's
            // .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            // (used in SnippetsApp's body) doesn't reach.
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)

            // Make the green button offer real full screen (arrows) instead
            // of plain zoom ("+"): the window must advertise that it can be
            // a primary full-screen window.
            window.collectionBehavior.insert(.fullScreenPrimary)

            let isFullScreen = window.styleMask.contains(.fullScreen)
            let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for type in buttons {
                window.standardWindowButton(type)?.alphaValue = isFullScreen ? 0 : 1
            }
        }
    }
}
#endif

#if canImport(AppKit)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        ColorPanelCenterer.shared.install()
        MenuBarController.shared.install()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainWindowOpener.activate()
        return true
    }

    /// The app now lives in the menu bar after its last window closes, which is
    /// the whole point of the quick-copy panel — it must be reachable while the
    /// user is working somewhere else. The panel footer carries Quit, because
    /// with no window and another app frontmost the menu bar is not ours.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

}
#endif

@main
struct SnippetsApp: App {
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var environment = AppEnvironment()
    @State private var appearanceSettings = AppearanceSettings()
    @State private var previewTrust = PreviewTrust()

    static let mainWindowID = "main"

    var body: some Scene {
        WindowGroup(id: SnippetsApp.mainWindowID) {
            if #available(macOS 15.0, *) {
                ContentView()
                    .previewTrustPrompt()
                    .environment(environment)
                    .environment(appearanceSettings)
                    .environment(previewTrust)
                    .environment(AppIntentNavigator.shared)
                    .modifier(MainWindowOpenerInstaller())
                // Appearance preference is applied via NSApp.appearance in
                // AppearanceSettings: preferredColorScheme would pin a per-window
                // override that AppKit can't clear when following the system.
                    .frame(minWidth: 1100, minHeight: 720)
                // Without this the window can be zoom-only (green button shows
                // "+"); this makes it a real full-screen-capable window.
                    .windowFullScreenBehavior(.enabled)
                // The gallery draws its own glass bar under the toolbar area;
                // hide the system toolbar background so it doesn't stack a
                // darker adaptive layer on top (visible on hover / when the
                // sidebar is collapsed).
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                    .task { SnippetsApp.backfillUUIDs() }
            } else {
                ContentView()
                    .previewTrustPrompt()
                    .environment(environment)
                    .environment(appearanceSettings)
                    .environment(previewTrust)
                    .environment(AppIntentNavigator.shared)
                    .modifier(MainWindowOpenerInstaller())
                // Appearance preference is applied via NSApp.appearance in
                // AppearanceSettings: preferredColorScheme would pin a per-window
                // override that AppKit can't clear when following the system.
                    .frame(minWidth: 1100, minHeight: 720)
                    .task { SnippetsApp.backfillUUIDs() }            }
        }
        #if os(macOS)
        // Hides the "Snippets" title in the toolbar via the supported API.
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .help) { }
            CommandGroup(after: .windowArrangement) {
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
        #endif
        .modelContainer(SnippetsData.sharedModelContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appearanceSettings)
                .environment(previewTrust)
        }
        #endif
    }

    @MainActor
    static func backfillUUIDs() {
        let context = SnippetsData.sharedModelContainer.mainContext
        let snippets = (try? context.fetch(FetchDescriptor<Snippet>())) ?? []
        let collections = (try? context.fetch(FetchDescriptor<SnippetCollection>())) ?? []
        if UUIDBackfill.assign(snippets: snippets, collections: collections) > 0 {
            try? context.save()
        }
    }
}

#if canImport(AppKit)
/// Parks an `openWindow` closure where `AppDelegate` can reach it, so clicking
/// the Dock icon can restore a window after the last one was closed.
private struct MainWindowOpenerInstaller: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onAppear {
            MainWindowOpener.open = { openWindow(id: SnippetsApp.mainWindowID) }
        }
    }
}
#endif

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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        for window in sender.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

}
#endif

@main
struct SnippetsApp: App {
    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var environment = AppEnvironment()
    @State private var appearanceSettings = AppearanceSettings()

    private var sharedModelContainer: ModelContainer = {
        let schema = Schema([Snippet.self, MediaItem.self, SnippetCollection.self])
        let appSupport = URL.applicationSupportDirectory
        let storeURL = appSupport.appending(path: "Snippets.store")

        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            let configuration = ModelConfiguration(url: storeURL)
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Unresolved error loading SwiftData container: \(error.localizedDescription)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(environment)
                .environment(appearanceSettings)
                .preferredColorScheme(appearanceSettings.resolvedColorScheme)
                .frame(minWidth: 1100, minHeight: 720)
                // Without this the window can be zoom-only (green button shows
                // "+"); this makes it a real full-screen-capable window.
                .windowFullScreenBehavior(.enabled)
                // The gallery draws its own glass bar under the toolbar area;
                // hide the system toolbar background so it doesn't stack a
                // darker adaptive layer on top (visible on hover / when the
                // sidebar is collapsed).
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
        .modelContainer(sharedModelContainer)

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appearanceSettings)
        }
        #endif
    }
}

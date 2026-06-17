import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

#if targetEnvironment(macCatalyst)
#error("Snippets is a native macOS app. In Xcode, select the run destination 'My Mac' (not Mac Catalyst or Designed for iPad).")
#endif

#if canImport(AppKit)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        configureWindows(NSApp.windows)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            NSApp.activate(ignoringOtherApps: true)
            configureWindows(NSApp.windows)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        configureWindows(sender.windows)
        for window in sender.windows where window.canBecomeMain {
            window.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func configureWindows(_ windows: [NSWindow]) {
        for window in windows where window.canBecomeMain {
            window.styleMask.formUnion([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.collectionBehavior.insert(.managed)
            window.minSize = NSSize(width: 1100, height: 720)
            window.standardWindowButton(.zoomButton)?.isEnabled = true
        }
    }
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
        }
        #if os(macOS)
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

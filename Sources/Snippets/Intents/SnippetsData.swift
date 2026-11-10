import AppKit
import Foundation
import SwiftData

/// The single SwiftData container shared by the SwiftUI app and every App Intent.
/// Intents may run while the app is backgrounded, so both paths must open the
/// same store — two containers on one URL would conflict.
enum SnippetsData {
    /// Opened by `bootstrap()` from `main()`, before SwiftUI starts. The open
    /// happens there because a failure shows a modal alert, and running a modal
    /// session inside the `sharedModelContainer` initializer re-enters its
    /// `dispatch_once` from an animation frame and traps.
    @MainActor
    static var bootstrapped: ModelContainer?

    @MainActor
    static let sharedModelContainer: ModelContainer = {
        if let bootstrapped { return bootstrapped }
        // Only reached under XCTest, or if `bootstrap()` was never called.
        let appSupport = URL.applicationSupportDirectory

        do {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            return try makeContainer(at: storeURL)
        } catch {
            fatalError("Unresolved error loading SwiftData container: \(error.localizedDescription)")
        }
    }()

    static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "Snippets.store")
    }

    static var backupsDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Snippets/Backups")
    }

    @MainActor
    static func makeContainer(at storeURL: URL) throws -> ModelContainer {
        let schema = Schema([Snippet.self, MediaItem.self, SnippetCollection.self])
        let configuration = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// Backs the store up when this is the first launch of a new build, then
    /// opens it, offering recovery instead of crashing when it cannot be
    /// opened. Must run on the main thread before SwiftUI starts, and must not
    /// run for `--mcp-stdio`, which never touches the store.
    @MainActor
    static func bootstrap() {
        try? FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        // Tests keep today's behaviour: in-memory containers, no alert, no backups.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }

        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        StoreBackup.backUpIfBuildChanged(
            storeURL: storeURL, backupsDirectory: backupsDirectory,
            currentBuild: build, defaults: .standard)

        var presentedAlert = false
        bootstrapped = StoreBootstrap.open(
            storeURL: storeURL, backupsDirectory: backupsDirectory,
            makeContainer: { try makeContainer(at: $0) },
            ask: { error in
                if !presentedAlert {
                    // SwiftUI has not started, so the app is not yet a regular,
                    // frontmost application.
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    presentedAlert = true
                }
                return askRecovery(error)
            },
            reveal: { NSWorkspace.shared.activateFileViewerSelecting([$0]) })
        if bootstrapped == nil { exit(0) }
    }

    @MainActor
    private static func askRecovery(_ error: Error) -> StoreRecoveryChoice {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Snippets couldn’t open your library"
        alert.informativeText = StoreBootstrap.recoveryMessage(for: error)
        // Quit is first, so it is the default button: Return changes nothing.
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Start with an Empty Library")
        switch alert.runModal() {
        case .alertSecondButtonReturn: return .reveal
        case .alertThirdButtonReturn: return .startEmpty
        default: return .quit
        }
    }
}

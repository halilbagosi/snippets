import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)

/// Watches the clipboard for copied code, when the user has asked it to.
///
/// macOS has no clipboard-change notification, so polling `changeCount` is the
/// only mechanism available. The timer carries a tolerance so the OS can
/// coalesce it with other work rather than waking the CPU on its own schedule.
///
/// This type holds no policy: every accept/reject decision belongs to
/// `ClipboardCapture`. Clipboard content is never written to disk here — a
/// candidate lives in memory until the user accepts it in the panel.
@Observable
@MainActor
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    /// Opt-in, and off by default: the app should not start reading the
    /// clipboard because it was launched.
    static let enabledDefaultsKey = "quickCapture.enabled"

    private static let interval: TimeInterval = 1.0

    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
            isEnabled ? start() : stop()
        }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSeenChangeCount = NSPasteboard.general.changeCount
    /// Whether a Snippets build is the active app *now*. Updated only after
    /// the change pending at an app switch has been attributed to the app that
    /// was active before it, so a copy made just before switching is credited
    /// to the right app.
    @ObservationIgnored private var snippetsIsFrontmost = false
    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    /// Begin polling if enabled. Safe to call repeatedly.
    func start() {
        guard isEnabled, timer == nil else { return }
        lastSeenChangeCount = NSPasteboard.general.changeCount
        snippetsIsFrontmost = Self.isSnippets(NSWorkspace.shared.frontmostApplication)

        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let activatedSnippets = Self.isSnippets(app)
            Task { @MainActor in ClipboardMonitor.shared.frontmostChanged(toSnippets: activatedSnippets) }
        }

        let created = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in ClipboardMonitor.shared.poll() }
        }
        created.tolerance = Self.interval / 2
        timer = created
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private nonisolated static func isSnippets(_ app: NSRunningApplication?) -> Bool {
        ClipboardCapture.isSnippets(
            bundleIdentifier: app?.bundleIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    /// Settles any change still pending from before the switch — e.g. code
    /// copied in another app a moment before clicking into Snippets — against
    /// the app that was frontmost when it was made, then records the new one.
    private func frontmostChanged(toSnippets activatedSnippets: Bool) {
        guard timer != nil else { return }
        poll()
        snippetsIsFrontmost = activatedSnippets
    }

    /// Reads the pasteboard's contents, not just its metadata.
    ///
    /// Measured on macOS 27.0 (build 26A5388g): this did not produce a visible
    /// paste-permission alert for this app during the four-copy probe. Re-measure
    /// on a major OS update — the gating is Apple's and the feature stops being
    /// viable if it ever starts applying here. See `Docs/security-overview.md`.
    private func poll() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let candidate = ClipboardCapture.candidate(
            text: pasteboard.string(forType: .string),
            types: types,
            isOwnWrite: ClipboardCapture.isSelfOriginated(
                isOwnWrite: current == Clipboard.lastLocalChangeCount,
                snippetsWasFrontmost: snippetsIsFrontmost
            )
        )

        guard let candidate else { return }
        MenuBarController.shared.showPanel(capture: candidate)
    }
}
#endif

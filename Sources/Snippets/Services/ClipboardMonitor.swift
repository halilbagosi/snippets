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

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
    }

    /// Begin polling if enabled. Safe to call repeatedly.
    func start() {
        guard isEnabled, timer == nil else { return }
        lastSeenChangeCount = NSPasteboard.general.changeCount

        let created = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in ClipboardMonitor.shared.poll() }
        }
        created.tolerance = Self.interval / 2
        timer = created
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pasteboard = NSPasteboard.general
        let current = pasteboard.changeCount
        guard current != lastSeenChangeCount else { return }
        lastSeenChangeCount = current

        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        let candidate = ClipboardCapture.candidate(
            text: pasteboard.string(forType: .string),
            types: types,
            isOwnWrite: current == Clipboard.lastLocalChangeCount
        )

        guard let candidate else { return }
        MenuBarController.shared.showPanel(capture: candidate)
    }
}
#endif

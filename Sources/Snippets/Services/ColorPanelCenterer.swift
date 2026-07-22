import AppKit

/// Centers the shared color panel over the app's window.
///
/// Every SwiftUI `ColorPicker` in the app opens the one shared
/// `NSColorPanel`, and AppKit restores whatever frame that panel was last
/// left at — persisted in `NSWindow Frame NSColorPanel`. In practice it
/// reopens in the bottom-left corner of the screen, nowhere near the swatch
/// that opened it. Repositioning it as it becomes key puts it where the
/// user is looking instead.
@MainActor
final class ColorPanelCenterer: NSObject {
    static let shared = ColorPanelCenterer()

    private var isInstalled = false

    /// Idempotent, so it is safe to call from every app launch path.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let panel = notification.object as? NSColorPanel else { return }
        // AppKit restores the panel's autosaved frame right after it becomes
        // key, so centering synchronously here loses the race. Deferring to the
        // next runloop tick runs the reposition after that restore wins.
        DispatchQueue.main.async { [weak self] in
            self?.center(panel)
        }
    }

    private func center(_ panel: NSColorPanel) {
        // A sheet (the snippet detail modal) is not a main window, so prefer the
        // key/main window and fall back to the largest visible ordinary window,
        // which is the document window the sheet is attached to.
        let host = NSApp.mainWindow
            ?? NSApp.keyWindow.flatMap { $0 is NSPanel ? nil : $0 }
            ?? NSApp.windows
                .filter { $0.isVisible && !($0 is NSPanel) }
                .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let hostFrame = host?.frame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        panel.setFrameOrigin(
            NSPoint(
                x: hostFrame.midX - size.width / 2,
                y: hostFrame.midY - size.height / 2
            )
        )
    }
}

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
        center(panel)
    }

    private func center(_ panel: NSColorPanel) {
        // The color panel is itself key by this point, so `mainWindow` is the
        // document window behind it; fall back to any visible ordinary window,
        // then to the screen, so the panel is never left off in a corner.
        let host = NSApp.mainWindow
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.canBecomeMain }
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

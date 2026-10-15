import AppKit

/// Centers the shared color panel over the app's window each time it opens.
///
/// Every SwiftUI `ColorPicker` in the app opens the one shared
/// `NSColorPanel`, and AppKit restores whatever frame that panel was last
/// left at — persisted as `NSWindow Frame NSColorPanel`, in practice the
/// bottom-left corner of the screen, nowhere near the swatch that opened it.
///
/// The hook is `didUpdateNotification` rather than the more obvious
/// `didBecomeKeyNotification`: `NSColorPanel` is an `NSPanel`, and a panel
/// only takes key when it actually needs input, so opening one frequently
/// posts no key notification at all. `didUpdate` fires for visible windows
/// on the event-loop cycle, which is after AppKit has restored the
/// autosaved frame — so repositioning here also wins that race.
@MainActor
final class ColorPanelCenterer: NSObject {
    static let shared = ColorPanelCenterer()

    private var isInstalled = false
    /// Centering happens once per presentation, so the user stays free to
    /// drag the panel wherever they like while it is open.
    private var hasCenteredThisPresentation = false

    /// Idempotent, so it is safe to call from every app launch path.
    func install() {
        guard !isInstalled else { return }
        isInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidUpdate(_:)),
            name: NSWindow.didUpdateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        guard let panel = notification.object as? NSColorPanel,
              panel.isVisible,
              !hasCenteredThisPresentation else { return }
        hasCenteredThisPresentation = true
        center(panel)
    }

    /// Closing arms the next presentation to be centered again.
    @objc private func windowWillClose(_ notification: Notification) {
        guard notification.object is NSColorPanel else { return }
        hasCenteredThisPresentation = false
    }

    private func center(_ panel: NSColorPanel) {
        // A sheet (the snippet detail modal) is not a main window, so prefer
        // the key/main window and fall back to the largest visible ordinary
        // window, which is the document window a sheet is attached to.
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

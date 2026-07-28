import SwiftUI
import Observation
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)

/// Lets AppKit reopen the SwiftUI `WindowGroup` after its last window closed.
///
/// `AppDelegate` cannot call `openWindow` directly — it is a SwiftUI
/// environment action — so `ContentView` parks a closure here on appear.
@MainActor
enum MainWindowOpener {
    static var open: (() -> Void)?

    /// Bring the app forward, restoring a window if none is left.
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
        let restorable = NSApp.windows.filter(\.canBecomeMain)
        if restorable.isEmpty {
            open?()
        } else {
            for window in restorable { window.makeKeyAndOrderFront(nil) }
        }
    }
}

/// Carries an accepted capture to the editor. Nothing is persisted here —
/// the draft is handed over unsaved, so a bad detection costs one ⌘W and
/// leaves no row in the store.
@MainActor
@Observable
final class CaptureDraft {
    static let shared = CaptureDraft()
    var pending: ClipboardCapture.Candidate?
    private init() {}
}

/// Owns the menu bar item and the panel that hangs from it.
///
/// The only AppKit surface in this feature. `MenuBarExtra(.window)` was not
/// used because four behaviours here need control it does not offer:
/// programmatic dismissal after the copy confirmation, auto-close on
/// `resignKey`, first-responder handoff to the search field on open, and an
/// entrance anchored to the status item rather than a system fade.
@MainActor
final class MenuBarController: NSObject, NSWindowDelegate {
    static let shared = MenuBarController()

    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var model: QuickCopyViewModel?

    private override init() { super.init() }

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "scissors",
            accessibilityDescription: "Snippets quick copy"
        )
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        statusItem = item
    }

    @objc private func statusItemClicked() {
        togglePanel()
    }

    func togglePanel() {
        if panel?.isVisible == true { hidePanel() } else { showPanel(capture: nil) }
    }

    /// Present the panel. A non-nil `capture` means this was triggered by the
    /// clipboard monitor rather than a click, so the panel must NOT take key
    /// focus — it would swallow keystrokes meant for the app the user is in.
    func showPanel(capture: ClipboardCapture.Candidate?) {
        let model = existingOrNewModel()
        model.reload()
        model.pendingCapture = capture

        let panel = existingOrNewPanel()
        position(panel)
        // `hidePanel` fades the window itself out; the entrance is SwiftUI's,
        // so the window must be fully opaque again before it is shown.
        panel.alphaValue = 1

        // Rebuild the hosted view on every open. SwiftUI keeps the view tree
        // alive across order-out/order-front, so without this neither the
        // entrance animation nor the search-field focus would fire a second
        // time — the panel would open dead on its second use.
        panel.contentView = NSHostingView(rootView: makeRoot(model: model, panel: panel))

        panel.orderFront(nil)
        if capture == nil {
            panel.makeKey()
        }
    }

    func hidePanel() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.13   // matches DSToken.Motion.popoverOut
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
        }
    }

    // MARK: Window delegate

    /// Clicking away dismisses, the way every other menu bar panel behaves.
    func windowDidResignKey(_ notification: Notification) {
        hidePanel()
    }

    // MARK: Construction

    private func existingOrNewModel() -> QuickCopyViewModel {
        if let model { return model }
        let created = QuickCopyViewModel(context: SnippetsData.sharedModelContainer.mainContext)
        model = created
        return created
    }

    private func existingOrNewPanel() -> NSPanel {
        if let panel { return panel }

        let created = NSPanel(
            contentRect: NSRect(
                x: 0, y: 0,
                width: QuickCopyPanel.panelWidth,
                height: QuickCopyPanel.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.level = .statusBar
        created.hidesOnDeactivate = false
        created.isMovable = false
        created.delegate = self
        // A borderless panel refuses key by default; the search field needs it.
        created.becomesKeyOnlyIfNeeded = false

        panel = created
        return created
    }

    private func makeRoot(model: QuickCopyViewModel, panel: NSPanel) -> some View {
        QuickCopyPanel(
            model: model,
            scaleAnchor: scaleAnchor(for: panel),
            onDismiss: { [weak self] in self?.hidePanel() },
            onOpenMainWindow: { [weak self] snippet in
                self?.hidePanel()
                MainWindowOpener.activate()
                // ContentView observes this and opens the snippet, then clears
                // it — see its `.onChange(of: navigator.pendingOpenSnippetUUID)`.
                if let snippet, let uuid = snippet.uuid {
                    AppIntentNavigator.shared.pendingOpenSnippetUUID = uuid
                }
            },
            onQuit: { NSApp.terminate(nil) }
        )
        // The panel lives outside the scene graph, so it inherits nothing from
        // the WindowGroup's `.modelContainer`.
        .modelContainer(SnippetsData.sharedModelContainer)
    }

    /// Hang the panel under the status item, kept fully on screen.
    private func position(_ panel: NSPanel) {
        guard
            let button = statusItem?.button,
            let buttonWindow = button.window,
            let screen = buttonWindow.screen ?? NSScreen.main
        else { return }

        let buttonInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let visible = screen.visibleFrame
        let gap: CGFloat = 6

        var x = buttonInScreen.midX - QuickCopyPanel.panelWidth / 2
        x = min(max(x, visible.minX + gap), visible.maxX - QuickCopyPanel.panelWidth - gap)
        let y = buttonInScreen.minY - QuickCopyPanel.panelHeight - gap

        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Where the status item sits along the panel's top edge, as a `UnitPoint`.
    ///
    /// Near a screen edge the panel gets pushed sideways to stay on screen, so
    /// this cannot be assumed to be the centre — it is measured against the
    /// panel's actual frame after positioning.
    private func scaleAnchor(for panel: NSPanel) -> UnitPoint {
        guard
            let button = statusItem?.button,
            let buttonWindow = button.window
        else { return .top }

        let buttonInScreen = buttonWindow.convertToScreen(
            button.convert(button.bounds, to: nil)
        )
        let offset = buttonInScreen.midX - panel.frame.minX
        let fraction = min(max(offset / panel.frame.width, 0), 1)
        return UnitPoint(x: fraction, y: 0)
    }
}
#endif

import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
enum Clipboard {
    /// `changeCount` produced by our own most recent write.
    ///
    /// The capture monitor compares against this so copying *from* Snippets
    /// never prompts the user to save a snippet they already have. Every copy
    /// button in the app funnels through `copy(_:)`. Copies the app doesn't
    /// write itself (⌘C out of a code view) are caught by the monitor's
    /// frontmost-app check instead.
    private(set) static var lastLocalChangeCount: Int = -1

    static func copy(_ string: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        write(string, to: pasteboard)
        lastLocalChangeCount = pasteboard.changeCount
        #endif
    }

    #if canImport(AppKit)
    /// The write itself, separate so tests can aim it at a private pasteboard.
    static func write(_ string: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        // Marks the copy as ours for every running Snippets build, not just
        // this process (see `ClipboardCapture.internalCopyType`). Apps that
        // paste ignore types they do not know.
        pasteboard.setData(
            Data(), forType: NSPasteboard.PasteboardType(ClipboardCapture.internalCopyType)
        )
    }
    #endif
}

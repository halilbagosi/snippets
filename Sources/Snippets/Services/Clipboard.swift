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
    /// path in the app funnels through `copy(_:)`, so recording it here covers
    /// all of them from one place.
    private(set) static var lastLocalChangeCount: Int = -1

    static func copy(_ string: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        lastLocalChangeCount = pasteboard.changeCount
        #endif
    }
}

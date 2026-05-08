import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum Clipboard {
    static func copy(_ string: String) {
        #if canImport(AppKit)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        #endif
    }
}

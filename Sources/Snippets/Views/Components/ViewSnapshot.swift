#if canImport(AppKit)
import AppKit
import SwiftUI

/// Utility to render a SwiftUI view into an `NSImage` at a fixed size.
enum ViewSnapshot {
    @MainActor
    static func snapshot<V: View>(of view: V, size: CGSize) -> NSImage? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: hosting.bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
#endif

#if canImport(AppKit)
import AppKit
import SwiftUI

/// Utility to render a SwiftUI view into an `NSImage` at a fixed size.
enum ViewSnapshot {
    @MainActor
    static func snapshot<V: View>(of view: V, size: CGSize) -> NSImage? {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2.0
        renderer.isOpaque = false

        guard let cgImage = renderer.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0 && height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return NSImage(cgImage: cgImage, size: size)
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let sanitizedCGImage = context.makeImage() else {
            return NSImage(cgImage: cgImage, size: size)
        }

        return NSImage(cgImage: sanitizedCGImage, size: size)
    }
}
#endif

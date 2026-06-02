import SwiftUI
import MetalKit

/// A lightweight SwiftUI overlay that hosts the Metal shatter renderer.
struct MetalGenieOverlay: View {
    var progress: CGFloat
    var accent: Color
    #if os(macOS)
    var snapshot: NSImage?
    #endif

    static var isSupported: Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }

    var body: some View {
        Group {
            #if os(macOS)
            MetalGenieRepresentable(progress: progress, accent: accent, snapshot: snapshot)
                .allowsHitTesting(false)
            #else
            // Fallback: simple translucent overlay for other platforms
            Rectangle()
                .fill(Color.white.opacity(Double(1 - progress) * 0.10))
                .allowsHitTesting(false)
            #endif
        }
    }
}

#if os(macOS)
fileprivate struct MetalGenieRepresentable: NSViewRepresentable {
    var progress: CGFloat
    var accent: Color
    var snapshot: NSImage?

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.enableSetNeedsDisplay = true
        view.isPaused = true

        if context.coordinator.renderer == nil {
            context.coordinator.renderer = MetalGenieRenderer(mtkView: view)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.progress = Float(progress)
        // Pass accent color into renderer
        #if canImport(AppKit)
        if let nsAccent = NSColor(accent).usingColorSpace(.deviceRGB) {
            renderer.accentColor = SIMD4<Float>(Float(nsAccent.redComponent), Float(nsAccent.greenComponent), Float(nsAccent.blueComponent), Float(nsAccent.alphaComponent))
        }
        #endif
        renderer.updateTexture(from: snapshot)
        nsView.setNeedsDisplay(nsView.bounds)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator {
        var renderer: MetalGenieRenderer?
    }
}
#endif

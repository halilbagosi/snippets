import SwiftUI
import MetalKit

/// A SwiftUI overlay that renders a card snapshot through the disintegration shader.
struct MetalDisintegrationOverlay: View {
    var progress: CGFloat
    var accent: Color
    #if os(macOS)
    var snapshot: NSImage?
    #endif

    static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    var body: some View {
        Group {
            #if os(macOS)
            MetalDisintegrationRepresentable(progress: progress, accent: accent, snapshot: snapshot)
                .allowsHitTesting(false)
            #else
            Rectangle()
                .fill(accent.opacity(Double(1 - progress) * 0.10))
                .allowsHitTesting(false)
            #endif
        }
    }
}

#if os(macOS)
private struct MetalDisintegrationRepresentable: NSViewRepresentable {
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
            context.coordinator.renderer = MetalDisintegrationRenderer(mtkView: view)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        renderer.progress = Float(progress)
        if let nsAccent = NSColor(accent).usingColorSpace(.deviceRGB) {
            renderer.accentColor = SIMD4<Float>(
                Float(nsAccent.redComponent),
                Float(nsAccent.greenComponent),
                Float(nsAccent.blueComponent),
                Float(nsAccent.alphaComponent)
            )
        }
        renderer.updateTexture(from: snapshot)
        nsView.setNeedsDisplay(nsView.bounds)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: MetalDisintegrationRenderer?
    }
}
#endif

#Preview("MetalDisintegrationOverlay") {
    MetalDisintegrationOverlay(progress: 0.5, accent: .blue)
        .frame(width: 300, height: 400)
        .background(Color.black)
}

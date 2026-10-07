import SwiftUI
import MetalKit

/// A SwiftUI overlay that renders a card snapshot through the disintegration shader.
///
/// The animation is clocked by the Metal view's own display link — SwiftUI only
/// supplies the start date once; per-frame progress never round-trips through
/// view updates, so frame pacing survives main-thread layout work (e.g. the
/// grid reflow that runs while a card is being deleted).
struct MetalDisintegrationOverlay: View {
    var startDate: Date
    var duration: TimeInterval
    var accent: Color
    #if os(macOS)
    var snapshot: NSImage?
    #endif
    /// Renders a single static frame instead of animating (previews).
    var fixedProgress: CGFloat? = nil

    static var isSupported: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    var body: some View {
        #if os(macOS)
        MetalDisintegrationRepresentable(
            startDate: startDate,
            duration: duration,
            accent: accent,
            snapshot: snapshot,
            fixedProgress: fixedProgress
        )
        .allowsHitTesting(false)
        #else
        Color.clear
            .allowsHitTesting(false)
        #endif
    }
}

#if os(macOS)
private struct MetalDisintegrationRepresentable: NSViewRepresentable {
    var startDate: Date
    var duration: TimeInterval
    var accent: Color
    var snapshot: NSImage?
    var fixedProgress: CGFloat?

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.wantsLayer = true
        view.layer?.isOpaque = false
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)

        if context.coordinator.renderer == nil {
            context.coordinator.renderer = MetalDisintegrationRenderer(mtkView: view)
        }

        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        guard let renderer = context.coordinator.renderer else { return }
        if let nsAccent = NSColor(accent).usingColorSpace(.deviceRGB) {
            renderer.accentColor = SIMD4<Float>(
                Float(nsAccent.redComponent),
                Float(nsAccent.greenComponent),
                Float(nsAccent.blueComponent),
                Float(nsAccent.alphaComponent)
            )
        }
        renderer.updateTexture(from: snapshot)
        if let fixedProgress {
            renderer.showFixedProgress(Float(fixedProgress))
        } else {
            renderer.beginAnimation(startDate: startDate, duration: duration)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var renderer: MetalDisintegrationRenderer?
    }
}
#endif

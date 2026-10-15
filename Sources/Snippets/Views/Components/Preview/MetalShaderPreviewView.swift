import SwiftUI
import MetalKit

/// Live preview for Metal shader snippets: compiles the source at runtime with
/// `MTLLibrary(source:)` and renders a fullscreen pass with time/resolution/
/// mouse uniforms (see `MetalShaderSource` for the snippet convention).
struct MetalShaderPreviewView: View {
    let entry: String
    let helpers: [String]
    let theme: Theme
    /// Tweakable `SnippetParams` fields (declaration order = buffer layout)
    /// and their live values from the preview's parameter controls.
    var params: [PreviewParam] = []
    var paramValues: [String: PreviewParamValue] = [:]

    private var changeKey: String { (helpers + [entry]).joined(separator: "\u{0}") }

    /// The last pipeline that compiled successfully. Kept on screen while a
    /// recompile runs so an edit (or applying a parameter config, which
    /// rewrites the source) never blanks the canvas.
    @State private var pipeline: ShaderPipeline?
    @State private var failure: String?

    private var isFirstCompile: Bool { pipeline == nil && failure == nil }

    var body: some View {
        ZStack {
            // The canvas is opaque black in every state, and matches the
            // MTKView's own clear colour. An MTKView presents nothing until its
            // first drawable, and the panel behind this view is bright Liquid
            // Glass — which is what showed through as a white flash each time a
            // shader was compiled or recompiled.
            Color.black

            if let pipeline {
                ShaderRenderView(pipeline: pipeline, params: params, paramValues: paramValues)
            }

            if let failure {
                ScrollView {
                    Text(failure)
                        .font(Mono.font(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSToken.Spacing.md)
                }
            } else if isFirstCompile {
                ProgressView()
                    .controlSize(.small)
            }
        }
        // Controls sit on the black canvas regardless of the app's appearance.
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: changeKey) {
            let source = entry
            let helperSources = helpers
            let result = await Task.detached(priority: .userInitiated) {
                ShaderPipeline.compile(entry: source, helpers: helperSources)
            }.value
            // `.task(id:)` cancels this task when the source changes, but the
            // detached compile runs to completion regardless — dropping its
            // result keeps a slow older compile from overwriting a newer one.
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let compiled):
                pipeline = compiled
                failure = nil
            case .failure(let error):
                pipeline = nil
                failure = error.localizedDescription
            }
        }
    }
}

/// Shader time, accumulated per drawn frame rather than read off a wall clock.
///
/// An MTKView stops drawing whenever the preview cannot be seen (occluded,
/// minimized, behind another window), but wall-clock time keeps running — so a
/// clock built on `CACurrentMediaTime()` alone made a shader lurch forward by
/// the whole length of the pause the moment it came back into view.
struct ShaderClock {
    private(set) var elapsed: CFTimeInterval = 0
    private var lastFrameTime: CFTimeInterval?

    /// Longest gap credited to a single frame. Collapses a pause of any length
    /// to an imperceptible step, while staying well above the frame time of
    /// even a very heavy shader so real rendering is never slowed down.
    static let maxFrameDelta: CFTimeInterval = 0.25

    mutating func advance(to now: CFTimeInterval) {
        if let lastFrameTime {
            // A backwards step (clock adjustment) contributes nothing rather
            // than winding the shader back.
            elapsed += max(0, min(now - lastFrameTime, Self.maxFrameDelta))
        }
        lastFrameTime = now
    }
}

private struct ShaderRenderView: NSViewRepresentable {
    let pipeline: ShaderPipeline
    var params: [PreviewParam] = []
    var paramValues: [String: PreviewParamValue] = [:]

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MouseTrackingMTKView {
        let view = MouseTrackingMTKView(frame: .zero, device: pipeline.device)
        view.colorPixelFormat = .bgra8Unorm
        // Opaque black, matching the canvas behind the view, so the frames
        // before the first drawable are indistinguishable from a cleared one.
        view.clearColor = MTLClearColorMake(0, 0, 0, 1)
        view.layer?.isOpaque = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        // Match ProMotion displays (the disintegration renderer already runs
        // at 120); MTKView clamps to the actual display refresh rate.
        view.preferredFramesPerSecond = 120
        view.delegate = context.coordinator
        context.coordinator.attach(pipeline: pipeline, view: view)
        context.coordinator.setParams(params, values: paramValues)
        return view
    }

    func updateNSView(_ view: MouseTrackingMTKView, context: Context) {
        // A recompile can hand back a pipeline built on a different device;
        // rendering it through the view's original one draws nothing at all.
        if view.device !== pipeline.device {
            view.device = pipeline.device
        }
        context.coordinator.attach(pipeline: pipeline, view: view)
        context.coordinator.setParams(params, values: paramValues)
    }

    final class Renderer: NSObject, MTKViewDelegate {
        // Must match the Metal-side SnippetUniforms layout.
        private struct Uniforms {
            var time: Float = 0
            var resolution: SIMD2<Float> = .zero
            var mouse: SIMD4<Float> = .zero
        }

        private var pipeline: ShaderPipeline?
        private var commandQueue: MTLCommandQueue?
        private weak var trackingView: MouseTrackingMTKView?
        private var clock = ShaderClock()
        /// Pre-packed `SnippetParams` buffer contents (see
        /// `PreviewParamDetector.packMetalParams`); empty when the snippet
        /// declares no params struct.
        private var packedParams: [UInt8] = []

        func attach(pipeline: ShaderPipeline, view: MouseTrackingMTKView) {
            trackingView = view
            guard self.pipeline !== pipeline else { return }
            self.pipeline = pipeline
            commandQueue = pipeline.device.makeCommandQueue()
        }

        func setParams(_ params: [PreviewParam], values: [String: PreviewParamValue]) {
            packedParams = params.isEmpty
                ? [] : PreviewParamDetector.packMetalParams(params, overrides: values)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            // A zero-sized drawable yields a degenerate resolution uniform,
            // which divides to NaN in most shaders.
            guard view.drawableSize.width > 0, view.drawableSize.height > 0 else { return }
            guard let pipeline,
                  let commandQueue,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            clock.advance(to: CACurrentMediaTime())

            var uniforms = Uniforms()
            uniforms.time = Float(clock.elapsed)
            uniforms.resolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
            uniforms.mouse = trackingView?.mouseState ?? .zero
            encoder.setRenderPipelineState(pipeline.pipelineState)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            if !packedParams.isEmpty {
                packedParams.withUnsafeBytes { buffer in
                    encoder.setFragmentBytes(buffer.baseAddress!, length: buffer.count, index: 1)
                }
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}

/// MTKView that reports mouse position (in pixels, origin bottom-left,
/// shadertoy convention) and button state for the mouse uniform.
final class MouseTrackingMTKView: MTKView {
    private(set) var mouseState: SIMD4<Float> = .zero

    /// The display link free-runs at the display refresh rate, so it must be
    /// stopped whenever the shader cannot actually be seen — otherwise a hidden,
    /// minimized, or fully covered window keeps rendering at 120fps forever.
    /// `occlusionState` folds all of those cases into one signal.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionStateChanged),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
        }

        updatePausedState()
    }

    @objc private func occlusionStateChanged() {
        updatePausedState()
    }

    private func updatePausedState() {
        isPaused = !(window?.occlusionState.contains(.visible) ?? false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateMouse(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        updateMouse(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        mouseState.z = 1
        updateMouse(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        mouseState.z = 0
    }

    private func updateMouse(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let scale = Float(window?.backingScaleFactor ?? 1)
        mouseState.x = Float(point.x) * scale
        mouseState.y = Float(point.y) * scale
    }
}

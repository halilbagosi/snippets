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

    @State private var state: CompileState = .compiling

    private enum CompileState {
        case compiling
        case ready(ShaderPipeline)
        case failed(String)
    }

    var body: some View {
        ZStack {
            switch state {
            case .compiling:
                ProgressView()
                    .controlSize(.small)
            case .ready(let pipeline):
                ShaderRenderView(pipeline: pipeline, params: params, paramValues: paramValues)
            case .failed(let message):
                ScrollView {
                    Text(message)
                        .font(Mono.font(size: 11))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DSToken.Spacing.md)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: changeKey) {
            state = .compiling
            let source = entry
            let helperSources = helpers
            let result = await Task.detached(priority: .userInitiated) {
                ShaderPipeline.compile(entry: source, helpers: helperSources)
            }.value
            switch result {
            case .success(let pipeline): state = .ready(pipeline)
            case .failure(let error): state = .failed(error.localizedDescription)
            }
        }
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
        // Match ProMotion displays (the disintegration renderer already runs
        // at 120); MTKView clamps to the actual display refresh rate.
        view.preferredFramesPerSecond = 120
        view.delegate = context.coordinator
        context.coordinator.attach(pipeline: pipeline, view: view)
        context.coordinator.setParams(params, values: paramValues)
        return view
    }

    func updateNSView(_ view: MouseTrackingMTKView, context: Context) {
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
        private let startTime = CACurrentMediaTime()
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
            guard let pipeline,
                  let commandQueue,
                  let descriptor = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
                return
            }
            var uniforms = Uniforms()
            uniforms.time = Float(CACurrentMediaTime() - startTime)
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

import Foundation
import MetalKit
import OSLog
import SwiftUI

final class MetalDisintegrationRenderer: NSObject, MTKViewDelegate {
    private enum RendererError: LocalizedError {
        case missingLibrary
        case missingFunctions

        var errorDescription: String? {
            switch self {
            case .missingLibrary:
                return "No Metal shader library could be loaded."
            case .missingFunctions:
                return "The Metal shader library is missing required disintegration entry points."
            }
        }
    }

    private static let logger = Logger(subsystem: "Snippets", category: "MetalDisintegrationRenderer")

    struct Uniforms {
        var sizeAndProgress: SIMD4<Float>
        var accentColor: SIMD4<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState!
    private var samplerState: MTLSamplerState!
    private var uniformsBuffer: MTLBuffer
    private weak var mtkView: MTKView?

    /// Wall-clock anchor of the running animation; also used to dedupe the
    /// repeated `beginAnimation` calls SwiftUI makes on unrelated updates.
    private(set) var animationStartDate: Date?
    private var startMediaTime: CFTimeInterval = 0
    private var duration: CFTimeInterval = 1

    /// When set, the renderer draws this progress and never advances (previews).
    private var fixedProgress: Float?

    var accentColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)

    private var inputImage: NSImage?
    private var inputTexture: MTLTexture?

    @MainActor
    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.mtkView = mtkView

        let bufferSize = MemoryLayout<Uniforms>.size
        guard let uniformsBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return nil }
        self.uniformsBuffer = uniformsBuffer

        super.init()

        mtkView.device = device
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm
        // Idle until beginAnimation()/showFixedProgress() picks a drive mode.
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true

        do {
            try buildPipeline()
        } catch {
            Self.logger.error("Failed to build Metal disintegration pipeline: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .notMipmapped
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Starts (or, for the same `startDate`, keeps running) a display-link
    /// driven animation. Progress is computed inside `draw(in:)` from
    /// `CACurrentMediaTime()`, so frame pacing is v-synced and completely
    /// decoupled from SwiftUI update cadence and main-thread layout work.
    @MainActor
    func beginAnimation(startDate: Date, duration: TimeInterval) {
        guard animationStartDate != startDate else { return }
        animationStartDate = startDate
        self.duration = max(duration, 0.01)
        let alreadyElapsed = max(Date().timeIntervalSince(startDate), 0)
        startMediaTime = CACurrentMediaTime() - alreadyElapsed
        fixedProgress = nil

        guard let view = mtkView else { return }
        view.preferredFramesPerSecond = 120
        view.enableSetNeedsDisplay = false
        view.isPaused = false
    }

    /// Renders a single static frame at the given progress (used by previews).
    @MainActor
    func showFixedProgress(_ progress: Float) {
        guard fixedProgress != progress else { return }
        fixedProgress = progress
        animationStartDate = nil

        guard let view = mtkView else { return }
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.setNeedsDisplay(view.bounds)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    private func currentProgress() -> Float {
        if let fixedProgress {
            return min(max(fixedProgress, 0), 1)
        }
        guard animationStartDate != nil else { return 0 }
        let elapsed = CACurrentMediaTime() - startMediaTime
        let linear = Float(min(max(elapsed / duration, 0), 1))
        // Global smoothstep ease: soft start, graceful settle.
        return linear * linear * (3 - 2 * linear)
    }

    func draw(in view: MTKView) {
        guard let texture = inputTexture,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        let progress = currentProgress()
        let size = view.drawableSize
        var uniforms = Uniforms(
            sizeAndProgress: SIMD4<Float>(Float(size.width), Float(size.height), progress, 0.0),
            accentColor: accentColor
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)

        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Finished: this frame rendered fully transparent output, stop the
        // display link. SwiftUI removes the overlay shortly after.
        if fixedProgress == nil, progress >= 1 {
            view.isPaused = true
        }
    }

    @MainActor
    private func buildPipeline() throws {
        let library = try makeShaderLibrary()
        guard let vertex = library.makeFunction(name: "vertex_main"),
              let fragment = library.makeFunction(name: "fragment_main") else {
            throw RendererError.missingFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let colorAttachment = descriptor.colorAttachments[0]!
        colorAttachment.pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm
        colorAttachment.isBlendingEnabled = true
        colorAttachment.sourceRGBBlendFactor = .one
        colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        colorAttachment.sourceAlphaBlendFactor = .one
        colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private func makeShaderLibrary() throws -> MTLLibrary {
        #if SWIFT_PACKAGE
        if let library = try? device.makeDefaultLibrary(bundle: .module) {
            return library
        }
        #endif

        if let library = device.makeDefaultLibrary() {
            return library
        }

        #if SWIFT_PACKAGE
        guard let shaderURL = Bundle.module.url(forResource: "DisintegrationShaders", withExtension: "metal.txt") else {
            throw RendererError.missingLibrary
        }
        #else
        guard let shaderURL = Bundle.main.url(forResource: "DisintegrationShaders", withExtension: "metal.txt") else {
            throw RendererError.missingLibrary
        }
        #endif

        let source = try String(contentsOf: shaderURL, encoding: .utf8)
        return try device.makeLibrary(source: source, options: nil)
    }

    func updateTexture(from nsImage: NSImage?) {
        if inputImage === nsImage {
            return
        }

        guard let nsImage,
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            inputImage = nil
            inputTexture = nil
            return
        }

        let loader = MTKTextureLoader(device: device)
        do {
            inputImage = nsImage
            inputTexture = try loader.newTexture(cgImage: cgImage, options: [.SRGB: false])
        } catch {
            Self.logger.error("Failed to create Metal texture: \(error.localizedDescription, privacy: .public)")
            inputImage = nil
            inputTexture = nil
        }
    }
}

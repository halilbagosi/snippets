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
    private var needsDisplay = true

    var progress: Float = 0 {
        didSet { needsDisplay = true }
    }

    var accentColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1) {
        didSet { needsDisplay = true }
    }

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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        updateUniforms(size: size)
    }

    private func updateUniforms(size: CGSize) {
        var uniforms = Uniforms(
            sizeAndProgress: SIMD4<Float>(Float(size.width), Float(size.height), progress, 0.0),
            accentColor: accentColor
        )
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
        needsDisplay = true
    }

    func draw(in view: MTKView) {
        guard needsDisplay,
              let texture = inputTexture,
              let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        updateUniforms(size: view.drawableSize)
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        needsDisplay = false
    }

    func updateTexture(from nsImage: NSImage?) {
        if inputImage === nsImage {
            return
        }

        guard let nsImage,
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            inputImage = nil
            inputTexture = nil
            needsDisplay = true
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
        needsDisplay = true
    }
}

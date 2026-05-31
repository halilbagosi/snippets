import Foundation
import MetalKit
import OSLog
import SwiftUI

final class MetalShatterRenderer: NSObject, MTKViewDelegate {
    private enum RendererError: LocalizedError {
        case missingLibrary
        case missingFunctions

        var errorDescription: String? {
            switch self {
            case .missingLibrary:
                return "No Metal shader library could be loaded."
            case .missingFunctions:
                return "The Metal shader library is missing required entry points."
            }
        }
    }

    private static let logger = Logger(subsystem: "Snippets", category: "MetalShatterRenderer")

    struct Uniforms {
        var sizeAndProgress: SIMD4<Float>
        var baseColor: SIMD4<Float>
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

    var baseColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1) {
        didSet { needsDisplay = true }
    }

    var accentColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1) {
        didSet { needsDisplay = true }
    }

    private var inputTexture: MTLTexture? = nil

    @MainActor
    init?(mtkView: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.mtkView = mtkView

        let bufferSize = MemoryLayout<Uniforms>.size
        guard let ub = device.makeBuffer(length: bufferSize, options: .storageModeShared) else { return nil }
        self.uniformsBuffer = ub

        super.init()

        mtkView.device = device
        mtkView.delegate = self
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.enableSetNeedsDisplay = true
        mtkView.isPaused = true

        do {
            try buildPipeline()
        } catch {
            Self.logger.error("Failed to build Metal shatter pipeline: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.mipFilter = .notMipmapped
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    @MainActor
    private func buildPipeline() throws {
        let library = try makeShaderLibrary()
        guard let vertex = library.makeFunction(name: "vertex_main"), let fragment = library.makeFunction(name: "fragment_main") else {
            throw RendererError.missingFunctions
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertex
        desc.fragmentFunction = fragment
        desc.colorAttachments[0].pixelFormat = mtkView?.colorPixelFormat ?? .bgra8Unorm
        pipelineState = try device.makeRenderPipelineState(descriptor: desc)
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
        guard let shaderURL = Bundle.module.url(forResource: "GlassBreakShaders", withExtension: "metal") else {
            throw RendererError.missingLibrary
        }
        #else
        guard let shaderURL = Bundle.main.url(forResource: "GlassBreakShaders", withExtension: "metal") else {
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
        var uniforms = Uniforms(sizeAndProgress: SIMD4<Float>(Float(size.width), Float(size.height), progress, 0.0), baseColor: baseColor, accentColor: accentColor)
        memcpy(uniformsBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.size)
        needsDisplay = true
    }

    func draw(in view: MTKView) {
        guard needsDisplay, let drawable = view.currentDrawable, let descriptor = view.currentRenderPassDescriptor else { return }
        updateUniforms(size: view.drawableSize)

        guard let commandBuffer = commandQueue.makeCommandBuffer(), let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        if let tex = inputTexture {
            encoder.setFragmentTexture(tex, index: 0)
        }
        encoder.setFragmentBuffer(uniformsBuffer, offset: 0, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        needsDisplay = false
    }

    func updateTexture(from nsImage: NSImage?) {
        guard let nsImage = nsImage else { inputTexture = nil; needsDisplay = true; return }
        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { inputTexture = nil; needsDisplay = true; return }
        let loader = MTKTextureLoader(device: device)
        do {
            let options: [MTKTextureLoader.Option: Any] = [.SRGB: false]
            inputTexture = try loader.newTexture(cgImage: cgImage, options: options)
        } catch {
            Self.logger.error("Failed to create Metal texture: \(error.localizedDescription, privacy: .public)")
            inputTexture = nil
        }
        needsDisplay = true
    }
}

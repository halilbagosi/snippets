import Metal
import Foundation

/// Compiled Metal pipeline for a shader snippet, plus the device it was
/// built on. Compilation runs off the main thread; see `MetalShaderSource`
/// for the snippet convention.
final class ShaderPipeline: @unchecked Sendable {
    let device: MTLDevice
    let pipelineState: MTLRenderPipelineState

    private init(device: MTLDevice, pipelineState: MTLRenderPipelineState) {
        self.device = device
        self.pipelineState = pipelineState
    }

    enum CompileError: LocalizedError {
        case noDevice
        case missingFunction(String)

        var errorDescription: String? {
            switch self {
            case .noDevice: return "No Metal device available."
            case .missingFunction(let name): return "Function `\(name)` not found in compiled library."
            }
        }
    }

    static func compile(_ code: String) -> Result<ShaderPipeline, Error> {
        compile(entry: code, helpers: [])
    }

    static func compile(entry: String, helpers: [String]) -> Result<ShaderPipeline, Error> {
        do {
            let prepared = try MetalShaderSource.prepare(entry: entry, helpers: helpers)
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw CompileError.noDevice
            }
            let library = try device.makeLibrary(source: prepared.source, options: nil)
            guard let vertex = library.makeFunction(name: prepared.vertexFunction) else {
                throw CompileError.missingFunction(prepared.vertexFunction)
            }
            guard let fragment = library.makeFunction(name: prepared.fragmentFunction) else {
                throw CompileError.missingFunction(prepared.fragmentFunction)
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
            return .success(ShaderPipeline(device: device, pipelineState: pipelineState))
        } catch {
            return .failure(error)
        }
    }
}

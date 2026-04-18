#if canImport(UIKit)
import Foundation
import UIKit
import Metal
import QuartzCore
import simd

@MainActor
public final class ChromeRenderer {
    public let metalLayer = CAMetalLayer()

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    public init?(context: MetalContext? = nil) {
        guard let ctx = context ?? .shared else { return nil }
        self.device = ctx.device
        self.commandQueue = ctx.commandQueue
        metalLayer.device = ctx.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = UIScreen.main.scale
        metalLayer.isOpaque = true
        self.pipeline = makePipeline()
    }

    public func start() {
        stop()
        startTime = CACurrentMediaTime()
        let link = CADisplayLink(target: ChromeDisplayProxy(owner: self),
                                 selector: #selector(ChromeDisplayProxy.tick))
        // Run at reduced frame rate — shimmer is slow, 15fps is plenty
        link.preferredFramesPerSecond = 15
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc fileprivate func tick(_ link: CADisplayLink) {
        render(time: Float(link.timestamp - startTime))
    }

    private func render(time: Float) {
        guard let pipeline,
              let drawable = metalLayer.nextDrawable() else { return }

        let size = metalLayer.drawableSize
        var uniforms = ChromeUniforms(
            viewport: SIMD2<Float>(Float(size.width), Float(size.height)),
            time: time
        )

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        withUnsafePointer(to: &uniforms) { ptr in
            enc.setVertexBytes(ptr, length: MemoryLayout<ChromeUniforms>.stride, index: 0)
            enc.setFragmentBytes(ptr, length: MemoryLayout<ChromeUniforms>.stride, index: 0)
        }
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func makePipeline() -> MTLRenderPipelineState? {
        if let lib = device.makeDefaultLibrary() {
            return makePipeline(with: lib)
        }
        #if SWIFT_PACKAGE
        if let lib = try? device.makeDefaultLibrary(bundle: .module) {
            return makePipeline(with: lib)
        }
        #endif
        return nil
    }

    private func makePipeline(with lib: MTLLibrary) -> MTLRenderPipelineState? {
        guard let v = lib.makeFunction(name: "chrome_vertex"),
              let f = lib.makeFunction(name: "chrome_fragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}

private struct ChromeUniforms {
    var viewport: SIMD2<Float>
    var time: Float
}

@MainActor
private final class ChromeDisplayProxy: NSObject {
    weak var owner: ChromeRenderer?
    init(owner: ChromeRenderer) { self.owner = owner }
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}
#endif

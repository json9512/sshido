#if canImport(UIKit)
import Foundation
import UIKit
import Metal
import QuartzCore
import simd
import SwiftTerm

@MainActor
public protocol TerminalGridSource: AnyObject {
    var cols: Int { get }
    var rows: Int { get }
    func charAt(col: Int, row: Int) -> (codepoint: UInt32, fg: SIMD4<Float>, bg: SIMD4<Float>)
    func cursorCell() -> (col: Int, row: Int)?
    var defaultBackground: SIMD4<Float> { get }
    var defaultForeground: SIMD4<Float> { get }
    func isSelected(col: Int, row: Int) -> Bool
    func widthAt(col: Int, row: Int) -> Int
}

public extension TerminalGridSource {
    func isSelected(col: Int, row: Int) -> Bool { false }
    func widthAt(col: Int, row: Int) -> Int { 1 }
}

func isWideCodepoint(_ cp: UInt32) -> Bool {
    switch cp {
    case 0x1100...0x115F,
         0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF,
         0x4E00...0x9FFF, 0xA000...0xA4CF, 0xAC00...0xD7A3,
         0xF900...0xFAFF, 0xFE30...0xFE4F, 0xFF00...0xFF60,
         0xFFE0...0xFFE6, 0x1F300...0x1F64F, 0x1F900...0x1F9FF,
         0x20000...0x2FFFD, 0x30000...0x3FFFD:
        return true
    default: return false
    }
}

private struct CellInstanceGPU {
    var origin: SIMD2<Float>
    var size: SIMD2<Float>
    var fg: SIMD4<Float>
    var bg: SIMD4<Float>
    var atlasOrigin: SIMD2<Float>
    var atlasSize: SIMD2<Float>
}

private struct UniformsGPU {
    var viewport: SIMD2<Float>
}

@MainActor
public final class MetalTerminalRenderer {
    public let metalLayer = CAMetalLayer()
    public weak var source: TerminalGridSource?

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipeline: MTLRenderPipelineState?
    private let sampler: MTLSamplerState
    private var atlas: GlyphAtlas
    public private(set) var fontSize: CGFloat
    private let scale: CGFloat

    private var instanceBuffer: MTLBuffer?
    private var instanceCapacity: Int = 0
    private var displayLink: CADisplayLink?
    public var dirty: Bool = true

    public init?(fontSize: CGFloat = 12, context: MetalContext? = nil) {
        guard let ctx = context ?? .shared else { return nil }
        self.device = ctx.device
        self.commandQueue = ctx.commandQueue
        self.scale = UIScreen.main.scale
        self.fontSize = fontSize
        self.atlas = GlyphAtlas(device: ctx.device, fontSize: fontSize, scale: scale)
        metalLayer.device = ctx.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = true
        metalLayer.contentsScale = scale
        let sd = MTLSamplerDescriptor()
        sd.minFilter = .linear
        sd.magFilter = .linear
        guard let s = ctx.device.makeSamplerState(descriptor: sd) else { return nil }
        self.sampler = s
        self.pipeline = makePipeline()
    }

    public func updateFontSize(_ pt: CGFloat) {
        let snapped = max(8, min(36, floor(pt)))
        guard snapped != fontSize else { return }
        fontSize = snapped
        atlas = GlyphAtlas(device: device, fontSize: fontSize, scale: scale)
        dirty = true
    }

    public var glyphMetrics: GlyphMetrics { atlas.metrics }

    public func start() {
        stop()
        let link = CADisplayLink(target: DisplayLinkProxy(owner: self),
                                 selector: #selector(DisplayLinkProxy.tick))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc fileprivate func tick() {
        guard dirty, let source else { return }
        render(source: source)
        dirty = false
    }

    public func setNeedsRender() { dirty = true }

    private func render(source: TerminalGridSource) {
        guard let pipeline,
              let drawable = metalLayer.nextDrawable() else { return }

        let cellW = atlas.metrics.cellWidth
        let cellH = atlas.metrics.cellHeight
        let cols = source.cols
        let rows = source.rows
        let count = cols * rows
        ensureInstanceBuffer(count: count)
        guard let instanceBuffer else { return }

        let ptr = instanceBuffer.contents().bindMemory(to: CellInstanceGPU.self, capacity: count)
        let cursor = source.cursorCell()
        let blankUV = atlas.uvRect(for: 0x20)
        for r in 0..<rows {
            var c = 0
            while c < cols {
                let cell = source.charAt(col: c, row: r)
                let isCursor = (cursor?.col == c && cursor?.row == r)
                let isSelected = source.isSelected(col: c, row: r)
                var bg = isCursor ? cell.fg : cell.bg
                var fg = isCursor ? cell.bg : cell.fg
                if isSelected && !isCursor {
                    bg = SIMD4<Float>(0.2, 0.45, 0.85, 1)
                    fg = SIMD4<Float>(1, 1, 1, 1)
                }
                let cp = cell.codepoint == 0 ? 0x20 : cell.codepoint
                var width = source.widthAt(col: c, row: r)
                if isCursor { width = 1 }
                let uv = atlas.uvRect(for: cp)
                let i = r * cols + c
                ptr[i] = CellInstanceGPU(
                    origin: SIMD2<Float>(Float(c) * Float(cellW),
                                         Float(r) * Float(cellH)),
                    size: SIMD2<Float>(Float(cellW) * Float(width), Float(cellH)),
                    fg: fg,
                    bg: bg,
                    atlasOrigin: SIMD2<Float>(Float(uv.minX), Float(uv.minY)),
                    atlasSize: SIMD2<Float>(Float(uv.width), Float(uv.height))
                )
                if width == 2 && c + 1 < cols {
                    let j = r * cols + c + 1
                    ptr[j] = CellInstanceGPU(
                        origin: SIMD2<Float>(Float(c + 1) * Float(cellW),
                                             Float(r) * Float(cellH)),
                        size: SIMD2<Float>(0, 0),
                        fg: fg,
                        bg: bg,
                        atlasOrigin: SIMD2<Float>(Float(blankUV.minX), Float(blankUV.minY)),
                        atlasSize: SIMD2<Float>(Float(blankUV.width), Float(blankUV.height))
                    )
                    c += 2
                } else {
                    c += 1
                }
            }
        }

        let drawableSize = metalLayer.drawableSize
        var uniforms = UniformsGPU(viewport: SIMD2<Float>(
            Float(drawableSize.width / scale),
            Float(drawableSize.height / scale)
        ))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        let bgC = source.defaultBackground
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(bgC.x), green: Double(bgC.y), blue: Double(bgC.z), alpha: 1
        )
        pass.colorAttachments[0].storeAction = .store

        guard let cmd = commandQueue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: pass) else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        withUnsafePointer(to: &uniforms) { ptr in
            enc.setVertexBytes(ptr, length: MemoryLayout<UniformsGPU>.stride, index: 1)
        }
        enc.setFragmentTexture(atlas.texture, index: 0)
        enc.setFragmentSamplerState(sampler, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: count)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func ensureInstanceBuffer(count: Int) {
        let needed = max(count, 1)
        if needed <= instanceCapacity, instanceBuffer != nil { return }
        let stride = MemoryLayout<CellInstanceGPU>.stride
        instanceBuffer = device.makeBuffer(length: stride * needed, options: .storageModeShared)
        instanceCapacity = needed
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
        guard let v = lib.makeFunction(name: "cell_vertex"),
              let f = lib.makeFunction(name: "cell_fragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = v
        desc.fragmentFunction = f
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: desc)
    }
}

@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var owner: MetalTerminalRenderer?
    init(owner: MetalTerminalRenderer) { self.owner = owner }
    @objc func tick() { owner?.tick() }
}
#endif

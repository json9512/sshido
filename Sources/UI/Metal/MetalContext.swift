#if canImport(UIKit)
import Metal

@MainActor
public final class MetalContext {
    public static let shared = MetalContext()

    public let device: MTLDevice
    public let commandQueue: MTLCommandQueue

    private init?() {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let q = dev.makeCommandQueue() else { return nil }
        self.device = dev
        self.commandQueue = q
    }
}
#endif

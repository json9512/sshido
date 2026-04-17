#if canImport(UIKit)
import Foundation

@MainActor
public final class BridgeStore {
    public static let shared = BridgeStore()

    private var bridges: [UUID: MetalTerminalBridge] = [:]

    public func bridge(for sessionID: UUID) -> MetalTerminalBridge? {
        bridges[sessionID]
    }

    public func adopt(_ bridge: MetalTerminalBridge, for sessionID: UUID) {
        bridges[sessionID] = bridge
    }

    public func remove(sessionID: UUID) {
        bridges.removeValue(forKey: sessionID)
    }
}
#endif

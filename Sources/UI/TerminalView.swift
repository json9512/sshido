#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoCore)
import sshidoCore
#endif

public struct TerminalView: UIViewRepresentable {
    let channel: SSHChannel
    let sessionID: UUID
    let onBridgeReady: ((TerminalBridge) -> Void)?

    public init(channel: SSHChannel, sessionID: UUID, onBridgeReady: ((TerminalBridge) -> Void)? = nil) {
        self.channel = channel
        self.sessionID = sessionID
        self.onBridgeReady = onBridgeReady
    }

    public func makeUIView(context: Context) -> UIView {
        let bridge = context.coordinator.bridge
        DispatchQueue.main.async {
            _ = bridge.view.becomeFirstResponder()
        }
        onBridgeReady?(bridge)
        return bridge.view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.bridge.refit()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(channel: channel, sessionID: sessionID)
    }

    @MainActor
    public final class Coordinator {
        let bridge: MetalTerminalBridge
        init(channel: SSHChannel, sessionID: UUID) {
            if let cached = BridgeStore.shared.bridge(for: sessionID) {
                self.bridge = cached
            } else {
                let fresh = MetalTerminalBridge(channel: channel)
                BridgeStore.shared.adopt(fresh, for: sessionID)
                self.bridge = fresh
            }
        }
    }
}
#endif

#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoCore)
import sshidoCore
#endif

public struct TerminalView: UIViewRepresentable {
    let channel: SSHChannel
    let onBridgeReady: ((TerminalBridge) -> Void)?

    public init(channel: SSHChannel, onBridgeReady: ((TerminalBridge) -> Void)? = nil) {
        self.channel = channel
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
        Coordinator(channel: channel)
    }

    @MainActor
    public final class Coordinator {
        let bridge: MetalTerminalBridge
        init(channel: SSHChannel) {
            self.bridge = MetalTerminalBridge(channel: channel)
        }
    }
}
#endif

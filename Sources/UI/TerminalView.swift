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
        guard let bridge = context.coordinator.bridge else {
            return Self.unavailableView()
        }
        DispatchQueue.main.async {
            _ = bridge.view.becomeFirstResponder()
        }
        onBridgeReady?(bridge)
        return bridge.view
    }

    public func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.bridge?.refit()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(channel: channel, sessionID: sessionID)
    }

    private static func unavailableView() -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let label = UILabel()
        label.text = "Terminal unavailable on this device (Metal renderer could not start)."
        label.textColor = .lightGray
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15)
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24),
        ])
        return container
    }

    @MainActor
    public final class Coordinator {
        let bridge: MetalTerminalBridge?
        init(channel: SSHChannel, sessionID: UUID) {
            if let cached = BridgeStore.shared.bridge(for: sessionID) {
                self.bridge = cached
            } else if let fresh = MetalTerminalBridge(channel: channel) {
                BridgeStore.shared.adopt(fresh, for: sessionID)
                self.bridge = fresh
            } else {
                self.bridge = nil
            }
        }
    }
}
#endif

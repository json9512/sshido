import XCTest
@testable import sshidoCore
import sshidoModels

@available(macOS 15.0, *)
final class AgentBridgeIntegrationTests: XCTestCase {
    private func bridge() throws -> (AgentBridge, String) {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["SSHIDO_AGENT_E2E_HOST"] else {
            throw XCTSkip("set SSHIDO_AGENT_E2E_HOST to run against a real host")
        }
        let keyPath = (env["SSHIDO_AGENT_E2E_KEY"] ?? "~/.ssh/id_ed25519")
            .replacingOccurrences(of: "~", with: NSHomeDirectory())
        let pem = try String(contentsOfFile: keyPath, encoding: .utf8)
        let channel = MetricsOnlySSHChannel(
            host: host, port: 22, user: env["SSHIDO_AGENT_E2E_USER"] ?? NSUserName(),
            auth: .privateKeyPEM(pem, passphrase: nil), hostKeyConfirm: { _ in .trust })
        return (AgentBridge(channel: channel), env["SSHIDO_AGENT_E2E_PODMAN"] ?? "podman")
    }

    func testAttachmentsDownloadIntact() async throws {
        let (bridge, podman) = try bridge()
        var attachments: [AgentChatMessage] = []
        for try await output in await bridge.events(podman: podman, since: 0) {
            guard case .event(let event) = output else { continue }
            if case .message(let m) = event, m.attachment != nil { attachments.append(m) }
            if case .ready = event { break }
        }
        try XCTSkipIf(attachments.isEmpty, "no attachments in this host's chat yet")
        for message in attachments {
            let data = try await bridge.runData(AgentHostCommands.file(podman: podman, messageID: message.id))
            XCTAssertEqual(Int64(data.count), message.attachment?.size, "size of \(message.attachment?.name ?? "")")
            if message.attachment?.mime == "image/png" {
                XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            }
        }
        await bridge.disconnect()
    }

    func testStatusAndChatRoundTrip() async throws {
        let (bridge, podman) = try bridge()
        let status = AgentHostStatus.parse(try await bridge.run(AgentHostCommands.status(podman: podman)))
        XCTAssertEqual(status.daemon, .running, "daemon must be running on the test host")

        var sawReady = false
        var replayedUpTo: Int64?
        var lastSeen: Int64 = 0
        var reply: AgentChatMessage?
        let deadline = Date().addingTimeInterval(180)
        for try await output in await bridge.events(podman: podman, since: 0) {
            guard case .event(let event) = output else { continue }
            if case .message(let m) = event { lastSeen = max(lastSeen, m.id) }
            if case .ready = event, replayedUpTo == nil {
                sawReady = true
                replayedUpTo = lastSeen
                try await bridge.send(.send("Reply with exactly the word pong. Do not start any workers."))
            }
            if case .message(let m) = event, let floor = replayedUpTo, m.id > floor,
               m.kind == .reply, m.text.lowercased().contains("pong") {
                reply = m
                break
            }
            if Date() > deadline { break }
        }
        await bridge.disconnect()
        XCTAssertTrue(sawReady)
        XCTAssertNotNil(reply, "no reply containing pong within 180 s")
    }
}

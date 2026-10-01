import XCTest
@testable import sshidoCore
import sshidoModels

final class SessionStoreChannelTests: XCTestCase {
    private let host = RemoteHost(name: "t", hostname: "h", username: "u")
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testInputTypedBeforeTheTerminalConnectsSurvives() async throws {
        let store = SessionStore(directory: directory)
        let session = await store.openSession(for: host, auth: .password("p"), title: "sign in")
        let typed = await store.ensureChannel(for: session, host: host, auth: .password("p"))
        try await typed.send(Array("claude auth login\r".utf8))
        let shown = await store.ensureChannel(for: session, host: host, auth: .password("p"))
        XCTAssertTrue(typed === shown)
        let citadel = try XCTUnwrap(shown as? CitadelSSHChannel)
        XCTAssertEqual(citadel.heldInput, [Array("claude auth login\r".utf8)])
    }

    func testClosedChannelIsReplaced() async {
        let store = SessionStore(directory: directory)
        let session = await store.openSession(for: host, auth: .password("p"))
        let first = await store.ensureChannel(for: session, host: host, auth: .password("p"))
        await first.disconnect()
        let second = await store.ensureChannel(for: session, host: host, auth: .password("p"))
        XCTAssertFalse(first === second)
    }
}

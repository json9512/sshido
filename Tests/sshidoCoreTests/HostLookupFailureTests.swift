import XCTest
@testable import sshidoCore

final class HostLookupFailureTests: XCTestCase {
    private let unresolvable = "sshido-lookup-test.invalid"

    func testTerminalChannelReportsHostNotFound() async {
        let ch = CitadelSSHChannel(host: unresolvable, port: 22, user: "x", auth: .password("p"))
        do {
            try await ch.connect()
            XCTFail("expected hostNotFound")
        } catch let e as SSHError {
            guard case .hostNotFound(let host, let port) = e else { return XCTFail("wrong error: \(e)") }
            XCTAssertEqual(host, unresolvable)
            XCTAssertEqual(port, 22)
        } catch {
            XCTFail("wrong error: \(error)")
        }
        let failure = await ch.connectFailure
        guard case .hostNotFound(let host, _)? = failure else { return XCTFail("connectFailure: \(String(describing: failure))") }
        XCTAssertEqual(host, unresolvable)
    }

    func testExecChannelReportsHostNotFound() async {
        let ch = MetricsOnlySSHChannel(host: unresolvable, port: 2222, user: "x", auth: .password("p"))
        do {
            try await ch.connect()
            XCTFail("expected hostNotFound")
        } catch let e as SSHError {
            guard case .hostNotFound(let host, let port) = e else { return XCTFail("wrong error: \(e)") }
            XCTAssertEqual(host, unresolvable)
            XCTAssertEqual(port, 2222)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testOtherFailuresAreNotHostNotFound() async {
        let ch = CitadelSSHChannel(host: "127.0.0.1", port: 22, user: "x",
                                   auth: .privateKeyPEM("not a key", passphrase: nil))
        try? await ch.connect()
        let failure = await ch.connectFailure
        guard case .invalidKey? = failure else { return XCTFail("connectFailure: \(String(describing: failure))") }
        XCTAssertNil(SSHError.hostLookupFailure(SSHError.transport("Connection refused")))
    }

    func testMessagePointsAtTheVPNApp() {
        let message = SSHError.hostNotFound(host: "mac.tail0000.ts.net", port: 22).description
        XCTAssertTrue(message.contains("mac.tail0000.ts.net"))
        XCTAssertTrue(message.contains("Tailscale"))
        XCTAssertTrue(message.contains("VPN"))
    }
}

import XCTest
@testable import sshidoModels
@testable import sshidoCore

final class AgentProfileTests: XCTestCase {
    func testBuiltinsUnique() {
        let ids = AgentProfile.builtins.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

func testRemoteHostCodable() throws {
        let host = RemoteHost(name: "test", hostname: "example.com", username: "root")
        let data = try JSONEncoder().encode(host)
        let decoded = try JSONDecoder().decode(RemoteHost.self, from: data)
        XCTAssertEqual(decoded.hostname, "example.com")
        XCTAssertEqual(decoded.port, 22)
    }

    func testRemoteHostnameRoundTripsAndOlderHostsDecodeWithout() throws {
        let host = RemoteHost(name: "Mac", hostname: "mac.tail.ts.net", username: "u", remoteHostname: "json-mbp")
        let decoded = try JSONDecoder().decode(RemoteHost.self, from: JSONEncoder().encode(host))
        XCTAssertEqual(decoded.remoteHostname, "json-mbp")
        let legacy = #"{"id":"\#(UUID().uuidString)","name":"Pi","hostname":"192.168.200.103","username":"json"}"#
        XCTAssertNil(try JSONDecoder().decode(RemoteHost.self, from: Data(legacy.utf8)).remoteHostname)
    }

    func testInvalidKeyRejected() async {
        let ch = CitadelSSHChannel(
            host: "127.0.0.1", port: 22, user: "x",
            auth: .privateKeyPEM("not a key", passphrase: nil)
        )
        do {
            try await ch.connect()
            XCTFail("expected invalidKey error")
        } catch let e as SSHError {
            if case .invalidKey = e {} else { XCTFail("wrong error: \(e)") }
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

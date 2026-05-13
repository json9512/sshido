import XCTest
import NIOSSH
@testable import sshidoCore

final class HostKeyFingerprintTests: XCTestCase {
    // Test vector generated locally via:
    //   ssh-keygen -t ed25519 -N "" -C "tofu-test" -f /tmp/sshido-test-key
    //   ssh-keygen -l -f /tmp/sshido-test-key.pub
    // If our fingerprint output ever diverges from `ssh-keygen -l -f`, this
    // test breaks — that's the property users rely on when cross-checking
    // against what their server admin tells them.
    private let publicKeyString = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAII4G9D8Wd/3KoDOdMyh1ys3rnvpaoAPchBlavR1lpHZm tofu-test"
    private let expectedFingerprint = "SHA256:j0uMjiTaS3jPL0RryPRCDViovAf3Bm0J6S7ghM0qDtI"

    func testFingerprintMatchesSSHKeygenOutput() throws {
        let key = try NIOSSHPublicKey(openSSHPublicKey: publicKeyString)
        let got = HostKeyFingerprint.sha256(key)
        XCTAssertEqual(got, expectedFingerprint)
    }

    func testFingerprintHasSHA256Prefix() throws {
        let key = try NIOSSHPublicKey(openSSHPublicKey: publicKeyString)
        XCTAssertTrue(HostKeyFingerprint.sha256(key).hasPrefix("SHA256:"))
    }

    func testFingerprintIsBase64WithoutPadding() throws {
        let key = try NIOSSHPublicKey(openSSHPublicKey: publicKeyString)
        let fp = HostKeyFingerprint.sha256(key)
        let body = fp.dropFirst("SHA256:".count)
        XCTAssertFalse(body.contains("="), "OpenSSH strips '=' padding")
    }
}

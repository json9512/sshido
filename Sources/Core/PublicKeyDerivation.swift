import Foundation
import Citadel
import Crypto

public enum PublicKeyDerivation {
    public struct GeneratedKey: Sendable {
        public let privateKeyPEM: String
        public let publicKeyString: String
    }

    public static func generateEd25519(comment: String = "sshido") -> GeneratedKey {
        let priv = Curve25519.Signing.PrivateKey()
        let pubRaw = Array(priv.publicKey.rawRepresentation)
        let privRaw = Array(priv.rawRepresentation) + pubRaw

        var pubWire = [UInt8]()
        writeString(&pubWire, "ssh-ed25519")
        writeString(&pubWire, pubRaw)

        let check: UInt32 = .random(in: 0...UInt32.max)
        var privSection = [UInt8]()
        var checkBE = check.bigEndian
        withUnsafeBytes(of: &checkBE) { privSection.append(contentsOf: $0) }
        withUnsafeBytes(of: &checkBE) { privSection.append(contentsOf: $0) }
        writeString(&privSection, "ssh-ed25519")
        writeString(&privSection, pubRaw)
        writeString(&privSection, privRaw)
        writeString(&privSection, comment)
        var pad: UInt8 = 1
        while privSection.count % 8 != 0 {
            privSection.append(pad)
            pad += 1
        }

        var blob = [UInt8]()
        blob.append(contentsOf: Array("openssh-key-v1\0".utf8))
        writeString(&blob, "none")
        writeString(&blob, "none")
        writeString(&blob, "")
        var one = UInt32(1).bigEndian
        withUnsafeBytes(of: &one) { blob.append(contentsOf: $0) }
        writeString(&blob, pubWire)
        writeString(&blob, privSection)

        let b64 = Data(blob).base64EncodedString()
        var pem = "-----BEGIN OPENSSH PRIVATE KEY-----\n"
        for i in stride(from: 0, to: b64.count, by: 70) {
            let start = b64.index(b64.startIndex, offsetBy: i)
            let end = b64.index(start, offsetBy: min(70, b64.count - i))
            pem += b64[start..<end] + "\n"
        }
        pem += "-----END OPENSSH PRIVATE KEY-----\n"

        let pub = "ssh-ed25519 " + Data(pubWire).base64EncodedString() + " " + comment
        return GeneratedKey(privateKeyPEM: pem, publicKeyString: pub)
    }

    public static func openSSHPublicKey(fromPEM pem: String, comment: String = "sshido") -> String? {
        guard let ed = try? Curve25519.Signing.PrivateKey(sshEd25519: pem) else { return nil }
        var buf = [UInt8]()
        writeString(&buf, "ssh-ed25519")
        writeString(&buf, Array(ed.publicKey.rawRepresentation))
        return "ssh-ed25519 " + Data(buf).base64EncodedString() + " " + comment
    }

    public static func installCommand(forPublicKey pub: String) -> String {
        let escaped = pub.replacingOccurrences(of: "'", with: "'\\''")
        return "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '\(escaped)' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    }

    private static func writeString(_ buf: inout [UInt8], _ s: String) {
        writeString(&buf, Array(s.utf8))
    }

    private static func writeString(_ buf: inout [UInt8], _ bytes: [UInt8]) {
        var len = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &len) { buf.append(contentsOf: $0) }
        buf.append(contentsOf: bytes)
    }
}

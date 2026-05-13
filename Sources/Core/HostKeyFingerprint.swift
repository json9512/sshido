import Foundation
import Crypto
import NIOCore
import NIOSSH

// Output matches `ssh-keygen -l -f host_key.pub` — `NIOSSHPublicKey.write(to:)`
// emits the canonical SSH wire format (length-prefixed algorithm identifier
// + key bytes) that OpenSSH itself SHA256s for its fingerprint display.
public enum HostKeyFingerprint {
    public static func sha256(_ key: NIOSSHPublicKey) -> String {
        var buffer = ByteBufferAllocator().buffer(capacity: 256)
        key.write(to: &buffer)
        let bytes = Array(buffer.readableBytesView)
        let digest = SHA256.hash(data: bytes)
        let base64 = Data(digest).base64EncodedString()
        // OpenSSH strips '=' padding from the SHA256 fingerprint display.
        let stripped = base64.split(separator: "=").first.map(String.init) ?? base64
        return "SHA256:\(stripped)"
    }
}

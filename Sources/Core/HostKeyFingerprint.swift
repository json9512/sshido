import Foundation
import Crypto
import NIOCore
import NIOSSH

/// Compute the OpenSSH-compatible SHA256 fingerprint of a host's public
/// key. The output matches what `ssh-keygen -l -f host_key.pub` prints
/// on the server side — users can cross-reference the fingerprint shown
/// in the iOS prompt against the value their server admin gives them.
///
/// Implementation: NIOSSH's `write(to:)` writes the canonical SSH wire
/// format with a length-prefixed algorithm identifier and key bytes.
/// That same byte sequence is what OpenSSH hashes for its fingerprint.
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

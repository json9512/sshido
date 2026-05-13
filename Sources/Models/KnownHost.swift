import Foundation

/// A host whose SSH host-key fingerprint has been seen and trusted at
/// least once. Storage is keyed by `(host, port)` rather than by
/// `RemoteHost.id` so trust survives `RemoteHost` rename/delete and so
/// ad-hoc connections (no `RemoteHost` record) can also accrue trust.
public struct KnownHost: Codable, Hashable, Sendable, Identifiable {
    public let host: String
    public let port: Int
    public let fingerprint: String   // "SHA256:..." — matches `ssh-keygen -l -f`
    public let firstSeen: Date
    public var lastSeen: Date

    public init(host: String, port: Int, fingerprint: String, firstSeen: Date = Date(), lastSeen: Date = Date()) {
        self.host = host
        self.port = port
        self.fingerprint = fingerprint
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }

    public var id: String { "\(host):\(port)" }
}

/// A challenge the SSH layer surfaces to the UI when first connecting
/// to an unknown host, or when the presented host key doesn't match
/// the one we've previously trusted.
public enum HostKeyChallenge: Hashable, Sendable, Identifiable {
    case unknownHost(host: String, port: Int, fingerprint: String)
    case mismatch(host: String, port: Int, expected: String, presented: String)

    public var host: String {
        switch self {
        case .unknownHost(let h, _, _), .mismatch(let h, _, _, _): return h
        }
    }

    public var port: Int {
        switch self {
        case .unknownHost(_, let p, _), .mismatch(_, let p, _, _): return p
        }
    }

    public var id: String {
        switch self {
        case .unknownHost(let h, let p, let f):
            return "unknown:\(h):\(p):\(f)"
        case .mismatch(let h, let p, let exp, let pres):
            return "mismatch:\(h):\(p):\(exp):\(pres)"
        }
    }
}

public enum HostKeyDecision: Sendable {
    /// First-connect: trust and store. Mismatch: replace stored fingerprint and continue.
    case trust
    /// First-connect: abort the connection. Mismatch: same.
    case reject
}

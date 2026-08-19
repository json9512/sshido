import Foundation

/// Local-network addresses are only reachable through the connected host,
/// so they open via an SSH tunnel instead of directly.
public enum BrowserURLResolver {
    public enum Target: Equatable, Sendable {
        case direct(URL)
        case tunneled(open: URL, remoteHost: String, port: Int)
    }

    public static func resolve(_ raw: String) -> Target? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hasHTTPScheme = trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://")
        guard hasHTTPScheme || !trimmed.contains("://") else { return nil }
        let withScheme = hasHTTPScheme ? trimmed : "http://" + trimmed
        guard var comps = URLComponents(string: withScheme),
              let scheme = comps.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = comps.host?.lowercased(), !host.isEmpty
        else { return nil }

        guard isHostLocal(host) else {
            if withScheme != trimmed { comps.scheme = "https" }
            return comps.url.map { .direct($0) }
        }

        let port = comps.port ?? (scheme == "https" ? 443 : 80)
        let remoteHost = (host == "localhost" || host == "::1") ? "127.0.0.1" : host
        comps.host = "127.0.0.1"
        comps.port = port
        guard let open = comps.url else { return nil }
        return .tunneled(open: open, remoteHost: remoteHost, port: port)
    }

    static func isHostLocal(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (127, _), (10, _), (192, 168), (169, 254): return true
        case (172, 16...31): return true
        default: return false
        }
    }
}

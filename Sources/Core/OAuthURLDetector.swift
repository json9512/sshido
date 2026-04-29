import Foundation

public struct OAuthTunnelTarget: Sendable, Equatable {
    public let port: Int
    public let originalURL: URL

    public init(port: Int, originalURL: URL) {
        self.port = port
        self.originalURL = originalURL
    }
}

public enum OAuthURLDetector {
    public static func detect(_ input: String) -> OAuthTunnelTarget? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let target = detectStructured(trimmed) { return target }
        return detectByPattern(trimmed)
    }

    private static func detectStructured(_ input: String) -> OAuthTunnelTarget? {
        guard let url = URL(string: input),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let redirect = comps.queryItems?.first(where: { $0.name == "redirect_uri" })?.value
        else { return nil }
        return parseRedirectURI(redirect).map { OAuthTunnelTarget(port: $0, originalURL: url) }
    }

    private static func detectByPattern(_ input: String) -> OAuthTunnelTarget? {
        let pattern = #"redirect_uri=http(?:%3A|:)(?:%2F%2F|//)(?:localhost|127\.0\.0\.1)(?:%3A|:)(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              match.numberOfRanges >= 2,
              let portRange = Range(match.range(at: 1), in: input),
              let port = Int(input[portRange]),
              (1...65535).contains(port),
              let url = URL(string: input),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return OAuthTunnelTarget(port: port, originalURL: url)
    }

    public static func parseRedirectURI(_ redirect: String) -> Int? {
        guard let url = URL(string: redirect),
              (url.scheme?.lowercased() == "http"),
              let host = url.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1",
              let port = url.port,
              (1...65535).contains(port)
        else { return nil }
        return port
    }
}

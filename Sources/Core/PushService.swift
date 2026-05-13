import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor PushService {
    public static let shared = PushService()

    private let stateURL: URL
    private let settingsURL: URL
    private let session: URLSession
    public private(set) var deviceToken: String?
    public private(set) var subscription: PushSubscription?
    public private(set) var settings: PushSettings

    public init(session: URLSession = .shared) {
        self.session = session
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.stateURL = dir.appendingPathComponent("push-subscription.json")
        self.settingsURL = dir.appendingPathComponent("push-settings.json")
        if let data = try? Data(contentsOf: stateURL),
           let s = try? JSONDecoder().decode(PushSubscription.self, from: data) {
            self.subscription = s
        }
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(PushSettings.self, from: data) {
            self.settings = s
        } else {
            self.settings = .default
        }
    }

    public func update(deviceToken: String) async {
        let isNew = deviceToken != self.deviceToken
        self.deviceToken = deviceToken
        if isNew {
            do {
                try await syncSubscription()
            } catch {
                Log.push.error("syncSubscription on token update failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public func setServerURL(_ url: String) async throws {
        let trimmed = try Self.validateServerURL(url)
        self.settings = PushSettings(serverURL: trimmed)
        try persistSettings()
        self.subscription = nil
        do {
            try FileManager.default.removeItem(at: stateURL)
        } catch CocoaError.fileNoSuchFile {
            // First-time setup: no existing file to remove.
        } catch {
            Log.push.error("remove stale push-subscription.json failed: \(String(describing: error), privacy: .public)")
        }
        try await syncSubscription()
    }

    public func resubscribe() async throws {
        try await syncSubscription()
    }

    public func clearSubscription() throws {
        self.subscription = nil
        do {
            try FileManager.default.removeItem(at: stateURL)
        } catch CocoaError.fileNoSuchFile {
            // Already gone.
        } catch {
            Log.push.error("clearSubscription remove failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func syncSubscription() async throws {
        guard let token = deviceToken else { throw PushError.noDeviceToken }
        guard let endpoint = URL(string: settings.serverURL + "/subscribe") else {
            throw PushError.invalidServerURL
        }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try JSONSerialization.data(withJSONObject: ["deviceToken": token])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw PushError.serverRejected
        }
        struct R: Decodable { let id: String; let notifyURL: String }
        let decoded = try JSONDecoder().decode(R.self, from: data)
        guard Self.isValidNotifyURL(decoded.notifyURL) else {
            throw PushError.invalidNotifyURL
        }
        let sub = PushSubscription(
            serverURL: settings.serverURL,
            subscriberID: decoded.id,
            notifyURL: decoded.notifyURL
        )
        self.subscription = sub
        try persistSubscription()
    }

    /// Notify URLs returned by /subscribe end up interpolated into the
    /// agent-setup prompt that users paste into Claude Code. A malicious
    /// relay can otherwise smuggle prompt-injection content (newlines,
    /// shell snippets) into that prompt. This whitelist matches what the
    /// real relay actually returns: scheme + host (no whitespace) + the
    /// literal /n/ path + a URL-safe id.
    /// Normalize and validate a user-supplied push relay URL. We allow both
    /// http and https (Tailscale and LAN deployments without TLS are a real
    /// use case), but reject any other scheme so file:// / javascript: /
    /// ssh:// can't slip past `URL(string:)`'s lax acceptance. A non-empty
    /// host is also required.
    static func validateServerURL(_ url: String) throws -> String {
        var trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty,
              let parsed = URL(string: trimmed),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = parsed.host, !host.isEmpty
        else {
            throw PushError.invalidServerURL
        }
        return trimmed
    }

    static let notifyURLPattern = #"^https?://[^/\s]+/n/[A-Za-z0-9_-]+$"#

    static func isValidNotifyURL(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 512 else { return false }
        return s.range(of: notifyURLPattern, options: .regularExpression) != nil
    }

    private func persistSubscription() throws {
        guard let subscription else { return }
        let data = try JSONEncoder().encode(subscription)
        try data.write(to: stateURL, options: .atomic)
    }

    private func persistSettings() throws {
        let data = try JSONEncoder().encode(settings)
        try data.write(to: settingsURL, options: .atomic)
    }
}

public enum PushError: Error, LocalizedError {
    case invalidServerURL
    case serverRejected
    case noDeviceToken
    case invalidNotifyURL

    public var errorDescription: String? {
        switch self {
        case .invalidServerURL: return "Invalid push server URL"
        case .serverRejected:   return "Push server refused subscribe"
        case .noDeviceToken:    return "No device APNs token yet — enable notifications in iOS Settings → sshido, then force-quit + reopen."
        case .invalidNotifyURL: return "The push server returned an unexpected notify URL. Verify you trust the server at Settings → Push notifications → Push server URL."
        }
    }
}

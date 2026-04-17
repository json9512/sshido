import Foundation

public enum OAuthCallbackDelivery {
    public enum Failure: Error, CustomStringConvertible {
        case notALocalhostCallback
        case transport(String)

        public var description: String {
            switch self {
            case .notALocalhostCallback:
                return "Not a localhost callback URL"
            case .transport(let m):
                return m
            }
        }
    }

    public static func deliver(callbackURL: String, through sshChannel: SSHChannel) async throws {
        guard let url = URL(string: callbackURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              (url.scheme?.lowercased() == "http"),
              let host = url.host?.lowercased(),
              host == "localhost" || host == "127.0.0.1",
              let port = url.port
        else { throw Failure.notALocalhostCallback }

        var pathAndQuery = url.path.isEmpty ? "/" : url.path
        if let q = url.query { pathAndQuery += "?" + q }

        let request =
            "GET \(pathAndQuery) HTTP/1.1\r\n" +
            "Host: 127.0.0.1:\(port)\r\n" +
            "User-Agent: sshido-oauth-callback/1\r\n" +
            "Accept: */*\r\n" +
            "Connection: close\r\n\r\n"

        let fwd: SSHForwardedChannel
        do {
            fwd = try await sshChannel.openForwardedChannel(host: "127.0.0.1", port: port)
        } catch {
            throw Failure.transport("open direct-tcpip: \(error)")
        }

        do {
            try await fwd.send(Data(request.utf8))
        } catch {
            await fwd.close()
            throw Failure.transport("send callback: \(error)")
        }

        let drain = Task {
            for await _ in fwd.inbound { }
        }
        _ = await drain.value
        await fwd.close()
    }
}

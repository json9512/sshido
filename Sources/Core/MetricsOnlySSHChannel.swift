import Foundation
import Citadel
import NIOSSH
#if canImport(sshidoModels)
import sshidoModels
#endif

public final class MetricsOnlySSHChannel: SSHChannel, @unchecked Sendable {
    private var onClose: (@Sendable () -> Void)?

    private let host: String
    private let port: Int
    private let user: String
    private let auth: SSHAuth
    private let hostKeyConfirm: HostKeyConfirmCallback
    private var client: SSHClient?
    private var connected = false

    public init(
        host: String,
        port: Int,
        user: String,
        auth: SSHAuth,
        hostKeyConfirm: @escaping HostKeyConfirmCallback = { _ in .reject }
    ) {
        self.host = host
        self.port = port
        self.user = user
        self.auth = auth
        self.hostKeyConfirm = hostKeyConfirm
    }

    public var isConnected: Bool { get async { connected } }

    public func setOutputHandler(onData: @escaping @Sendable (Data) async -> Void,
                                 onClose: @escaping @Sendable () -> Void) {
        self.onClose = onClose
    }

    public func connect() async throws {
        let method: SSHAuthenticationMethod
        switch auth {
        case .password(let pw):
            method = .passwordBased(username: user, password: pw)
        case .privateKeyPEM(let pem, let passphrase):
            method = try CitadelSSHChannel.authFromPEM(user: user, pem: pem, passphrase: passphrase)
        }
        let validator = TOFUHostKeyValidator(host: host, port: port, confirm: hostKeyConfirm)
        do {
            let sshClient = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: method,
                hostKeyValidator: .custom(validator),
                reconnect: .never
            )
            self.client = sshClient
            self.connected = true
        } catch let e as SSHError {
            throw e
        } catch let e as HostKeyValidationError {
            switch e {
            case .mismatch(let h, let p, let expected, let presented):
                throw SSHError.hostKeyChanged(host: h, port: p, expected: expected, presented: presented)
            case .rejectedByUser(let h, let p):
                throw SSHError.hostKeyRejected(host: h, port: p)
            }
        } catch {
            let msg = String(describing: error)
            if msg.lowercased().contains("auth") {
                throw SSHError.authFailed(msg)
            }
            throw SSHError.transport(msg)
        }
    }

    public func disconnect() async {
        if let c = client {
            try? await c.close()
        }
        client = nil
        connected = false
        onClose?()
    }

    public func send(_ bytes: [UInt8]) async throws {
        throw SSHError.transport("send not supported on metrics channel")
    }

    public func resize(cols: Int, rows: Int) async throws {}

    public func executeCommand(_ command: String) async throws -> Data {
        guard let client else { throw SSHError.notConnected }
        do {
            let buf = try await client.executeCommand(command, mergeStreams: false, inShell: false)
            return Data(buffer: buf)
        } catch let e as SSHError {
            throw e
        } catch {
            throw SSHError.transport("exec failed: \(error)")
        }
    }
}

import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH
#if canImport(sshidoModels)
import sshidoModels
#endif

public enum SSHAuth: Sendable {
    case password(String)
    case privateKeyPEM(String, passphrase: String?)
}

public final class CitadelSSHChannel: SSHChannel, @unchecked Sendable {
    public let output: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    private let host: String
    private let port: Int
    private let user: String
    private let auth: SSHAuth
    private let bootstrapCommand: String?
    private let environment: [String: String]
    private var initialCols: Int
    private var initialRows: Int

    private var client: SSHClient?
    private var stdin: TTYStdinWriter?
    private var ttyTask: Task<Void, Error>?
    private var connected = false
    private var pendingInput: [[UInt8]] = []
    private let pendingByteLimit = 4096

    public init(host: String, port: Int, user: String, auth: SSHAuth,
                cols: Int = 80, rows: Int = 24,
                bootstrapCommand: String? = nil,
                environment: [String: String] = [:]) {
        self.host = host
        self.port = port
        self.user = user
        self.auth = auth
        self.bootstrapCommand = bootstrapCommand
        self.environment = environment
        self.initialCols = cols
        self.initialRows = rows
        var cont: AsyncStream<Data>.Continuation!
        self.output = AsyncStream(bufferingPolicy: .unbounded) { cont = $0 }
        self.continuation = cont
    }

    public var isConnected: Bool { get async { connected } }

    public func setInitialSize(cols: Int, rows: Int) {
        guard !connected else { return }
        if cols > 0 { initialCols = cols }
        if rows > 0 { initialRows = rows }
    }

    public func connect() async throws {
        let method: SSHAuthenticationMethod
        switch auth {
        case .password(let pw):
            method = .passwordBased(username: user, password: pw)
        case .privateKeyPEM(let pem, let passphrase):
            method = try Self.authFromPEM(user: user, pem: pem, passphrase: passphrase)
        }

        let sshClient: SSHClient
        do {
            sshClient = try await withThrowingTaskGroup(of: SSHClient.self) { group in
                group.addTask {
                    try await SSHClient.connect(
                        host: self.host,
                        port: self.port,
                        authenticationMethod: method,
                        hostKeyValidator: .acceptAnything(),
                        reconnect: .never
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: 15_000_000_000)
                    throw SSHError.transport("connection timed out after 15s (host unreachable or blocked)")
                }
                let first = try await group.next()!
                group.cancelAll()
                return first
            }
        } catch let e as SSHError {
            throw e
        } catch {
            let msg = String(describing: error)
            if msg.contains("authentication") || msg.contains("Auth") {
                throw SSHError.authFailed(msg)
            }
            throw SSHError.transport(msg)
        }
        self.client = sshClient
        self.connected = true

        ttyTask = Task { [weak self, sshClient] in
            guard let self else { return }
            do {
                guard #available(iOS 17.0, macOS 15.0, *) else {
                    throw SSHError.transport("requires iOS 17 / macOS 15")
                }
                let ptyRequest = SSHChannelRequestEvent.PseudoTerminalRequest(
                    wantReply: true,
                    term: "xterm-256color",
                    terminalCharacterWidth: self.initialCols,
                    terminalRowHeight: self.initialRows,
                    terminalPixelWidth: 0,
                    terminalPixelHeight: 0,
                    terminalModes: SSHTerminalModes([:])
                )
                try await sshClient.withPTY(ptyRequest) { inbound, outbound in
                    self.stdin = outbound
                    await self.flushPendingInput()
                    var bootstrapPieces: [String] = []
                    for (k, v) in self.environment {
                        bootstrapPieces.append("export \(k)=\(Self.shellQuote(v))")
                    }
                    if let cmd = self.bootstrapCommand {
                        bootstrapPieces.append(cmd)
                    }
                    if !bootstrapPieces.isEmpty {
                        let line = bootstrapPieces.joined(separator: "; ") + "\r"
                        var buf = ByteBufferAllocator().buffer(capacity: line.utf8.count)
                        buf.writeString(line)
                        try await outbound.write(buf)
                    }
                    for try await chunk in inbound {
                        switch chunk {
                        case .stdout(let buf):
                            self.emit(Data(buffer: buf))
                        case .stderr(let buf):
                            self.emit(Data(buffer: buf))
                        }
                    }
                }
            } catch {
                self.emit("\r\n[session ended: \(error)]\r\n")
            }
            self.connected = false
            self.continuation.finish()
        }
    }

    public func disconnect() async {
        ttyTask?.cancel()
        ttyTask = nil
        stdin = nil
        if let c = client { try? await c.close() }
        client = nil
        connected = false
        continuation.finish()
    }

    public func send(_ bytes: [UInt8]) async throws {
        guard let w = stdin else {
            queueInput(bytes)
            return
        }
        var buf = ByteBufferAllocator().buffer(capacity: bytes.count)
        buf.writeBytes(bytes)
        try await w.write(buf)
    }

    private func queueInput(_ bytes: [UInt8]) {
        let totalPending = pendingInput.reduce(0) { $0 + $1.count }
        if totalPending + bytes.count > pendingByteLimit { return }
        pendingInput.append(bytes)
    }

    private func flushPendingInput() async {
        guard let w = stdin, !pendingInput.isEmpty else { return }
        let drained = pendingInput
        pendingInput.removeAll(keepingCapacity: false)
        for chunk in drained {
            var buf = ByteBufferAllocator().buffer(capacity: chunk.count)
            buf.writeBytes(chunk)
            try? await w.write(buf)
        }
    }

    public func resize(cols: Int, rows: Int) async throws {
        guard let w = stdin else { return }
        try await w.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }

    public func uploadFile(data: Data, remotePath: String) async throws {
        guard let client else { throw SSHError.notConnected }
        let sftp: SFTPClient
        do {
            sftp = try await client.openSFTP()
        } catch {
            throw SSHError.transport("sftp open: \(error)")
        }
        let dirPath = (remotePath as NSString).deletingLastPathComponent
        if !dirPath.isEmpty, dirPath != "/" {
            _ = try? await sftp.createDirectory(atPath: dirPath)
        }
        do {
            try await sftp.withFile(
                filePath: remotePath,
                flags: [.write, .create, .truncate]
            ) { file in
                try await file.write(ByteBuffer(bytes: Array(data)))
            }
        } catch {
            try? await sftp.close()
            throw SSHError.transport("sftp write: \(error)")
        }
        try? await sftp.close()
    }

    private func emit(_ s: String) { continuation.yield(Data(s.utf8)) }
    private func emit(_ d: Data)   { continuation.yield(d) }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func authFromPEM(user: String, pem: String, passphrase: String?) throws -> SSHAuthenticationMethod {
        let decryption = passphrase.flatMap { $0.data(using: .utf8) }
        if pem.contains("BEGIN OPENSSH PRIVATE KEY") {
            if let ed = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: decryption) {
                return .ed25519(username: user, privateKey: ed)
            }
            if let rsa = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryption) {
                return .rsa(username: user, privateKey: rsa)
            }
            throw SSHError.invalidKey("OpenSSH key is neither ed25519 nor RSA, or is encrypted with unsupported cipher")
        }
        if pem.contains("BEGIN RSA PRIVATE KEY") {
            if let rsa = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: decryption) {
                return .rsa(username: user, privateKey: rsa)
            }
        }
        throw SSHError.invalidKey("unsupported key format — expected OpenSSH (ed25519/RSA) or PKCS#1 RSA PEM")
    }
}

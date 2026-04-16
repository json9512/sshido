import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor HostStore {
    public static let shared = HostStore()

    private let url: URL
    private var cached: [RemoteHost] = []

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("hosts.json")
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([RemoteHost].self, from: data) {
            self.cached = arr
        }
    }

    public func all() -> [RemoteHost] { cached }

    public func upsert(_ host: RemoteHost) throws {
        if let idx = cached.firstIndex(where: { $0.id == host.id }) {
            cached[idx] = host
        } else {
            cached.append(host)
        }
        try persist()
    }

    public func remove(id: UUID) throws {
        cached.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(cached)
        try data.write(to: url, options: .atomic)
    }
}

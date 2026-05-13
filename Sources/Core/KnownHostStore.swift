import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor KnownHostStore {
    public static let shared = KnownHostStore()

    private let fileURL: URL
    private var entries: [String: KnownHost]
    private var loaded = false

    public init(fileURL: URL? = nil) {
        if let url = fileURL {
            self.fileURL = url
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("sshido", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("known-hosts.json")
        }
        self.entries = [:]
    }

    private func ensureLoaded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let array = try? JSONDecoder().decode([KnownHost].self, from: data) else {
            return
        }
        for entry in array {
            entries[Self.key(host: entry.host, port: entry.port)] = entry
        }
    }

    public func get(host: String, port: Int) -> KnownHost? {
        ensureLoaded()
        return entries[Self.key(host: host, port: port)]
    }

    public func all() -> [KnownHost] {
        ensureLoaded()
        return Array(entries.values).sorted { $0.host < $1.host }
    }

    // No-op if `(host, port)` already exists — callers use `replace` to overwrite.
    public func add(host: String, port: Int, fingerprint: String, at date: Date = Date()) throws {
        ensureLoaded()
        let k = Self.key(host: host, port: port)
        guard entries[k] == nil else { return }
        entries[k] = KnownHost(host: host, port: port, fingerprint: fingerprint, firstSeen: date, lastSeen: date)
        try persist()
    }

    public func replace(host: String, port: Int, fingerprint: String, at date: Date = Date()) throws {
        ensureLoaded()
        let k = Self.key(host: host, port: port)
        entries[k] = KnownHost(host: host, port: port, fingerprint: fingerprint, firstSeen: date, lastSeen: date)
        try persist()
    }

    // Best-effort: persist failure here just leaves a stale timestamp,
    // it must not break the connect path.
    public func touchLastSeen(host: String, port: Int, at date: Date = Date()) {
        ensureLoaded()
        let k = Self.key(host: host, port: port)
        guard var existing = entries[k] else { return }
        existing.lastSeen = date
        entries[k] = existing
        try? persist()
    }

    public func remove(host: String, port: Int) throws {
        ensureLoaded()
        entries.removeValue(forKey: Self.key(host: host, port: port))
        try persist()
    }

    private func persist() throws {
        let arr = Array(entries.values).sorted { $0.host < $1.host }
        let data = try JSONEncoder().encode(arr)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func key(host: String, port: Int) -> String {
        "\(host):\(port)"
    }
}

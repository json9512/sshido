import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor CustomShortcutStore {
    public static let shared = CustomShortcutStore()

    private let url: URL
    public private(set) var shortcuts: [CustomShortcut]

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("shortcuts.json")
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([CustomShortcut].self, from: data) {
            self.shortcuts = arr
        } else {
            self.shortcuts = CustomShortcut.agentDefaults
            if let data = try? JSONEncoder().encode(self.shortcuts) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    public func add(_ s: CustomShortcut) throws {
        shortcuts.append(s)
        try persist()
    }

    public func remove(id: UUID) throws {
        shortcuts.removeAll { $0.id == id }
        try persist()
    }

    public func update(_ s: CustomShortcut) throws {
        if let i = shortcuts.firstIndex(where: { $0.id == s.id }) {
            shortcuts[i] = s
            try persist()
        }
    }

    public func move(from source: IndexSet, to destination: Int) throws {
        shortcuts.move(fromOffsets: source, toOffset: destination)
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(shortcuts)
        try data.write(to: url, options: .atomic)
    }
}

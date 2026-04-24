import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public actor ShortcutGroupStore {
    public static let shared = ShortcutGroupStore()

    private let url: URL
    private let legacyFlatURL: URL
    public private(set) var groups: [ShortcutGroup]

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("shortcut-groups.json")
        self.legacyFlatURL = dir.appendingPathComponent("shortcuts.json")

        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ShortcutGroup].self, from: data) {
            self.groups = decoded
            return
        }

        var seeded: [ShortcutGroup] = []

        if let data = try? Data(contentsOf: legacyFlatURL),
           let legacy = try? JSONDecoder().decode([CustomShortcut].self, from: data),
           !legacy.isEmpty {
            seeded.append(ShortcutGroup(label: "Custom",
                                        sfSymbol: "command",
                                        shortcuts: legacy))
        } else {
            seeded.append(ShortcutGroup.claudeSeed)
        }
        seeded.append(ShortcutGroup.tmuxSeed)

        self.groups = seeded
        if let data = try? JSONEncoder().encode(seeded) {
            try? data.write(to: url, options: .atomic)
        }
    }

    public func addGroup(_ g: ShortcutGroup) throws {
        groups.append(g)
        try persist()
    }

    public func removeGroup(id: UUID) throws {
        groups.removeAll { $0.id == id }
        try persist()
    }

    public func updateGroup(_ g: ShortcutGroup) throws {
        guard let i = groups.firstIndex(where: { $0.id == g.id }) else { return }
        groups[i] = g
        try persist()
    }

    public func moveGroup(from source: IndexSet, to destination: Int) throws {
        groups.move(fromOffsets: source, toOffset: destination)
        try persist()
    }

    public func addShortcut(toGroup groupId: UUID, _ sc: CustomShortcut) throws {
        guard let i = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[i].shortcuts.append(sc)
        try persist()
    }

    public func removeShortcut(fromGroup groupId: UUID, shortcutId: UUID) throws {
        guard let i = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[i].shortcuts.removeAll { $0.id == shortcutId }
        try persist()
    }

    public func updateShortcut(inGroup groupId: UUID, _ sc: CustomShortcut) throws {
        guard let i = groups.firstIndex(where: { $0.id == groupId }) else { return }
        guard let j = groups[i].shortcuts.firstIndex(where: { $0.id == sc.id }) else { return }
        groups[i].shortcuts[j] = sc
        try persist()
    }

    public func moveShortcut(inGroup groupId: UUID,
                             from source: IndexSet,
                             to destination: Int) throws {
        guard let i = groups.firstIndex(where: { $0.id == groupId }) else { return }
        groups[i].shortcuts.move(fromOffsets: source, toOffset: destination)
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(groups)
        try data.write(to: url, options: .atomic)
    }
}

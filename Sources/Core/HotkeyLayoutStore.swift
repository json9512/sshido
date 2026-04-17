import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public extension Notification.Name {
    static let hotkeyLayoutChanged = Notification.Name("sshido.hotkeyLayoutChanged")
}

public actor HotkeyLayoutStore {
    public static let shared = HotkeyLayoutStore()

    private let url: URL
    public private(set) var order: [String]

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("hotkey-order.json")
        if let data = try? Data(contentsOf: url),
           let arr = try? JSONDecoder().decode([String].self, from: data) {
            self.order = arr
        } else {
            self.order = []
        }
    }

    public func ordered(builtins: [HotkeyButton], customs: [CustomShortcut]) -> [BarItem] {
        let items: [BarItem] = builtins.map(BarItem.builtin) + customs.map(BarItem.custom)
        let byId = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var result: [BarItem] = []
        var seen = Set<String>()
        for id in order {
            if let item = byId[id] {
                result.append(item)
                seen.insert(id)
            }
        }
        for item in items where !seen.contains(item.id) {
            result.append(item)
        }
        return result
    }

    public func setOrder(_ ids: [String]) throws {
        order = ids
        try persist()
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(order)
        try data.write(to: url, options: .atomic)
    }
}

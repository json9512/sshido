import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public extension Notification.Name {
    static let sshidoAppearanceChanged = Notification.Name("sshido.appearanceChanged")
}

public actor AppearanceStore {
    public static let shared = AppearanceStore()

    private let url: URL
    public private(set) var appearance: TerminalAppearance

    public init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sshido", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.url = dir.appendingPathComponent("appearance.json")
        if let data = try? Data(contentsOf: url),
           let a = try? JSONDecoder().decode(TerminalAppearance.self, from: data) {
            self.appearance = a
        } else {
            self.appearance = .default
        }
    }

    public func set(_ new: TerminalAppearance) throws {
        self.appearance = new
        try persist()
        NotificationCenter.default.post(name: .sshidoAppearanceChanged, object: nil)
    }

    private func persist() throws {
        let data = try JSONEncoder().encode(appearance)
        try data.write(to: url, options: .atomic)
    }
}

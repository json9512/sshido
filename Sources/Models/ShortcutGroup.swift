import Foundation

public struct ShortcutGroup: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var label: String
    public var sfSymbol: String?
    public var shortcuts: [CustomShortcut]

    public init(id: UUID = UUID(),
                label: String,
                sfSymbol: String? = nil,
                shortcuts: [CustomShortcut] = []) {
        self.id = id
        self.label = label
        self.sfSymbol = sfSymbol
        self.shortcuts = shortcuts
    }
}

public extension ShortcutGroup {
    static let tmuxSeed = ShortcutGroup(
        label: "TMUX",
        sfSymbol: "rectangle.split.2x1",
        shortcuts: [
            .init(label: "Prefix",      bytes: [0x02]),
            .init(label: "Split |",     bytes: [0x02, 0x25]),
            .init(label: "Split -",     bytes: [0x02, 0x22]),
            .init(label: "New window",  bytes: [0x02, 0x63]),
            .init(label: "Next window", bytes: [0x02, 0x6e]),
            .init(label: "Prev window", bytes: [0x02, 0x70]),
            .init(label: "Zoom pane",   bytes: [0x02, 0x7a]),
            .init(label: "Kill pane",   bytes: [0x02, 0x78]),
            .init(label: "Detach",      bytes: [0x02, 0x64]),
            .init(label: "Command",     bytes: [0x02, 0x3a]),
            .init(label: "Pane ↑",      bytes: [0x02, 0x1b, 0x5b, 0x41]),
            .init(label: "Pane ↓",      bytes: [0x02, 0x1b, 0x5b, 0x42]),
            .init(label: "Pane ←",      bytes: [0x02, 0x1b, 0x5b, 0x44]),
            .init(label: "Pane →",      bytes: [0x02, 0x1b, 0x5b, 0x43]),
            .init(label: "Mouse on",
                  bytes: [0x74, 0x6d, 0x75, 0x78, 0x20,
                          0x73, 0x65, 0x74, 0x20, 0x2d, 0x67, 0x20,
                          0x6d, 0x6f, 0x75, 0x73, 0x65, 0x20,
                          0x6f, 0x6e, 0x0d])
        ]
    )

    static let claudeSeed = ShortcutGroup(
        label: "Claude",
        sfSymbol: "sparkles",
        shortcuts: CustomShortcut.agentDefaults
    )
}

public enum GroupIconCatalog {
    public static let symbols: [String] = [
        "square.grid.2x2",
        "rectangle.split.2x1",
        "sparkles",
        "terminal",
        "keyboard",
        "command",
        "chevron.left.forwardslash.chevron.right",
        "bolt",
        "bookmark",
        "tag",
        "folder",
        "wrench.and.screwdriver",
        "hammer",
        "gauge",
        "cpu",
        "network"
    ]
}

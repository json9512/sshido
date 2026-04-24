import Foundation

public enum HotkeyKind: Codable, Hashable, Sendable {
    case rawBytes([UInt8])
    case modifier(Modifier)

    public enum Modifier: String, Codable, Hashable, Sendable, CaseIterable {
        case shift, ctrl, alt, cmd
        public var label: String {
            switch self {
            case .shift: return "⇧"
            case .ctrl:  return "⌃"
            case .alt:   return "⌥"
            case .cmd:   return "⌘"
            }
        }
    }
}

public struct HotkeyButton: Hashable, Codable, Sendable, Identifiable {
    public var id: String { label }
    public let label: String
    public let kind: HotkeyKind
    public let sfSymbol: String?

    public init(label: String, kind: HotkeyKind, sfSymbol: String? = nil) {
        self.label = label
        self.kind = kind
        self.sfSymbol = sfSymbol
    }

    public init(label: String, bytes: [UInt8], sfSymbol: String? = nil) {
        self.init(label: label, kind: .rawBytes(bytes), sfSymbol: sfSymbol)
    }

    public static let defaults: [HotkeyButton] = [
        HotkeyButton(label: "Esc", bytes: [0x1b], sfSymbol: "escape"),
        HotkeyButton(label: "Tab", bytes: [0x09], sfSymbol: "arrow.right.to.line"),
        HotkeyButton(label: "⇧Tab", bytes: [0x1b, 0x5b, 0x5a]),
        HotkeyButton(label: "Space", bytes: [0x20], sfSymbol: "space"),
        HotkeyButton(label: "⌃C",  bytes: [0x03]),
        HotkeyButton(label: "⌃D",  bytes: [0x04]),
        HotkeyButton(label: "⌃O",  bytes: [0x0f]),
        HotkeyButton(label: "↑",   bytes: [0x1b, 0x5b, 0x41]),
        HotkeyButton(label: "↓",   bytes: [0x1b, 0x5b, 0x42]),
        HotkeyButton(label: "←",   bytes: [0x1b, 0x5b, 0x44]),
        HotkeyButton(label: "→",   bytes: [0x1b, 0x5b, 0x43])
    ]
}

public extension CustomShortcut {
    static let agentDefaults: [CustomShortcut] = [
        .init(label: "/",        bytes: [0x2f]),
        .init(label: "#",        bytes: [0x23]),
        .init(label: "?",        bytes: [0x3f]),
        .init(label: "Esc Esc",  bytes: [0x1b, 0x1b]),
        .init(label: "⌃R",       bytes: [0x12]),
        .init(label: "⌃L",       bytes: [0x0c]),
        .init(label: "⌃A",       bytes: [0x01]),
        .init(label: "⌃E",       bytes: [0x05]),
        .init(label: "⌃W",       bytes: [0x17])
    ]
}

public enum BarItem: Identifiable, Hashable, Sendable {
    case builtin(HotkeyButton)
    case group(ShortcutGroup)

    public var id: String {
        switch self {
        case .builtin(let b): return "b:\(b.label)"
        case .group(let g):   return "g:\(g.id.uuidString)"
        }
    }

    public var label: String {
        switch self {
        case .builtin(let b): return b.label
        case .group(let g):   return g.label
        }
    }
}

public struct CustomShortcut: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var label: String
    public var bytes: [UInt8]

    public init(id: UUID = UUID(), label: String, bytes: [UInt8]) {
        self.id = id
        self.label = label
        self.bytes = bytes
    }

    public init(id: UUID = UUID(), label: String, text: String) {
        self.init(id: id, label: label, bytes: Array(text.utf8))
    }
}

public struct AgentProfile: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    public static let claudeCode = AgentProfile(name: "Claude Code")
    public static let codex      = AgentProfile(name: "Codex")
    public static let shell      = AgentProfile(name: "Shell / tmux")

    public static let builtins: [AgentProfile] = [.claudeCode, .codex, .shell]

    public var icon: String {
        switch name {
        case "Claude Code": return "sparkles"
        case "Codex":       return "chevron.left.forwardslash.chevron.right"
        case "Shell / tmux": return "terminal"
        default: return "command"
        }
    }

    public var tint: String {
        switch name {
        case "Claude Code": return "orange"
        case "Codex":       return "purple"
        case "Shell / tmux": return "gray"
        default: return "blue"
        }
    }
}

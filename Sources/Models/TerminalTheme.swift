import Foundation

/// A named terminal theme. Currently customises the background + default
/// foreground pair; ANSI 16-color palette remains at SwiftTerm defaults.
/// Expanding the palette is a follow-up (requires calling SwiftTerm's
/// `Terminal.installColors` on every theme switch).
public struct TerminalTheme: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let isPremium: Bool
    /// Background hex without the leading '#'. Six hex chars.
    public let bgHex: String
    /// Default foreground hex.
    public let fgHex: String

    public init(id: String, name: String, isPremium: Bool, bgHex: String, fgHex: String) {
        self.id = id
        self.name = name
        self.isPremium = isPremium
        self.bgHex = bgHex
        self.fgHex = fgHex
    }

    /// Decode hex to a 4-float tuple (RGB + alpha=1). Returns nil if the
    /// string isn't a well-formed 6-char hex value.
    public static func rgb(fromHex hex: String) -> (r: Float, g: Float, b: Float)? {
        var h = hex
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6,
              let v = UInt32(h, radix: 16) else { return nil }
        let r = Float((v >> 16) & 0xFF) / 255
        let g = Float((v >> 8) & 0xFF) / 255
        let b = Float(v & 0xFF) / 255
        return (r, g, b)
    }
}

/// Catalog of bundled themes. The id is persisted in `TerminalAppearance`,
/// so never rename or renumber these IDs without a migration.
public enum TerminalThemes {
    public static let classicDark = TerminalTheme(
        id: "classic-dark", name: "Classic Dark", isPremium: false,
        bgHex: "232325", fgHex: "E0E0E0"
    )
    public static let highContrast = TerminalTheme(
        id: "high-contrast", name: "High Contrast", isPremium: false,
        bgHex: "000000", fgHex: "FFFFFF"
    )
    public static let solarizedLight = TerminalTheme(
        id: "solarized-light", name: "Solarized Light", isPremium: false,
        bgHex: "FDF6E3", fgHex: "586E75"
    )

    // Premium palettes — flagship community palettes. Credits belong
    // to their respective designers; attribution will appear in the
    // in-app About / credits view once it's added.
    public static let dracula = TerminalTheme(
        id: "dracula", name: "Dracula", isPremium: true,
        bgHex: "282A36", fgHex: "F8F8F2"
    )
    public static let catppuccinMocha = TerminalTheme(
        id: "catppuccin-mocha", name: "Catppuccin Mocha", isPremium: true,
        bgHex: "1E1E2E", fgHex: "CDD6F4"
    )
    public static let nord = TerminalTheme(
        id: "nord", name: "Nord", isPremium: true,
        bgHex: "2E3440", fgHex: "D8DEE9"
    )
    public static let tokyoNight = TerminalTheme(
        id: "tokyo-night", name: "Tokyo Night", isPremium: true,
        bgHex: "1A1B26", fgHex: "A9B1D6"
    )
    public static let gruvboxDark = TerminalTheme(
        id: "gruvbox-dark", name: "Gruvbox Dark", isPremium: true,
        bgHex: "282828", fgHex: "EBDBB2"
    )

    public static let all: [TerminalTheme] = [
        classicDark, highContrast, solarizedLight,
        dracula, catppuccinMocha, nord, tokyoNight, gruvboxDark,
    ]

    public static let defaultID = classicDark.id

    public static func theme(for id: String) -> TerminalTheme? {
        all.first { $0.id == id }
    }
}

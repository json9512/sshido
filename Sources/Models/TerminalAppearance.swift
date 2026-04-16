import Foundation

public enum TerminalTheme: String, CaseIterable, Codable, Hashable, Sendable {
    case nord
    case solarizedDark
    case pureBlack
    case light

    public var displayName: String {
        switch self {
        case .nord:          return "Nord"
        case .solarizedDark: return "Solarized Dark"
        case .pureBlack:     return "Pure Black"
        case .light:         return "Light"
        }
    }

    public var jsObject: String {
        switch self {
        case .nord: return """
        {"background":"#2e3440","foreground":"#d8dee9","cursor":"#d8dee9",
         "selectionBackground":"#434c5e",
         "black":"#3b4252","red":"#bf616a","green":"#a3be8c","yellow":"#ebcb8b",
         "blue":"#81a1c1","magenta":"#b48ead","cyan":"#88c0d0","white":"#e5e9f0",
         "brightBlack":"#4c566a","brightRed":"#bf616a","brightGreen":"#a3be8c",
         "brightYellow":"#ebcb8b","brightBlue":"#81a1c1","brightMagenta":"#b48ead",
         "brightCyan":"#8fbcbb","brightWhite":"#eceff4"}
        """
        case .solarizedDark: return """
        {"background":"#002b36","foreground":"#839496","cursor":"#93a1a1",
         "selectionBackground":"#073642",
         "black":"#073642","red":"#dc322f","green":"#859900","yellow":"#b58900",
         "blue":"#268bd2","magenta":"#d33682","cyan":"#2aa198","white":"#eee8d5",
         "brightBlack":"#002b36","brightRed":"#cb4b16","brightGreen":"#586e75",
         "brightYellow":"#657b83","brightBlue":"#839496","brightMagenta":"#6c71c4",
         "brightCyan":"#93a1a1","brightWhite":"#fdf6e3"}
        """
        case .pureBlack: return """
        {"background":"#000000","foreground":"#e0e0e0","cursor":"#ffffff",
         "selectionBackground":"#3a3a3a",
         "black":"#000000","red":"#cd3131","green":"#0dbc79","yellow":"#e5e510",
         "blue":"#2472c8","magenta":"#bc3fbc","cyan":"#11a8cd","white":"#e5e5e5",
         "brightBlack":"#666666","brightRed":"#f14c4c","brightGreen":"#23d18b",
         "brightYellow":"#f5f543","brightBlue":"#3b8eea","brightMagenta":"#d670d6",
         "brightCyan":"#29b8db","brightWhite":"#ffffff"}
        """
        case .light: return """
        {"background":"#fafafa","foreground":"#383a42","cursor":"#526fff",
         "selectionBackground":"#d8dee9",
         "black":"#383a42","red":"#e45649","green":"#50a14f","yellow":"#c18401",
         "blue":"#4078f2","magenta":"#a626a4","cyan":"#0184bc","white":"#fafafa",
         "brightBlack":"#a0a1a7","brightRed":"#e45649","brightGreen":"#50a14f",
         "brightYellow":"#c18401","brightBlue":"#4078f2","brightMagenta":"#a626a4",
         "brightCyan":"#0184bc","brightWhite":"#ffffff"}
        """
        }
    }
}

public struct TerminalAppearance: Codable, Hashable, Sendable {
    public var theme: TerminalTheme
    public var fontSize: Int

    public init(theme: TerminalTheme = .pureBlack, fontSize: Int = 12) {
        self.theme = theme
        self.fontSize = fontSize
    }

    public static let `default` = TerminalAppearance()
}

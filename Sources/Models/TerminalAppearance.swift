import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum ReturnKeyStyle: String, Codable, Hashable, Sendable, CaseIterable {
    case defaultReturn
    case send
    case done
    case go
    case newline

    public var displayName: String {
        switch self {
        case .defaultReturn: return "Return (↵)"
        case .send:          return "Send"
        case .done:          return "Done"
        case .go:            return "Go"
        case .newline:       return "New line"
        }
    }

    #if canImport(SwiftUI)
    public var submitLabel: SubmitLabel {
        switch self {
        case .defaultReturn: return .return
        case .send:          return .send
        case .done:          return .done
        case .go:            return .go
        case .newline:       return .return
        }
    }
    #endif
}

public struct TerminalAppearance: Codable, Hashable, Sendable {
    public var fontSize: Int
    public var returnKeyStyle: ReturnKeyStyle
    public var showMascotCompanion: Bool
    /// ID of the active terminal theme from `TerminalThemes`. Stored as
    /// a string so the catalog can grow without migration.
    public var themeID: String
    public var voiceDictationEnabled: Bool
    /// BCP-47 locale for on-device dictation; empty means the system locale.
    public var dictationLocaleID: String

    public init(fontSize: Int = 12,
                returnKeyStyle: ReturnKeyStyle = .defaultReturn,
                showMascotCompanion: Bool = true,
                themeID: String = TerminalThemes.defaultID,
                voiceDictationEnabled: Bool = true,
                dictationLocaleID: String = "") {
        self.fontSize = fontSize
        self.returnKeyStyle = returnKeyStyle
        self.showMascotCompanion = showMascotCompanion
        self.themeID = themeID
        self.voiceDictationEnabled = voiceDictationEnabled
        self.dictationLocaleID = dictationLocaleID
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? 12
        self.returnKeyStyle = try c.decodeIfPresent(ReturnKeyStyle.self, forKey: .returnKeyStyle) ?? .defaultReturn
        self.showMascotCompanion = try c.decodeIfPresent(Bool.self, forKey: .showMascotCompanion) ?? true
        self.themeID = try c.decodeIfPresent(String.self, forKey: .themeID) ?? TerminalThemes.defaultID
        self.voiceDictationEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceDictationEnabled) ?? true
        self.dictationLocaleID = try c.decodeIfPresent(String.self, forKey: .dictationLocaleID) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case fontSize, returnKeyStyle, showMascotCompanion, themeID
        case voiceDictationEnabled, dictationLocaleID
    }

    public var theme: TerminalTheme {
        TerminalThemes.theme(for: themeID) ?? TerminalThemes.classicDark
    }

    public static let `default` = TerminalAppearance()
}

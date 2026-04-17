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

    public init(fontSize: Int = 12,
                returnKeyStyle: ReturnKeyStyle = .defaultReturn) {
        self.fontSize = fontSize
        self.returnKeyStyle = returnKeyStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.fontSize = try c.decodeIfPresent(Int.self, forKey: .fontSize) ?? 12
        self.returnKeyStyle = try c.decodeIfPresent(ReturnKeyStyle.self, forKey: .returnKeyStyle) ?? .defaultReturn
    }

    private enum CodingKeys: String, CodingKey {
        case fontSize, returnKeyStyle
    }

    public static let `default` = TerminalAppearance()
}

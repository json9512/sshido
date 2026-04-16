import Foundation

public enum VoiceLanguage: String, Codable, CaseIterable, Sendable {
    case auto, en, ko
    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .en:   return "English"
        case .ko:   return "한국어"
        }
    }
    public var localeIdentifier: String? {
        switch self {
        case .auto: return nil
        case .en:   return "en-US"
        case .ko:   return "ko-KR"
        }
    }
}

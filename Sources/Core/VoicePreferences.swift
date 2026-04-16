import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public final class VoicePreferences: @unchecked Sendable {
    public static let shared = VoicePreferences()
    private let key = "sshido.voice.language"

    public var language: VoiceLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: key),
               let v = VoiceLanguage(rawValue: raw) {
                return v
            }
            return .auto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

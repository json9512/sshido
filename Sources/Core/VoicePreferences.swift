import Foundation
#if canImport(sshidoModels)
import sshidoModels
#endif

public final class VoicePreferences: @unchecked Sendable {
    public static let shared = VoicePreferences()
    private let key = "sshido.voice.language"
    private let autoSendKey = "sshido.voice.autoSend"
    private let aiTranslateKey = "sshido.voice.aiTranslate"
    private let privacyKey = "sshido.privacyAccepted"

    public var privacyAccepted: Bool {
        get { UserDefaults.standard.bool(forKey: privacyKey) }
        set { UserDefaults.standard.set(newValue, forKey: privacyKey) }
    }

    public var autoSend: Bool {
        get { UserDefaults.standard.bool(forKey: autoSendKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoSendKey) }
    }

    public var aiTranslate: Bool {
        get {
            if UserDefaults.standard.object(forKey: aiTranslateKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: aiTranslateKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: aiTranslateKey) }
    }

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

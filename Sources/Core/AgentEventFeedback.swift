#if canImport(UIKit)
import Foundation
import UIKit
import CoreHaptics

/// Events that happen in an sshido session worth nudging the user about.
/// Fired from the push-notification presentation path and any future
/// in-app event sources (session died, reconnected, etc.).
public enum AgentEvent: String, Sendable {
    /// Agent is asking for user input (Claude Notification hook).
    case needsInput
    /// Agent finished its task successfully (Stop hook).
    case finishedOk
    /// Agent finished with an error (StopFailure hook).
    case finishedError

    public init?(pushEvent: String?) {
        switch pushEvent?.lowercased() {
        case "notification": self = .needsInput
        case "stop":          self = .finishedOk
        case "stopfailure":   self = .finishedError
        default:              return nil
        }
    }
}

/// A feedback theme defines how the app *feels* when agent events
/// arrive — which haptic pattern to fire for each event type. Premium
/// themes unlock more expressive patterns.
///
/// Sound themes are planned but require bundled audio assets; for the
/// first release we ship haptic-only themes and let iOS handle push
/// notification sounds via the user's system-level setting.
public struct FeedbackTheme: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let isPremium: Bool
    /// Intensity per event, 0 = no haptic, 1 = light, 2 = medium, 3 = heavy.
    public let needsInputIntensity: Int
    public let finishedOkIntensity: Int
    public let finishedErrorIntensity: Int
    /// Whether the event fires a double-tap instead of a single tap.
    public let doubleTapOnFinish: Bool

    public init(id: String, name: String, isPremium: Bool,
                needsInput: Int, finishedOk: Int, finishedError: Int,
                doubleTapOnFinish: Bool = false) {
        self.id = id
        self.name = name
        self.isPremium = isPremium
        self.needsInputIntensity = needsInput
        self.finishedOkIntensity = finishedOk
        self.finishedErrorIntensity = finishedError
        self.doubleTapOnFinish = doubleTapOnFinish
    }

    func intensity(for event: AgentEvent) -> Int {
        switch event {
        case .needsInput:    return needsInputIntensity
        case .finishedOk:    return finishedOkIntensity
        case .finishedError: return finishedErrorIntensity
        }
    }

    func usesDoubleTap(for event: AgentEvent) -> Bool {
        guard doubleTapOnFinish else { return false }
        return event == .finishedOk || event == .finishedError
    }
}

public enum FeedbackThemes {
    public static let off = FeedbackTheme(
        id: "off", name: "Off", isPremium: false,
        needsInput: 0, finishedOk: 0, finishedError: 0
    )
    public static let subtle = FeedbackTheme(
        id: "subtle", name: "Subtle", isPremium: false,
        needsInput: 1, finishedOk: 1, finishedError: 2
    )

    // Premium — more expressive personalities.
    public static let energetic = FeedbackTheme(
        id: "energetic", name: "Energetic", isPremium: true,
        needsInput: 2, finishedOk: 2, finishedError: 3,
        doubleTapOnFinish: true
    )
    public static let intense = FeedbackTheme(
        id: "intense", name: "Intense", isPremium: true,
        needsInput: 3, finishedOk: 3, finishedError: 3,
        doubleTapOnFinish: true
    )
    public static let zen = FeedbackTheme(
        id: "zen", name: "Zen", isPremium: true,
        needsInput: 1, finishedOk: 1, finishedError: 1
    )

    public static let all: [FeedbackTheme] = [off, subtle, energetic, intense, zen]
    public static let defaultID = subtle.id

    public static func theme(for id: String) -> FeedbackTheme? {
        all.first { $0.id == id }
    }
}

@MainActor
public final class FeedbackPreferences {
    public static let shared = FeedbackPreferences()
    private let key = "sshido.feedback.themeID"

    public var themeID: String {
        get { UserDefaults.standard.string(forKey: key) ?? FeedbackThemes.defaultID }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    public var theme: FeedbackTheme {
        FeedbackThemes.theme(for: themeID) ?? FeedbackThemes.subtle
    }
}

/// Plays the haptic/sound corresponding to an agent event, using the
/// currently-selected feedback theme. Silently falls back to a simple
/// UIImpactFeedbackGenerator when CHHapticEngine is unavailable.
@MainActor
public final class AgentEventFeedback {
    public static let shared = AgentEventFeedback()

    private init() {}

    public func fire(_ event: AgentEvent) {
        var theme = FeedbackPreferences.shared.theme
        // Defensive: strip premium if entitlement lapses.
        if theme.isPremium && !Entitlements.shared.hasPlus {
            theme = FeedbackThemes.subtle
        }
        let intensity = theme.intensity(for: event)
        guard intensity > 0 else { return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = {
            switch intensity {
            case 1: return .light
            case 2: return .medium
            default: return .heavy
            }
        }()
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
        if theme.usesDoubleTap(for: event) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                gen.impactOccurred()
            }
        }
    }
}
#endif

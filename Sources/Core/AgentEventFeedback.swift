#if canImport(UIKit)
import Foundation
import UIKit
import CoreHaptics

/// Events that happen in an sshido session worth nudging the user about.
public enum AgentEvent: String, Sendable {
    case needsInput
    case finishedOk
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

/// One event in a haptic pattern. Time is relative to pattern start.
/// Sharpness 0 feels round/subtle; 1 feels crisp/clicky. Duration nil =
/// transient (a single click); duration >0 = continuous rumble.
public struct HapticBeat: Sendable {
    public let time: TimeInterval
    public let intensity: Float
    public let sharpness: Float
    public let duration: TimeInterval?

    public init(time: TimeInterval, intensity: Float, sharpness: Float, duration: TimeInterval? = nil) {
        self.time = time
        self.intensity = intensity
        self.sharpness = sharpness
        self.duration = duration
    }
}

public struct FeedbackTheme: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let patterns: [AgentEvent: [HapticBeat]]

    func pattern(for event: AgentEvent) -> [HapticBeat] {
        patterns[event] ?? []
    }
}

public enum FeedbackThemes {
    public static let off = FeedbackTheme(
        id: "off", name: "Off", description: "No haptics.",
        patterns: [:]
    )

    public static let subtle = FeedbackTheme(
        id: "subtle", name: "Subtle", description: "Soft tap per event.",
        patterns: [
            .needsInput:    [HapticBeat(time: 0, intensity: 0.45, sharpness: 0.5)],
            .finishedOk:    [HapticBeat(time: 0, intensity: 0.45, sharpness: 0.5)],
            .finishedError: [HapticBeat(time: 0, intensity: 0.55, sharpness: 0.7)],
        ]
    )

    public static let energetic = FeedbackTheme(
        id: "energetic", name: "Energetic",
        description: "Punchy double-tap rhythms.",
        patterns: [
            // doo-doo
            .needsInput: [
                HapticBeat(time: 0.00, intensity: 0.75, sharpness: 0.9),
                HapticBeat(time: 0.10, intensity: 0.75, sharpness: 0.9),
            ],
            // tap-tap-TAP ascending
            .finishedOk: [
                HapticBeat(time: 0.00, intensity: 0.55, sharpness: 0.7),
                HapticBeat(time: 0.09, intensity: 0.70, sharpness: 0.8),
                HapticBeat(time: 0.18, intensity: 0.95, sharpness: 1.0),
            ],
            // rapid alarm burst
            .finishedError: [
                HapticBeat(time: 0.00, intensity: 1.00, sharpness: 1.0),
                HapticBeat(time: 0.06, intensity: 1.00, sharpness: 1.0),
                HapticBeat(time: 0.12, intensity: 1.00, sharpness: 1.0),
                HapticBeat(time: 0.18, intensity: 1.00, sharpness: 1.0),
            ],
        ]
    )

    public static let morse = FeedbackTheme(
        id: "morse", name: "Morse",
        description: "Telegraph dit-dah codes.",
        patterns: [
            // · ·  (two shorts)
            .needsInput: [
                HapticBeat(time: 0.00, intensity: 0.8, sharpness: 1.0, duration: 0.06),
                HapticBeat(time: 0.16, intensity: 0.8, sharpness: 1.0, duration: 0.06),
            ],
            // · —  (short, long)  ≈ letter A, "affirmative"
            .finishedOk: [
                HapticBeat(time: 0.00, intensity: 0.8, sharpness: 1.0, duration: 0.06),
                HapticBeat(time: 0.18, intensity: 0.8, sharpness: 1.0, duration: 0.20),
            ],
            // · · · — — — · · ·  (SOS, compressed)
            .finishedError: [
                HapticBeat(time: 0.00, intensity: 0.9, sharpness: 1.0, duration: 0.05),
                HapticBeat(time: 0.12, intensity: 0.9, sharpness: 1.0, duration: 0.05),
                HapticBeat(time: 0.24, intensity: 0.9, sharpness: 1.0, duration: 0.05),
                HapticBeat(time: 0.40, intensity: 0.9, sharpness: 1.0, duration: 0.18),
                HapticBeat(time: 0.66, intensity: 0.9, sharpness: 1.0, duration: 0.18),
                HapticBeat(time: 0.92, intensity: 0.9, sharpness: 1.0, duration: 0.18),
                HapticBeat(time: 1.18, intensity: 0.9, sharpness: 1.0, duration: 0.05),
                HapticBeat(time: 1.30, intensity: 0.9, sharpness: 1.0, duration: 0.05),
                HapticBeat(time: 1.42, intensity: 0.9, sharpness: 1.0, duration: 0.05),
            ],
        ]
    )

    public static let zen = FeedbackTheme(
        id: "zen", name: "Zen",
        description: "Slow, meditative rumbles.",
        patterns: [
            // slow single bloom
            .needsInput: [
                HapticBeat(time: 0.00, intensity: 0.35, sharpness: 0.05, duration: 0.45),
            ],
            // bloom then fade
            .finishedOk: [
                HapticBeat(time: 0.00, intensity: 0.45, sharpness: 0.1, duration: 0.35),
                HapticBeat(time: 0.50, intensity: 0.25, sharpness: 0.05, duration: 0.30),
            ],
            // three slow pulses
            .finishedError: [
                HapticBeat(time: 0.00, intensity: 0.5, sharpness: 0.15, duration: 0.25),
                HapticBeat(time: 0.45, intensity: 0.5, sharpness: 0.15, duration: 0.25),
                HapticBeat(time: 0.90, intensity: 0.5, sharpness: 0.15, duration: 0.25),
            ],
        ]
    )

    public static let heartbeat = FeedbackTheme(
        id: "heartbeat", name: "Heartbeat",
        description: "Lub-dub living pulse.",
        patterns: [
            // lub-dub
            .needsInput: [
                HapticBeat(time: 0.00, intensity: 0.55, sharpness: 0.3),
                HapticBeat(time: 0.14, intensity: 0.75, sharpness: 0.4),
            ],
            // lub-dub · lub-dub (content resting beat)
            .finishedOk: [
                HapticBeat(time: 0.00, intensity: 0.55, sharpness: 0.3),
                HapticBeat(time: 0.14, intensity: 0.75, sharpness: 0.4),
                HapticBeat(time: 0.70, intensity: 0.55, sharpness: 0.3),
                HapticBeat(time: 0.84, intensity: 0.75, sharpness: 0.4),
            ],
            // racing beat — 5 fast pulses
            .finishedError: [
                HapticBeat(time: 0.00, intensity: 0.85, sharpness: 0.5),
                HapticBeat(time: 0.18, intensity: 0.85, sharpness: 0.5),
                HapticBeat(time: 0.36, intensity: 0.85, sharpness: 0.5),
                HapticBeat(time: 0.54, intensity: 0.85, sharpness: 0.5),
                HapticBeat(time: 0.72, intensity: 0.85, sharpness: 0.5),
            ],
        ]
    )

    public static let all: [FeedbackTheme] = [off, subtle, energetic, morse, zen, heartbeat]
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

/// Plays CoreHaptics patterns that encode distinct rhythms per event and
/// theme. Gracefully degrades to UIImpactFeedbackGenerator on devices
/// that don't support CoreHaptics (older iPads, simulators).
@MainActor
public final class AgentEventFeedback {
    public static let shared = AgentEventFeedback()

    private var engine: CHHapticEngine?
    private var engineStarted = false

    private init() {
        prepareEngine()
    }

    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let e = try CHHapticEngine()
            e.isAutoShutdownEnabled = true
            e.resetHandler = { [weak self] in
                // Engine was reset by the system (e.g. audio session
                // interruption). Restart lazily on next fire().
                self?.engineStarted = false
            }
            e.stoppedHandler = { [weak self] _ in
                self?.engineStarted = false
            }
            engine = e
        } catch {
            Log.ui.error("CHHapticEngine init failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func fire(_ event: AgentEvent) {
        let beats = FeedbackPreferences.shared.theme.pattern(for: event)
        guard !beats.isEmpty else { return }
        play(beats: beats)
    }

    private func play(beats: [HapticBeat]) {
        // Prefer CoreHaptics; fall back to UIImpactFeedback when unavailable.
        if let engine = engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            do {
                if !engineStarted {
                    try engine.start()
                    engineStarted = true
                }
                let events = beats.map { beat -> CHHapticEvent in
                    let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: beat.intensity)
                    let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: beat.sharpness)
                    if let duration = beat.duration {
                        return CHHapticEvent(
                            eventType: .hapticContinuous,
                            parameters: [intensityParam, sharpnessParam],
                            relativeTime: beat.time,
                            duration: duration
                        )
                    } else {
                        return CHHapticEvent(
                            eventType: .hapticTransient,
                            parameters: [intensityParam, sharpnessParam],
                            relativeTime: beat.time
                        )
                    }
                }
                let pattern = try CHHapticPattern(events: events, parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                return
            } catch {
                Log.ui.error("Haptic pattern failed: \(String(describing: error), privacy: .public)")
                // Fall through to the impact-generator fallback.
            }
        }

        // Fallback: approximate the first few beats with UIImpactFeedbackGenerator.
        for (idx, beat) in beats.prefix(4).enumerated() {
            let style: UIImpactFeedbackGenerator.FeedbackStyle = {
                if beat.intensity > 0.75 { return .heavy }
                if beat.intensity > 0.45 { return .medium }
                return .light
            }()
            DispatchQueue.main.asyncAfter(deadline: .now() + beat.time) {
                let gen = UIImpactFeedbackGenerator(style: style)
                gen.prepare()
                gen.impactOccurred()
            }
            _ = idx
        }
    }
}
#endif

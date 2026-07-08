#if canImport(UIKit)
import Foundation

/// Interprets raw terminal events into sprite mood suggestions.
@MainActor
@Observable
public final class TerminalActivityTracker {
    public private(set) var suggestedMood: MascotMood = .sitting

    private var lastUserInputAt: Date = .distantPast
    private var recentOutputBytes: Int = 0
    private var outputWindowStart: Date = .now
    private var sustainedOutputStart: Date?
    private var connected = false

    public init() {}

    // MARK: - Event hooks (called from bridge/view)

    public func onDataReceived(byteCount: Int) {
        recentOutputBytes += byteCount
        let now = Date.now

        if now.timeIntervalSince(outputWindowStart) > 3 {
            recentOutputBytes = byteCount
            outputWindowStart = now
        }

        evaluateMood()
    }

    public func onUserInput() {
        lastUserInputAt = .now
        sustainedOutputStart = nil
        evaluateMood()
    }

    public func onConnected() {
        connected = true
        suggestedMood = .happy

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, self.suggestedMood == .happy else { return }
            self.suggestedMood = .sitting
        }
    }

    public func onDisconnected() {
        connected = false
        suggestedMood = .spooked
    }

    // MARK: - Mood evaluation

    private func evaluateMood() {
        let now = Date.now
        let timeSinceInput = now.timeIntervalSince(lastUserInputAt)

        if timeSinceInput < 2 {
            suggestedMood = .watching
            return
        }

        let windowDuration = now.timeIntervalSince(outputWindowStart)
        if windowDuration > 0 {
            let bytesPerSec = Double(recentOutputBytes) / windowDuration
            if bytesPerSec > 100 && timeSinceInput > 3 {
                if sustainedOutputStart == nil {
                    sustainedOutputStart = now
                }
                if let start = sustainedOutputStart, now.timeIntervalSince(start) > 3 {
                    suggestedMood = .excited
                    return
                }
            } else {
                sustainedOutputStart = nil
            }
        }

        if suggestedMood == .watching || suggestedMood == .excited {
            suggestedMood = .sitting
        }
    }
}
#endif

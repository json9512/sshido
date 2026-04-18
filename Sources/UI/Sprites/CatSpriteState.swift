#if canImport(UIKit)
import Foundation

/// Moods the sprite can display. Fixed contract — community packs must implement all 6.
public enum MascotMood: String, Hashable, CaseIterable, Sendable {
    case sitting
    case watching
    case excited
    case spooked
    case happy
    case napping
}

/// Defines an animation loop for a mood.
public struct MascotAnimationDef: Sendable {
    public let frames: ClosedRange<Int>
    public let fps: Double
    public let looping: Bool

    public init(frames: ClosedRange<Int>, fps: Double, looping: Bool = true) {
        self.frames = frames
        self.fps = fps
        self.looping = looping
    }
}

/// State machine driving the sprite animation.
/// Animation definitions are loaded from the active SpritePack.
@MainActor
@Observable
public final class MascotSpriteState {
    public private(set) var currentMood: MascotMood = .sitting
    public private(set) var currentFrame: Int = 0

    /// When non-nil, playing an extra animation instead of a core mood.
    public private(set) var currentExtra: String?

    /// The active pack's animation defs. Updated when the user switches packs.
    public private(set) var animations: [MascotMood: MascotAnimationDef] = MascotSpriteState.defaultAnimations

    /// Extra animation sheets and defs from the active pack.
    public private(set) var extraSheets: [String: SpriteSheet] = [:]
    public private(set) var extraDefs: [String: MascotAnimationDef] = [:]
    public private(set) var extraNames: [String] = []

    private var sleepTimer: Task<Void, Never>?
    private var lastActivityDate: Date = .now
    private var manualOverrideUntil: Date = .distantPast

    /// Whether a manual mood override is active (blocks tracker updates).
    public var isManualOverride: Bool { Date.now < manualOverrideUntil }

    public static let defaultAnimations: [MascotMood: MascotAnimationDef] = [
        .sitting:  MascotAnimationDef(frames: 0...3,  fps: 4),
        .watching: MascotAnimationDef(frames: 0...3,  fps: 8),
        .excited:  MascotAnimationDef(frames: 0...5,  fps: 10),
        .spooked:  MascotAnimationDef(frames: 0...3,  fps: 6),
        .happy:    MascotAnimationDef(frames: 0...3,  fps: 6),
        .napping:  MascotAnimationDef(frames: 0...3,  fps: 2),
    ]

    public var currentAnimation: MascotAnimationDef {
        if let extra = currentExtra, let def = extraDefs[extra] {
            return def
        }
        return animations[currentMood] ?? MascotAnimationDef(frames: 0...0, fps: 4)
    }

    public init() {
        scheduleSleepCheck()
    }

    /// Load animation definitions from a sprite pack.
    public func loadPack(_ pack: SpritePack) {
        var defs: [MascotMood: MascotAnimationDef] = [:]
        for mood in MascotMood.allCases {
            defs[mood] = pack.animationDef(for: mood)
        }
        animations = defs

        // Load extras
        extraSheets = pack.extras
        var eDefs: [String: MascotAnimationDef] = [:]
        for name in pack.extras.keys {
            if let def = pack.extraAnimationDef(for: name) {
                eDefs[name] = def
            }
        }
        extraDefs = eDefs
        extraNames = pack.extras.keys.sorted()

        // Reset to idle with new pack's frame range
        currentExtra = nil
        currentMood = .sitting
        currentFrame = currentAnimation.frames.lowerBound
    }

    public func transition(to mood: MascotMood) {
        guard mood != currentMood || currentExtra != nil else { return }
        guard !isManualOverride else { return }
        currentExtra = nil
        currentMood = mood
        currentFrame = currentAnimation.frames.lowerBound
        lastActivityDate = .now

        if mood != .napping {
            scheduleSleepCheck()
        }
    }

    /// Manually set mood with a cooldown that blocks tracker overrides.
    public func manualTransition(to mood: MascotMood, duration: TimeInterval = 5) {
        currentExtra = nil
        currentMood = mood
        currentFrame = currentAnimation.frames.lowerBound
        lastActivityDate = .now
        manualOverrideUntil = Date.now.addingTimeInterval(duration)
    }

    /// Cycle to the next mood or extra animation. Used by double-tap.
    public func cycleToNext(duration: TimeInterval = 5) {
        let allMoods = MascotMood.allCases
        let totalCount = allMoods.count + extraNames.count

        // Find current position
        let currentIndex: Int
        if let extra = currentExtra, let idx = extraNames.firstIndex(of: extra) {
            currentIndex = allMoods.count + idx
        } else {
            currentIndex = allMoods.firstIndex(of: currentMood) ?? 0
        }

        // Advance to next
        let nextIndex = (currentIndex + 1) % totalCount
        lastActivityDate = .now
        manualOverrideUntil = Date.now.addingTimeInterval(duration)

        if nextIndex < allMoods.count {
            currentExtra = nil
            currentMood = allMoods[nextIndex]
        } else {
            let extraIdx = nextIndex - allMoods.count
            currentExtra = extraNames[extraIdx]
        }
        currentFrame = currentAnimation.frames.lowerBound
    }

    /// Advance frame — called by TimelineView on each tick.
    public func tick() {
        let anim = currentAnimation
        let next = currentFrame + 1
        if next > anim.frames.upperBound {
            if anim.looping {
                currentFrame = anim.frames.lowerBound
            }
        } else {
            currentFrame = next
        }
    }

    public func noteActivity() {
        lastActivityDate = .now
    }

    private func scheduleSleepCheck() {
        sleepTimer?.cancel()
        sleepTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard let self else { return }
                if self.currentMood == .sitting,
                   Date.now.timeIntervalSince(self.lastActivityDate) > 60 {
                    self.transition(to: .napping)
                    return
                }
            }
        }
    }
}
#endif

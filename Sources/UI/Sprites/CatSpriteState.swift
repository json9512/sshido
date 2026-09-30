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

@MainActor
@Observable
public final class MascotSpriteState {
    public private(set) var currentMood: MascotMood = .sitting
    public private(set) var currentFrame: Int = 0

    public private(set) var currentExtra: String?

    public private(set) var animations: [MascotMood: MascotAnimationDef] = MascotSpriteState.defaultAnimations

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

    public func loadPack(_ pack: SpritePack) {
        var defs: [MascotMood: MascotAnimationDef] = [:]
        for mood in MascotMood.allCases {
            defs[mood] = pack.animationDef(for: mood)
        }
        animations = defs

        extraSheets = pack.extras
        var eDefs: [String: MascotAnimationDef] = [:]
        for name in pack.extras.keys {
            if let def = pack.extraAnimationDef(for: name) {
                eDefs[name] = def
            }
        }
        extraDefs = eDefs
        extraNames = pack.extras.keys.sorted()

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

    public func cycleToNext(duration: TimeInterval = 5) {
        let allMoods = MascotMood.allCases
        let totalCount = allMoods.count + extraNames.count

        let currentIndex: Int
        if let extra = currentExtra, let idx = extraNames.firstIndex(of: extra) {
            currentIndex = allMoods.count + idx
        } else {
            currentIndex = allMoods.firstIndex(of: currentMood) ?? 0
        }

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

#if canImport(UIKit)
import UIKit

// MARK: - Manifest (the community contract)

/// The JSON manifest that ships with every sprite pack.
/// For GIF-based packs, frameSize and animations are optional —
/// they're auto-detected from the GIF files.
public struct SpriteManifest: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let name: String
    public let author: String
    public let license: String?
    public let format: String?          // "gif" or "png" (defaults to "png")
    public let frameSize: [Int]?        // optional for GIF packs
    public let animations: [String: AnimationDef]?  // optional for GIF packs

    public struct AnimationDef: Codable, Sendable {
        public let frames: Int
        public let fps: Double
        public let loop: Bool?  // defaults to true if omitted

        public var looping: Bool { loop ?? true }
    }

    public var isGIF: Bool { format == "gif" }

    /// All 6 moods are required.
    public static let requiredMoods: Set<String> = [
        "sitting", "watching", "excited", "spooked", "happy", "napping"
    ]

    public var frameSizePx: Int { frameSize?.first ?? 32 }

    /// Display size in points
    public var displaySize: CGFloat {
        let px = frameSizePx
        if px >= 64 { return CGFloat(px) }
        return 48
    }

    public func validate() throws {
        guard version <= SpriteManifest.currentVersion else {
            throw PackError.unsupportedVersion(version)
        }
        if !isGIF {
            // PNG packs require explicit frameSize and animations
            guard let fs = frameSize, fs.count == 2, fs[0] == fs[1] else {
                throw PackError.invalidFrameSize(frameSize ?? [])
            }
            guard let anims = animations else {
                throw PackError.missingMoods(SpriteManifest.requiredMoods)
            }
            let missing = SpriteManifest.requiredMoods.subtracting(anims.keys)
            if !missing.isEmpty {
                throw PackError.missingMoods(missing)
            }
            for (mood, def) in anims {
                guard def.frames >= 1 else { throw PackError.invalidFrameCount(mood) }
                guard def.fps > 0, def.fps <= 60 else { throw PackError.invalidFPS(mood) }
            }
        }
    }
}

public enum PackError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidFrameSize([Int])
    case missingMoods(Set<String>)
    case invalidFrameCount(String)
    case invalidFPS(String)
    case missingManifest
    case missingSprite(String)
    case corruptImage(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v): return "Unsupported pack version \(v)"
        case .invalidFrameSize(let s): return "Frame size must be square, got \(s)"
        case .missingMoods(let m): return "Missing required moods: \(m.sorted().joined(separator: ", "))"
        case .invalidFrameCount(let m): return "Invalid frame count for \(m)"
        case .invalidFPS(let m): return "Invalid FPS for \(m)"
        case .missingManifest: return "manifest.json not found in pack"
        case .missingSprite(let m): return "Missing \(m).png/.gif in pack"
        case .corruptImage(let m): return "Could not load \(m)"
        }
    }
}

// MARK: - Loaded sprite pack

/// A fully loaded, ready-to-render sprite pack.
@MainActor
public final class SpritePack {
    public let manifest: SpriteManifest
    public let id: String
    public let directory: URL?
    public let sheets: [MascotMood: SpriteSheet]
    public let preview: UIImage?

    /// Group ID for mascots with color variants (e.g. "wolf", "fox").
    /// Nil for standalone mascots.
    public let group: String?
    /// Variant label within a group (e.g. "Fire", "Water").
    public let variant: String?

    /// Extra animations beyond the 6 core moods, accessible via double-tap cycling.
    public let extras: [String: SpriteSheet]

    public var name: String { manifest.name }
    public var author: String { manifest.author }

    /// Display size in points. All mascots render at 80pt for visibility on phone screens.
    public var displaySize: CGFloat { 80 }

    public init(manifest: SpriteManifest, id: String, directory: URL?, sheets: [MascotMood: SpriteSheet], preview: UIImage?, group: String? = nil, variant: String? = nil, extras: [String: SpriteSheet] = [:]) {
        self.manifest = manifest
        self.id = id
        self.directory = directory
        self.sheets = sheets
        self.preview = preview
        self.group = group
        self.variant = variant
        self.extras = extras
    }

    /// Animation definition for a mood.
    /// For GIF packs, derived from the SpriteSheet's extracted metadata.
    /// For PNG packs, sourced from the manifest.
    public func animationDef(for mood: MascotMood) -> MascotAnimationDef {
        let sheet = sheets[mood]

        // GIF packs: use data from the GIF itself
        if manifest.isGIF, let sheet {
            let count = sheet.frameCount
            let fps = sheet.extractedFPS ?? 8
            let looping = sheet.extractedLooping
            return MascotAnimationDef(frames: 0...(max(0, count - 1)), fps: fps, looping: looping)
        }

        // PNG packs: use manifest
        guard let anims = manifest.animations, let def = anims[mood.rawValue] else {
            return MascotAnimationDef(frames: 0...0, fps: 4)
        }
        return MascotAnimationDef(frames: 0...(def.frames - 1), fps: def.fps, looping: def.looping)
    }

    /// Animation definition for an extra animation (derived from GIF metadata).
    public func extraAnimationDef(for name: String) -> MascotAnimationDef? {
        guard let sheet = extras[name] else { return nil }
        let count = sheet.frameCount
        let fps = sheet.extractedFPS ?? 8
        let looping = sheet.extractedLooping
        return MascotAnimationDef(frames: 0...(max(0, count - 1)), fps: fps, looping: looping)
    }

    /// Load a sprite pack from a directory containing manifest.json + PNGs or GIFs.
    public static func load(from directory: URL) throws -> SpritePack {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw PackError.missingManifest
        }
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(SpriteManifest.self, from: data)
        try manifest.validate()

        var sheets: [MascotMood: SpriteSheet] = [:]

        if manifest.isGIF {
            // GIF-based pack
            for mood in MascotMood.allCases {
                let gifURL = directory.appendingPathComponent("\(mood.rawValue).gif")
                guard FileManager.default.fileExists(atPath: gifURL.path) else {
                    throw PackError.missingSprite(mood.rawValue)
                }
                guard let sheet = SpriteSheet(gifURL: gifURL) else {
                    throw PackError.corruptImage(mood.rawValue)
                }
                sheets[mood] = sheet
            }
        } else {
            // PNG strip pack
            let px = manifest.frameSizePx
            let size = CGSize(width: px, height: px)
            for mood in MascotMood.allCases {
                let pngURL = directory.appendingPathComponent("\(mood.rawValue).png")
                guard FileManager.default.fileExists(atPath: pngURL.path) else {
                    throw PackError.missingSprite(mood.rawValue)
                }
                guard let sheet = SpriteSheet(fileURL: pngURL, frameSize: size) else {
                    throw PackError.corruptImage(mood.rawValue)
                }
                sheets[mood] = sheet
            }
        }

        let previewURL = directory.appendingPathComponent("preview.png")
        let preview: UIImage? = UIImage(contentsOfFile: previewURL.path)

        let id = directory.lastPathComponent
        return SpritePack(manifest: manifest, id: id, directory: directory, sheets: sheets, preview: preview)
    }
}
#endif

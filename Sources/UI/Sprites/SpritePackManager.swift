#if canImport(UIKit)
import Foundation
import UIKit

/// Manages sprite pack storage, downloading, and active pack selection.
@MainActor
@Observable
public final class SpritePackManager {
    public static let shared = SpritePackManager()

    public private(set) var installedPacks: [SpritePack] = []
    public private(set) var activePack: SpritePack?
    public private(set) var isDownloading = false
    public private(set) var downloadError: String?

    private let fm = FileManager.default

    private init() {
        loadInstalledPacks()
        let savedID = activePackID
        if let saved = installedPacks.first(where: { $0.id == savedID }) {
            activePack = saved
        } else {
            activePack = installedPacks.first
        }
    }

    // MARK: - Directory layout
    //   Documents/SpritePacks/<pack-id>/
    //     manifest.json
    //     idle.png, typing.png, ...
    //     preview.png (optional)

    private var packsRoot: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("SpritePacks", isDirectory: true)
    }

    // MARK: - Persistence of active pack ID

    private static let activePackKey = "sshido.activeSpritePack"

    private var activePackID: String? {
        get { UserDefaults.standard.string(forKey: Self.activePackKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.activePackKey) }
    }

    // MARK: - Load installed packs from disk

    public func loadInstalledPacks() {
        var packs: [SpritePack] = []

        // Built-in packs
        for loader in builtinLoaders {
            if let pack = loader() {
                packs.append(pack)
            }
        }

        // Downloaded packs
        if fm.fileExists(atPath: packsRoot.path) {
            let contents = (try? fm.contentsOfDirectory(
                at: packsRoot, includingPropertiesForKeys: nil
            )) ?? []
            for dir in contents where dir.hasDirectoryPath {
                if let pack = try? SpritePack.load(from: dir) {
                    packs.append(pack)
                }
            }
        }

        installedPacks = packs
    }

    private static let wolfFoxVariants = ["Original", "Earth", "Fire", "Gold", "Metal", "Water", "Wood"]

    private static let dogBreeds: [(slug: String, name: String)] = [
        ("golden", "Golden Retriever"), ("akita", "Akita"), ("greatdane", "Great Dane"),
        ("schnauzer", "Schnauzer"), ("saintbernard", "Saint Bernard"), ("husky", "Husky"),
    ]
    private static let bearVariants: [(slug: String, name: String)] = [
        ("piggypink", "Piggy Pink"), ("molten", "Molten"), ("tsunami", "Tsunami"),
        ("emeraldvision", "Emerald Vision"), ("softgameboy", "Soft Gameboy"), ("arcticdust", "Arctic Dust"),
    ]

    private var builtinLoaders: [() -> SpritePack?] {
        var loaders: [() -> SpritePack?] = [
            // Existing packs
            { self.loadBuiltinPNG(prefix: "black_cat", name: "Black Cat", id: "builtin-black-cat") },
            { self.loadBuiltinGIF(prefix: "shoom",     name: "Shoom",     id: "builtin-shoom") },
            { self.loadBuiltinGIF(prefix: "peak_green", name: "Peak Green", id: "builtin-peak-green", group: "peak", variant: "Green") },
            { self.loadBuiltinGIF(prefix: "peak_blue",  name: "Peak Blue",  id: "builtin-peak-blue",  group: "peak", variant: "Blue") },
            { self.loadBuiltinGIF(prefix: "peak_pink",  name: "Peak Pink",  id: "builtin-peak-pink",  group: "peak", variant: "Pink") },
            { self.loadBuiltinGIF(prefix: "cat1",      name: "Cat Orange", id: "builtin-cat-orange", group: "cat", variant: "Orange") },
            { self.loadBuiltinGIF(prefix: "cat2",      name: "Cat White",  id: "builtin-cat-white",  group: "cat", variant: "White") },

            // Standalone packs
            { self.loadBuiltinGIF(prefix: "capybara", name: "Capybara", id: "builtin-capybara",
                                  extraNames: ["lean_down", "lean_up"]) },
            { self.loadBuiltinGIF(prefix: "pengu", name: "Pengu", id: "builtin-pengu",
                                  extraNames: ["attack_ice", "attack_ray"]) },
            { self.loadBuiltinGIF(prefix: "crow",      name: "Crow",      id: "builtin-crow") },
            { self.loadBuiltinGIF(prefix: "crab",      name: "Crab",      id: "builtin-crab") },
            { self.loadBuiltinGIF(prefix: "horse",     name: "Horse",     id: "builtin-horse") },
            { self.loadBuiltinGIF(prefix: "otter",     name: "Otter",     id: "builtin-otter") },
        ]

        // Wolf & Fox groups
        for v in Self.wolfFoxVariants {
            let slug = v.lowercased()
            loaders.append { self.loadBuiltinGIF(prefix: "wolf_\(slug)", name: "Wolf \(v)", id: "builtin-wolf-\(slug)", group: "wolf", variant: v) }
            loaders.append { self.loadBuiltinGIF(prefix: "fox_\(slug)",  name: "Fox \(v)",  id: "builtin-fox-\(slug)",  group: "fox",  variant: v) }
        }

        // Dog group (6 breeds)
        for breed in Self.dogBreeds {
            loaders.append { self.loadBuiltinGIF(prefix: "dog_\(breed.slug)", name: "Dog \(breed.name)", id: "builtin-dog-\(breed.slug)",
                                                 group: "dog", variant: breed.name,
                                                 extraNames: ["walk", "licking", "lying_down"]) }
        }

        // Bear group (6 colors)
        for bear in Self.bearVariants {
            loaders.append { self.loadBuiltinGIF(prefix: "bear_\(bear.slug)", name: "Bear \(bear.name)", id: "builtin-bear-\(bear.slug)",
                                                 group: "bear", variant: bear.name,
                                                 extraNames: ["tumble", "walk", "sniffing"]) }
        }

        // Sleeping Cat group (3 colors)
        for n in ["1", "3", "5"] {
            loaders.append { self.loadBuiltinGIF(prefix: "sleepycat_\(n)", name: "Sleepy Cat \(n)", id: "builtin-sleepycat-\(n)",
                                                 group: "sleepycat", variant: n) }
        }

        return loaders
    }

    private func loadBuiltinPNG(prefix: String, name: String, id: String) -> SpritePack? {
        let size = CGSize(width: 32, height: 32)
        var sheets: [MascotMood: SpriteSheet] = [:]
        for mood in MascotMood.allCases {
            if let sheet = SpriteSheet(named: "\(prefix)_\(mood.rawValue)", frameSize: size) {
                sheets[mood] = sheet
            }
        }
        guard sheets.count == MascotMood.allCases.count else { return nil }

        let manifest = SpriteManifest(
            version: 1, name: name, author: "Community", license: "CC0",
            format: nil, frameSize: [32, 32],
            animations: [
                "sitting":  .init(frames: 15, fps: 4,  loop: true),
                "watching": .init(frames: 15, fps: 10, loop: true),
                "excited":  .init(frames: 15, fps: 14, loop: true),
                "spooked":  .init(frames: 15, fps: 6,  loop: true),
                "happy":    .init(frames: 15, fps: 8,  loop: true),
                "napping":  .init(frames: 15, fps: 2,  loop: true),
            ]
        )
        return SpritePack(manifest: manifest, id: id, directory: nil, sheets: sheets, preview: nil)
    }

    private func loadBuiltinGIF(prefix: String, name: String, id: String, group: String? = nil, variant: String? = nil, extraNames: [String] = []) -> SpritePack? {
        var sheets: [MascotMood: SpriteSheet] = [:]
        for mood in MascotMood.allCases {
            // SpriteSheet(named:) tries .gif then .png
            if let sheet = SpriteSheet(named: "\(prefix)_\(mood.rawValue)", frameSize: .zero) {
                sheets[mood] = sheet
            }
        }
        guard sheets.count == MascotMood.allCases.count else { return nil }

        // Load extra animations
        var extras: [String: SpriteSheet] = [:]
        for extraName in extraNames {
            if let sheet = SpriteSheet(named: "\(prefix)_\(extraName)", frameSize: .zero) {
                extras[extraName] = sheet
            }
        }

        let manifest = SpriteManifest(
            version: 1, name: name, author: "Community", license: "CC0",
            format: "gif", frameSize: nil, animations: nil
        )
        return SpritePack(manifest: manifest, id: id, directory: nil, sheets: sheets, preview: nil, group: group, variant: variant, extras: extras)
    }

    // MARK: - Select active pack

    public func setActive(_ pack: SpritePack) {
        activePack = pack
        activePackID = pack.id
    }

    // MARK: - Install from a base URL
    //
    // The marketplace serves packs as a directory of files at a base URL:
    //   https://sprites.sshido.app/packs/cool-robot/manifest.json
    //   https://sprites.sshido.app/packs/cool-robot/idle.png
    //   https://sprites.sshido.app/packs/cool-robot/typing.png
    //   ...
    //
    // The app downloads manifest.json first, validates it, then downloads all PNGs.

    public func install(from baseURL: URL) async throws {
        isDownloading = true
        downloadError = nil
        defer { isDownloading = false }

        do {
            let session = URLSession.shared

            // 1. Download and parse manifest
            let manifestURL = baseURL.appendingPathComponent("manifest.json")
            let (manifestData, _) = try await session.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(SpriteManifest.self, from: manifestData)
            try manifest.validate()

            // 2. Create pack directory
            let packID = sanitize(manifest.name)
            let packDir = packsRoot.appendingPathComponent(packID)
            if fm.fileExists(atPath: packDir.path) {
                try fm.removeItem(at: packDir)
            }
            try fm.createDirectory(at: packDir, withIntermediateDirectories: true)

            // 3. Save manifest
            try manifestData.write(to: packDir.appendingPathComponent("manifest.json"))

            // 4. Download all mood sprites (GIF or PNG)
            let ext = manifest.isGIF ? "gif" : "png"
            for mood in SpriteManifest.requiredMoods {
                let fileURL = baseURL.appendingPathComponent("\(mood).\(ext)")
                let (fileData, _) = try await session.data(from: fileURL)
                try fileData.write(to: packDir.appendingPathComponent("\(mood).\(ext)"))
            }

            // 5. Try to download preview (optional)
            if let (previewData, resp) = try? await session.data(from: baseURL.appendingPathComponent("preview.png")),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? previewData.write(to: packDir.appendingPathComponent("preview.png"))
            }

            // 6. Validate the full pack loads correctly
            let pack = try SpritePack.load(from: packDir)

            // 7. Reload and activate
            loadInstalledPacks()
            if let installed = installedPacks.first(where: { $0.id == packID }) {
                setActive(installed)
            } else {
                setActive(pack)
            }
        } catch {
            downloadError = error.localizedDescription
            throw error
        }
    }

    // MARK: - Delete a downloaded pack

    public func delete(_ pack: SpritePack) throws {
        guard let dir = pack.directory else { return }
        try fm.removeItem(at: dir)
        if activePack?.id == pack.id {
            activePack = nil
            activePackID = nil
        }
        loadInstalledPacks()
        if activePack == nil {
            activePack = installedPacks.first
            activePackID = activePack?.id
        }
    }

    // MARK: - Helpers

    private func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return String(name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
#endif

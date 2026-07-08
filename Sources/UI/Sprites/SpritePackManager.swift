#if canImport(UIKit)
import Foundation
import UIKit
#if canImport(sshidoCore)
import sshidoCore
#endif

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

        for loader in builtinLoaders {
            if let pack = loader() {
                packs.append(pack)
            }
        }

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

    private var builtinLoaders: [() -> SpritePack?] {
        // License notes per pack, from the original itch.io product pages.
        // The raw GIFs are bundled into the compiled app only — they are not
        // tracked in this repo and not redistributable. See docs/sprites.md.
        let otterLicense    = "itch.io — rili-xl.itch.io/otter-sprite-pack (commercial OK; do not redistribute)"
        let sleepycatLicense = "itch.io — toffeecraft.itch.io/cat-sleeping-animation-free (commercial OK; do not redistribute)"

        let loaders: [() -> SpritePack?] = [
            { self.loadBuiltinGIF(prefix: "otter", name: "Otter", id: "builtin-otter",
                                   author: "RiLi_XL", license: otterLicense) },

            { self.loadBuiltinGIF(prefix: "sleepycat_1", name: "Sleepy Cat Cream",  id: "builtin-sleepycat-cream",
                                   author: "ToffeeCraft", license: sleepycatLicense,
                                   group: "sleepycat", variant: "Cream") },
            { self.loadBuiltinGIF(prefix: "sleepycat_3", name: "Sleepy Cat Ginger", id: "builtin-sleepycat-ginger",
                                   author: "ToffeeCraft", license: sleepycatLicense,
                                   group: "sleepycat", variant: "Ginger") },
            { self.loadBuiltinGIF(prefix: "sleepycat_5", name: "Sleepy Cat Silver", id: "builtin-sleepycat-silver",
                                   author: "ToffeeCraft", license: sleepycatLicense,
                                   group: "sleepycat", variant: "Silver") },
        ]
        return loaders
    }

    private func loadBuiltinGIF(prefix: String, name: String, id: String, author: String, license: String, group: String? = nil, variant: String? = nil, extraNames: [String] = []) -> SpritePack? {
        var sheets: [MascotMood: SpriteSheet] = [:]
        for mood in MascotMood.allCases {
            if let sheet = SpriteSheet(named: "\(prefix)_\(mood.rawValue)", frameSize: .zero) {
                sheets[mood] = sheet
            }
        }
        guard sheets.count == MascotMood.allCases.count else { return nil }

        var extras: [String: SpriteSheet] = [:]
        for extraName in extraNames {
            if let sheet = SpriteSheet(named: "\(prefix)_\(extraName)", frameSize: .zero) {
                extras[extraName] = sheet
            }
        }

        let manifest = SpriteManifest(
            version: 1, name: name, author: author, license: license,
            format: "gif", frameSize: nil, animations: nil
        )
        return SpritePack(manifest: manifest, id: id, directory: nil, sheets: sheets, preview: nil, group: group, variant: variant, extras: extras)
    }

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

            let manifestURL = baseURL.appendingPathComponent("manifest.json")
            let (manifestData, _) = try await session.data(from: manifestURL)
            let manifest = try JSONDecoder().decode(SpriteManifest.self, from: manifestData)
            try manifest.validate()

            let packID = sanitize(manifest.name)
            let packDir = packsRoot.appendingPathComponent(packID)
            if fm.fileExists(atPath: packDir.path) {
                try fm.removeItem(at: packDir)
            }
            try fm.createDirectory(at: packDir, withIntermediateDirectories: true)

            try manifestData.write(to: packDir.appendingPathComponent("manifest.json"))

            let ext = manifest.isGIF ? "gif" : "png"
            for mood in SpriteManifest.requiredMoods {
                let fileURL = baseURL.appendingPathComponent("\(mood).\(ext)")
                let (fileData, _) = try await session.data(from: fileURL)
                try fileData.write(to: packDir.appendingPathComponent("\(mood).\(ext)"))
            }

            if let (previewData, resp) = try? await session.data(from: baseURL.appendingPathComponent("preview.png")),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                try? previewData.write(to: packDir.appendingPathComponent("preview.png"))
            }

            let pack = try SpritePack.load(from: packDir)

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

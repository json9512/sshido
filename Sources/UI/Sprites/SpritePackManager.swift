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
        if let saved = installedPacks.first(where: { $0.id == savedID }),
           canActivate(saved) {
            activePack = saved
        } else {
            // Fall back to the first non-premium pack if the saved one is
            // gated and the user hasn't paid.
            activePack = installedPacks.first { canActivate($0) } ?? installedPacks.first
        }
    }

    /// True if the current entitlement state allows activating this pack.
    /// Free packs always pass; premium packs require sshido+.
    public func canActivate(_ pack: SpritePack) -> Bool {
        !pack.isPremium || Entitlements.shared.hasPlus
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

    private var builtinLoaders: [() -> SpritePack?] {
        let loaders: [() -> SpritePack?] = [
            // Otter (standalone, free)
            { self.loadBuiltinGIF(prefix: "otter", name: "Otter", id: "builtin-otter") },

            // Sleepy Cat group — Cream and Ginger are free, Silver is a
            // sshido+ premium variant (demonstrates the paywall flow until
            // dedicated premium packs ship).
            { self.loadBuiltinGIF(prefix: "sleepycat_1", name: "Sleepy Cat Cream",  id: "builtin-sleepycat-cream",  group: "sleepycat", variant: "Cream") },
            { self.loadBuiltinGIF(prefix: "sleepycat_3", name: "Sleepy Cat Ginger", id: "builtin-sleepycat-ginger", group: "sleepycat", variant: "Ginger") },
            { self.loadBuiltinGIF(prefix: "sleepycat_5", name: "Sleepy Cat Silver", id: "builtin-sleepycat-silver", group: "sleepycat", variant: "Silver", premium: true) },
        ]
        return loaders
    }

    private func loadBuiltinGIF(prefix: String, name: String, id: String, group: String? = nil, variant: String? = nil, extraNames: [String] = [], premium: Bool = false) -> SpritePack? {
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
            format: "gif", frameSize: nil, animations: nil, premium: premium
        )
        return SpritePack(manifest: manifest, id: id, directory: nil, sheets: sheets, preview: nil, group: group, variant: variant, extras: extras)
    }

    // MARK: - Select active pack

    /// Activates the pack. Silently refuses if the pack is premium and the
    /// user doesn't have sshido+; UI should gate the call upstream via
    /// `canActivate(_:)` and present the paywall. The silent refusal here
    /// is a safety net in case the gating UI is bypassed.
    public func setActive(_ pack: SpritePack) {
        guard canActivate(pack) else { return }
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

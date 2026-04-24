#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoUI)
import sshidoUI
#endif

struct MascotSettingsSection: View {
    @Binding var toast: String?

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var entitlements = Entitlements.shared
    @State private var showMascotGrid = false
    @State private var expandedGroup: String?

    /// Activate if allowed, otherwise open the paywall. Kept in one place
    /// so both the top-level grid and the variant picker share behavior.
    private func selectOrPaywall(_ pack: SpritePack, manager: SpritePackManager) {
        if manager.canActivate(pack) {
            manager.setActive(pack)
            toast = "Switched to \(pack.name)"
        } else {
            router.sheet = .paywall(.plusLocked(feature: "Mascot \"\(pack.name)\""))
        }
    }

    var body: some View {
        let manager = SpritePackManager.shared
        Section {
            if let active = manager.activePack,
               let sheet = active.sheets[.sitting] {
                HStack(spacing: 12) {
                    Image(uiImage: sheet.frame(at: 0))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(active.name).font(DS.Font.headline)
                            .foregroundStyle(DS.Color.textPrimary)
                        Text("by \(active.author)").font(DS.Font.caption)
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Button {
                showMascotGrid.toggle()
            } label: {
                HStack {
                    Text("Manage Mascot")
                        .foregroundStyle(DS.Color.accent)
                    Spacer()
                    Image(systemName: showMascotGrid ? "chevron.up" : "chevron.down")
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .buttonStyle(.plain)

            if showMascotGrid {
                if let group = expandedGroup {
                    variantPicker(for: group, manager: manager)
                } else {
                    mainGrid(manager: manager)
                }
            }
        } header: {
            DSSectionHeader("Mascot")
        }
        .listRowBackground(DS.Color.surface1)
    }

    /// Unique mascots for the grid: standalone packs + one representative per group.
    private var mascotGridItems: [SpritePack] {
        let manager = SpritePackManager.shared
        var seen = Set<String>()
        var items: [SpritePack] = []
        for pack in manager.installedPacks {
            if let group = pack.group {
                if seen.contains(group) { continue }
                seen.insert(group)
                if let active = manager.activePack, active.group == group {
                    items.append(active)
                } else {
                    items.append(pack)
                }
            } else {
                items.append(pack)
            }
        }
        return items
    }

    private func variants(for group: String) -> [SpritePack] {
        SpritePackManager.shared.installedPacks.filter { $0.group == group }
    }

    @ViewBuilder
    private func mainGrid(manager: SpritePackManager) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(mascotGridItems, id: \.id) { pack in
                mascotCell(pack, isActive: manager.activePack?.id == pack.id || (pack.group != nil && manager.activePack?.group == pack.group))
                    .onTapGesture {
                        if let group = pack.group {
                            expandedGroup = group
                        } else {
                            selectOrPaywall(pack, manager: manager)
                        }
                    }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func variantPicker(for group: String, manager: SpritePackManager) -> some View {
        let groupVariants = variants(for: group)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expandedGroup = nil
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(DS.Font.callout)
                }
                .foregroundStyle(DS.Color.accent)
            }
            .buttonStyle(.plain)

            Text("Choose \(group.capitalized) style")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(groupVariants, id: \.id) { vPack in
                    variantChip(vPack, isActive: manager.activePack?.id == vPack.id)
                        .onTapGesture {
                            selectOrPaywall(vPack, manager: manager)
                        }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func mascotCell(_ pack: SpritePack, isActive: Bool) -> some View {
        let sheet = pack.sheets[.sitting]
        let label = pack.group?.capitalized ?? pack.name
        let locked = pack.isPremium && !entitlements.hasPlus
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(isActive ? DS.Color.accent.opacity(0.15) : DS.Color.surface2)
                    .frame(height: 72)
                if let sheet {
                    Image(uiImage: sheet.frame(at: 0))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .opacity(locked ? 0.5 : 1)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 12))
                        .padding(4)
                        .background(DS.Color.surface0.opacity(0.85), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(6)
                } else if isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(6)
                }
                if pack.group != nil {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(DS.Color.textTertiary)
                        .font(.system(size: 10))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(6)
                }
            }
            Text(label)
                .font(DS.Font.caption)
                .foregroundStyle(isActive ? DS.Color.accent : DS.Color.textSecondary)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func variantChip(_ pack: SpritePack, isActive: Bool) -> some View {
        let sheet = pack.sheets[.sitting]
        let locked = pack.isPremium && !entitlements.hasPlus
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.sm)
                    .fill(isActive ? DS.Color.accent.opacity(0.15) : DS.Color.surface2)
                    .frame(width: 56, height: 56)
                if let sheet {
                    Image(uiImage: sheet.frame(at: 0))
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 36, height: 36)
                        .opacity(locked ? 0.5 : 1)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 11))
                        .padding(3)
                        .background(DS.Color.surface0.opacity(0.85), in: Circle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(3)
                } else if isActive {
                    RoundedRectangle(cornerRadius: DS.Radius.sm)
                        .stroke(DS.Color.accent, lineWidth: 2)
                        .frame(width: 56, height: 56)
                }
            }
            Text(pack.variant ?? "")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? DS.Color.accent : DS.Color.textSecondary)
                .lineLimit(1)
        }
    }
}
#endif

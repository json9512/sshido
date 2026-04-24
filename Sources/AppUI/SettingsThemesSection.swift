#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct ThemesSettingsSection: View {
    @Binding var appearance: TerminalAppearance
    @Binding var toast: String?

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var entitlements = Entitlements.shared
    @State private var expanded = false

    var body: some View {
        Section {
            activePreview
            expandToggle
            if expanded {
                themeList
            }
        } header: {
            DSSectionHeader("Theme")
        } footer: {
            Text("Changes the terminal background and default text color. ANSI colors (ls output, prompt colors) are controlled by your shell and stay unchanged.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .listRowBackground(DS.Color.surface1)
    }

    @ViewBuilder
    private var activePreview: some View {
        let theme = appearance.theme
        HStack(spacing: DS.Spacing.md) {
            swatch(theme, locked: false)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(theme.name)
                    .font(DS.Font.rowTitle)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(theme.isPremium ? "sshido+" : "Free")
                    .font(DS.Font.caption)
                    .foregroundStyle(theme.isPremium ? DS.Color.accent : DS.Color.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var expandToggle: some View {
        Button {
            withAnimation(DS.Animation.quick) { expanded.toggle() }
        } label: {
            HStack {
                Text(expanded ? "Hide themes" : "Change theme")
                    .foregroundStyle(DS.Color.accent)
                Spacer()
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(DS.Color.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var themeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(TerminalThemes.all.enumerated()), id: \.element.id) { idx, theme in
                themeRow(theme)
                if idx < TerminalThemes.all.count - 1 {
                    Divider()
                        .background(DS.Color.titaniumDark.opacity(0.3))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func themeRow(_ theme: TerminalTheme) -> some View {
        let isActive = appearance.themeID == theme.id
        let locked = theme.isPremium && !entitlements.hasPlus
        Button {
            if locked {
                router.sheet = .paywall(.plusLocked(feature: "Theme \"\(theme.name)\""))
            } else {
                appearance.themeID = theme.id
                toast = "Theme: \(theme.name)"
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                swatch(theme, locked: locked)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(theme.name)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(theme.isPremium ? "sshido+" : "Free")
                        .font(DS.Font.caption)
                        .foregroundStyle(theme.isPremium ? DS.Color.accent : DS.Color.textTertiary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Color.accent)
                } else if locked {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 12))
                }
            }
            .padding(.vertical, DS.Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func swatch(_ theme: TerminalTheme, locked: Bool) -> some View {
        let bg = color(from: theme.bgHex) ?? .black
        let fg = color(from: theme.fgHex) ?? .white
        ZStack {
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(bg)
                .frame(width: 44, height: 30)
            Text("Aa")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(fg)
        }
        .opacity(locked ? 0.5 : 1)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .stroke(DS.Color.titaniumDark, lineWidth: 1)
        )
    }

    private func color(from hex: String) -> Color? {
        guard let rgb = TerminalTheme.rgb(fromHex: hex) else { return nil }
        return Color(red: Double(rgb.r), green: Double(rgb.g), blue: Double(rgb.b))
    }
}
#endif

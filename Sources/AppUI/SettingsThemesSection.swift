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
            swatch(theme)
            Text(theme.name)
                .font(DS.Font.rowTitle)
                .foregroundStyle(DS.Color.textPrimary)
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
                    Rectangle()
                        .fill(DS.Color.titaniumDark.opacity(0.25))
                        .frame(height: 0.5)
                }
            }
        }
    }

    @ViewBuilder
    private func themeRow(_ theme: TerminalTheme) -> some View {
        let isActive = appearance.themeID == theme.id
        Button {
            appearance.themeID = theme.id
            toast = "Theme: \(theme.name)"
        } label: {
            HStack(spacing: DS.Spacing.md) {
                swatch(theme)
                Text(theme.name)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textPrimary)
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DS.Color.accent)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func swatch(_ theme: TerminalTheme) -> some View {
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

#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

struct TerminalFeature: AppFeature {
    let id = "terminal"

    var settings: [SettingsEntry] {
        [
            SettingsEntry(id: "appearance", group: .terminal, order: 0, icon: "paintpalette", title: "Appearance",
                          summary: { services in
                              let a = await services.appearance.appearance
                              return "\(a.theme.name) · \(a.fontSize) pt"
                          },
                          destination: { AnyView(AppearanceSettingsView()) }),
            SettingsEntry(id: "keys", group: .terminal, order: 1, icon: "keyboard", title: "Keys & shortcuts",
                          summary: { services in
                              let groups = await services.shortcuts.groups
                              let count = groups.reduce(0) { $0 + $1.shortcuts.count }
                              return "\(count) shortcuts · \(groups.count) groups"
                          },
                          destination: { AnyView(KeysSettingsView()) }),
            SettingsEntry(id: "voice", group: .terminal, order: 2, icon: "mic", title: "Voice",
                          summary: { services in await services.appearance.appearance.voiceDictationEnabled ? "On" : "Off" },
                          destination: { AnyView(VoiceSettingsView()) }),
        ]
    }
}

@MainActor
final class AppearanceModel: ObservableObject {
    @Published var value: TerminalAppearance = .default {
        didSet {
            guard loaded, value != oldValue else { return }
            let next = value
            let store = services.appearance
            Task { try? await store.set(next) }
        }
    }
    private var loaded = false
    private let services: AppServices

    init(services: AppServices) { self.services = services }

    func load() async {
        value = await services.appearance.appearance
        loaded = true
    }
}

struct AppearanceSettingsView: View {
    @Environment(\.services) private var services
    @State private var toast: String?

    var body: some View {
        AppearanceSettingsContent(model: AppearanceModel(services: services), toast: $toast)
            .toast($toast)
    }
}

private struct AppearanceSettingsContent: View {
    @StateObject var model: AppearanceModel
    @Binding var toast: String?

    var body: some View {
        List {
            Section {
                Stepper(value: $model.value.fontSize, in: 8...22) {
                    HStack(spacing: DS.Spacing.md) {
                        Text("Aa").font(.system(size: CGFloat(model.value.fontSize), design: .monospaced))
                            .frame(width: 44)
                        Text("\(model.value.fontSize) pt").font(DS.Font.rowTitle)
                    }
                }
                .tideRow()
            } header: {
                SectionLabel("Font size")
            }
            Section {
                ThemeGrid(selectedID: $model.value.themeID)
                    .listRowInsets(EdgeInsets(top: DS.Spacing.md, leading: DS.Spacing.md, bottom: DS.Spacing.md, trailing: DS.Spacing.md))
                    .tideRow()
            } header: {
                SectionLabel("Theme")
            }
            MascotSettingsSection(toast: $toast)
        }
        .tideList()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}

struct ThemeGrid: View {
    @Binding var selectedID: String

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: DS.Spacing.md)], spacing: DS.Spacing.md) {
            ForEach(TerminalThemes.all, id: \.id) { theme in
                Button { selectedID = theme.id } label: { swatch(theme) }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(theme.name)
                    .accessibilityAddTraits(selectedID == theme.id ? .isSelected : [])
            }
        }
    }

    private func swatch(_ theme: TerminalTheme) -> some View {
        let selected = selectedID == theme.id
        return VStack(alignment: .leading, spacing: 6) {
            Text("~ $ ls")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(color(theme.fgHex) ?? .white)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(color(theme.bgHex) ?? .black, in: RoundedRectangle(cornerRadius: DS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.control)
                    .stroke(selected ? DS.Color.accent : DS.Color.line, lineWidth: selected ? 2 : 1))
            HStack {
                Text(theme.name).font(DS.Font.caption).foregroundStyle(selected ? DS.Color.textPrimary : DS.Color.textSecondary)
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.Color.accent) }
            }
        }
    }

    private func color(_ hex: String) -> Color? {
        TerminalTheme.rgb(fromHex: hex).map { Color(red: Double($0.r), green: Double($0.g), blue: Double($0.b)) }
    }
}

struct KeysSettingsView: View {
    @Environment(\.services) private var services

    var body: some View {
        KeysSettingsContent(model: AppearanceModel(services: services))
    }
}

private struct KeysSettingsContent: View {
    @StateObject var model: AppearanceModel
    @Environment(\.services) private var services
    @State private var groups: [ShortcutGroup] = []

    var body: some View {
        List {
            Section {
                Picker(selection: $model.value.returnKeyStyle) {
                    ForEach(ReturnKeyStyle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                } label: {
                    TideRow(icon: "return", title: "Return key")
                }
                .tideRow()
            }
            Section {
                NavigationLink { ShortcutGroupsListView() } label: {
                    TideRow(icon: "square.grid.2x2", title: "Shortcut groups",
                            subtitle: "\(groups.count) groups · \(groups.reduce(0) { $0 + $1.shortcuts.count }) shortcuts")
                }
                .tideRow()
            }
        }
        .tideList()
        .navigationTitle("Keys & shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await model.load()
            groups = await services.shortcuts.groups
        }
        .onReceive(NotificationCenter.default.publisher(for: .hotkeyLayoutChanged)) { _ in
            Task { groups = await services.shortcuts.groups }
        }
    }
}

struct VoiceSettingsView: View {
    @Environment(\.services) private var services

    var body: some View {
        VoiceSettingsContent(model: AppearanceModel(services: services))
    }
}

private struct VoiceSettingsContent: View {
    @StateObject var model: AppearanceModel

    static let locales: [(id: String, label: String)] = [
        ("", "System"), ("en-US", "English (US)"), ("en-GB", "English (UK)"), ("ko-KR", "한국어"), ("ja-JP", "日本語"),
        ("zh-Hans", "中文 (简体)"), ("es-ES", "Español"), ("fr-FR", "Français"), ("de-DE", "Deutsch"),
    ]

    var body: some View {
        List {
            Section {
                Toggle(isOn: $model.value.voiceDictationEnabled) {
                    TideRow(icon: "mic", title: "Dictation")
                }
                .tideRow()
                if model.value.voiceDictationEnabled {
                    Picker(selection: $model.value.dictationLocaleID) {
                        ForEach(Self.locales, id: \.id) { Text($0.label).tag($0.id) }
                    } label: {
                        TideRow(icon: "globe", title: "Language")
                    }
                    .tideRow()
                }
            } footer: {
                Text("Transcribed on this device.").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .tideList()
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}
#endif

#if canImport(UIKit)
import SwiftUI
import UIKit
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

public struct SettingsView: View {
    @State private var settings = PushSettings.default
    @State private var subscription: PushSubscription?
    @State private var deviceToken: String?
    @State private var serverURLInput = ""
    @State private var error: String?
    @State private var info: String?
    @State private var working = false
    @State private var appearance: TerminalAppearance = .default
    @State private var shortcuts: [CustomShortcut] = []
    @State private var newLabel = ""
    @State private var newText = ""
    @State private var voiceLanguage: VoiceLanguage = VoicePreferences.shared.language

    static let commonShortcuts: [CustomShortcut] = [
        .init(label: "⇧Tab",     bytes: [0x1b, 0x5b, 0x5a]),
        .init(label: "⌥Enter",   bytes: [0x1b, 0x0d]),
        .init(label: "⌘Enter",   bytes: [0x1b, 0x0d]),
        .init(label: "Home",     bytes: [0x1b, 0x5b, 0x48]),
        .init(label: "End",      bytes: [0x1b, 0x5b, 0x46]),
        .init(label: "PgUp",     bytes: [0x1b, 0x5b, 0x35, 0x7e]),
        .init(label: "PgDn",     bytes: [0x1b, 0x5b, 0x36, 0x7e]),
        .init(label: "⌃←",       bytes: [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x44]),
        .init(label: "⌃→",       bytes: [0x1b, 0x5b, 0x31, 0x3b, 0x35, 0x43]),
        .init(label: "⌃A",       bytes: [0x01]),
        .init(label: "⌃E",       bytes: [0x05]),
        .init(label: "⌃R",       bytes: [0x12]),
        .init(label: "⌃W",       bytes: [0x17]),
        .init(label: "⌃L",       bytes: [0x0c]),
        .init(label: "F1",       bytes: [0x1b, 0x4f, 0x50]),
        .init(label: "F2",       bytes: [0x1b, 0x4f, 0x51]),
        .init(label: "F3",       bytes: [0x1b, 0x4f, 0x52]),
        .init(label: "F4",       bytes: [0x1b, 0x4f, 0x53])
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                    }
                }
                Section {
                    TextField("https://push.example.com", text: $serverURLInput)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.callout.monospaced())
                    Button {
                        Task { await applyServer() }
                    } label: {
                        if working { ProgressView() } else { Text("Save & subscribe") }
                    }
                    .disabled(working || serverURLInput.isEmpty)
                    if let subscription {
                        Divider()
                        HStack {
                            Text("Notify URL").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(subscription.notifyURL)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(3).truncationMode(.middle)
                        Button {
                            UIPasteboard.general.string = subscription.notifyURL
                            flashToast("Notify URL copied")
                        } label: {
                            Label("Copy Notify URL", systemImage: "doc.on.doc")
                        }
                        if let deviceToken {
                            Button {
                                UIPasteboard.general.string = deviceToken
                                flashToast("Device token copied")
                            } label: {
                                Label("Copy device token", systemImage: "iphone")
                            }
                        }
                        HStack {
                            Text("Subscribed \(subscription.subscribedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        Button("Resubscribe") {
                            Task {
                                try? await PushService.shared.resubscribe()
                                await reload()
                                flashToast("Resubscribed")
                            }
                        }
                        Button(role: .destructive) {
                            Task {
                                try? await PushService.shared.clearSubscription()
                                await reload()
                                flashToast("Subscription cleared")
                            }
                        } label: {
                            Label("Clear subscription", systemImage: "trash")
                        }
                    } else {
                        Text(deviceToken == nil
                             ? "Awaiting APNs registration…"
                             : "Not subscribed yet")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Push notifications")
                } footer: {
                    Text("Enter your sshido-relay URL, subscribe, then paste the Notify URL into ~/.claude/hooks/notify.sh on your dev server. See Help → Push notifications for the full walkthrough.")
                }
                Section {
                    let existingLabels = Set(shortcuts.map { $0.label })
                    let available = SettingsView.commonShortcuts.filter { !existingLabels.contains($0.label) }
                    if available.isEmpty {
                        Text("All common keys added.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                            ForEach(available, id: \.label) { sc in
                                Button {
                                    Task {
                                        try? await CustomShortcutStore.shared.add(sc)
                                        await reload()
                                    }
                                } label: {
                                    Text(sc.label)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                        .frame(maxWidth: .infinity, minHeight: 36)
                                        .background(Color.accentColor.opacity(0.15),
                                                    in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Quick add")
                } footer: {
                    Text("Tap a key to add it to your shortcut bar.")
                }
                Section("Custom shortcuts") {
                    if shortcuts.isEmpty {
                        Text("No shortcuts yet. Use Quick add above, or type bytes manually below.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(shortcuts) { sc in
                            HStack {
                                Text(sc.label).bold()
                                Spacer()
                                Text(displayBytes(sc.bytes))
                                    .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.tail)
                            }
                        }
                        .onDelete { offsets in
                            Task {
                                for i in offsets {
                                    try? await CustomShortcutStore.shared.remove(id: shortcuts[i].id)
                                }
                                await reload()
                            }
                        }
                    }
                    HStack {
                        TextField("Label", text: $newLabel)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .frame(maxWidth: 100)
                        TextField("Text or \\e \\n \\t \\xNN", text: $newText)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.callout.monospaced())
                        Button("Add") {
                            Task { await addShortcut() }
                        }
                        .disabled(newLabel.isEmpty || newText.isEmpty)
                    }
                }
                Section("Voice input") {
                    Picker("Language", selection: $voiceLanguage) {
                        ForEach(VoiceLanguage.allCases, id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                }
                Section("Terminal appearance") {
                    Picker("Theme", selection: $appearance.theme) {
                        ForEach(TerminalTheme.allCases, id: \.self) { t in
                            Text(t.displayName).tag(t)
                        }
                    }
                    Stepper("Font size: \(appearance.fontSize) pt",
                            value: $appearance.fontSize, in: 9...22)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Settings")
            .task { await reload() }
            .onChange(of: appearance) { _, new in
                Task { try? await AppearanceStore.shared.set(new) }
            }
            .onChange(of: voiceLanguage) { _, new in
                VoicePreferences.shared.language = new
            }
            .overlay(alignment: .top) {
                if let info {
                    Text(info)
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: info)
        }
    }

    private func flashToast(_ s: String) {
        info = s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if info == s { info = nil }
        }
    }

    private func reload() async {
        settings = await PushService.shared.settings
        subscription = await PushService.shared.subscription
        deviceToken = await PushService.shared.deviceToken
        appearance = await AppearanceStore.shared.appearance
        shortcuts = await CustomShortcutStore.shared.shortcuts
        if serverURLInput.isEmpty { serverURLInput = settings.serverURL }
    }

    private func addShortcut() async {
        let bytes = parseShortcut(newText)
        guard !bytes.isEmpty else { return }
        let sc = CustomShortcut(label: newLabel, bytes: bytes)
        try? await CustomShortcutStore.shared.add(sc)
        newLabel = ""
        newText = ""
        await reload()
    }

    private func parseShortcut(_ s: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "\\", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex {
                let code = s[next]
                switch code {
                case "n": out.append(0x0a); i = s.index(after: next)
                case "r": out.append(0x0d); i = s.index(after: next)
                case "t": out.append(0x09); i = s.index(after: next)
                case "e": out.append(0x1b); i = s.index(after: next)
                case "\\": out.append(0x5c); i = s.index(after: next)
                case "x":
                    if let h1 = s.index(next, offsetBy: 1, limitedBy: s.endIndex), h1 < s.endIndex,
                       let h2 = s.index(next, offsetBy: 2, limitedBy: s.endIndex), h2 < s.endIndex,
                       let v = UInt8(String(s[h1...h2]), radix: 16) {
                        out.append(v); i = s.index(after: h2)
                    } else { out.append(0x5c); out.append(0x78); i = s.index(after: next) }
                default:
                    out.append(0x5c); out.append(contentsOf: String(code).utf8); i = s.index(after: next)
                }
            } else {
                out.append(contentsOf: String(ch).utf8); i = s.index(after: i)
            }
        }
        return out
    }

    private func displayBytes(_ b: [UInt8]) -> String {
        if let s = String(bytes: b, encoding: .utf8), s.allSatisfy({ $0.isASCII && !$0.isNewline }) {
            return s
        }
        return b.map { String(format: "\\x%02x", $0) }.joined()
    }

    private func applyServer() async {
        error = nil; working = true
        defer { working = false }
        do {
            try await PushService.shared.setServerURL(serverURLInput)
            await reload()
            flashToast("Subscribed")
        } catch {
            self.error = String(describing: error)
        }
    }
}
#endif

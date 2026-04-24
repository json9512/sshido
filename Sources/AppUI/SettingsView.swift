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
    @State private var toast: String?
    @State private var working = false
    @State private var appearance: TerminalAppearance = .default
    @State private var groups: [ShortcutGroup] = []
    @State private var voiceLanguage: VoiceLanguage = VoicePreferences.shared.language
    @State private var voiceAutoSend: Bool = VoicePreferences.shared.autoSend
    @State private var voiceAITranslate: Bool = VoicePreferences.shared.aiTranslate

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label("Help & FAQ", systemImage: "questionmark.circle")
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                    .dsRow()
                }
                Section {
                    HStack(spacing: DS.Spacing.sm) {
                        TextField("https://push.example.com", text: $serverURLInput)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                            .font(DS.Font.mono)
                        Button {
                            Task { await applyServer() }
                        } label: {
                            if working {
                                ProgressView().tint(DS.Color.accent)
                            } else {
                                Image(systemName: subscription != nil ? "arrow.clockwise" : "paperplane.fill")
                                    .foregroundStyle(DS.Color.accent)
                            }
                        }
                        .disabled(working || trimmedServerURLInput.isEmpty)
                    }
                    .dsRow()
                    if let subscription {
                        HStack {
                            Text("Subscribed \(subscription.subscribedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            Spacer(minLength: DS.Spacing.lg)
                            Button {
                                UIPasteboard.general.string = Self.agentSetupPrompt(notifyURL: subscription.notifyURL)
                                toast = "Agent setup prompt copied"
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 16))
                                    .foregroundStyle(DS.Color.accent)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Copy agent setup prompt")
                            Button {
                                Task {
                                    try? await PushService.shared.clearSubscription()
                                    await reload()
                                    toast = "Subscription cleared"
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 16))
                                    .foregroundStyle(DS.Color.error)
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Clear subscription")
                        }
                        .dsRow()
                    } else {
                        Text(deviceToken == nil
                             ? "Awaiting APNs registration…"
                             : "Not subscribed yet")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                            .dsRow()
                    }
                } header: {
                    DSSectionHeader("Push notifications")
                } footer: {
                    Text("Enter your push server URL and tap send. Then copy the agent setup prompt and paste it into Claude Code.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Section(header: DSSectionHeader("Shortcuts")) {
                    NavigationLink {
                        ShortcutGroupsListView()
                    } label: {
                        HStack(spacing: DS.Spacing.md) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 16))
                                .foregroundStyle(DS.Color.titanium)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                                Text("Manage groups")
                                    .font(DS.Font.headline)
                                    .foregroundStyle(DS.Color.textPrimary)
                                Text(shortcutsSummary)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                    }
                    .dsRow()
                }
                Section(header: DSSectionHeader("Voice input")) {
                    Picker("Language", selection: $voiceLanguage) {
                        ForEach(VoiceLanguage.allCases, id: \.self) { v in
                            Text(v.displayName).tag(v)
                        }
                    }
                    .dsRow()
                    Toggle("Send Enter after voice input", isOn: $voiceAutoSend)
                        .dsRow()
                    Toggle("AI command translation", isOn: $voiceAITranslate)
                        .dsRow()
                }
                Section {
                    Picker("Return key", selection: $appearance.returnKeyStyle) {
                        ForEach(ReturnKeyStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    }
                    .dsRow()
                } header: {
                    DSSectionHeader("Keyboard")
                } footer: {
                    Text("Changes the bottom-right key on the software keyboard. \"Return\" is the usual ↵ arrow.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Section(header: DSSectionHeader("Terminal")) {
                    Stepper("Font size: \(appearance.fontSize) pt",
                            value: $appearance.fontSize, in: 8...22)
                        .dsRow()
                    Toggle("Show mascot", isOn: $appearance.showMascotCompanion)
                        .dsRow()
                }
                if appearance.showMascotCompanion {
                    mascotSection
                }
                if let error {
                    Section { InlineErrorText(error) }
                }
            }
            .dsFormStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil)
                    }
                }
            }
            .task { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .hotkeyLayoutChanged)) { _ in
                Task { await reload() }
            }
            .onChange(of: appearance) { _, new in
                Task { try? await AppearanceStore.shared.set(new) }
            }
            .onChange(of: voiceLanguage) { _, new in
                VoicePreferences.shared.language = new
            }
            .onChange(of: voiceAutoSend) { _, new in
                VoicePreferences.shared.autoSend = new
            }
            .onChange(of: voiceAITranslate) { _, new in
                VoicePreferences.shared.aiTranslate = new
            }
            .toast($toast)
        }
    }

    static func agentSetupPrompt(notifyURL: String) -> String {
        """
        Set up sshido push notifications on this machine.

        My Notify URL is: \(notifyURL)

        Context: sshido exports SSHIDO_SESSION=1 in every shell it opens (plain SSH and inside its tmux sessions). The hooks below gate on that env var so Claude Code running in a local terminal on this machine will not push — only sessions opened from the sshido iOS app will.

        Do the following, idempotently:

        1. mkdir -p ~/.claude/hooks ~/.sshido
        2. Write ~/.sshido/notify.url containing exactly the Notify URL above (no trailing newline chars beyond one), chmod 600.
        3. Write ~/.claude/hooks/notify.sh (chmod +x):
           - reads URL from $SSHIDO_NOTIFY_URL or ~/.sshido/notify.url; exits 0 silently if neither is set
           - takes args: EVENT TITLE BODY
           - POSTs JSON {title, body, priority, sessionRef, hostRef} to the URL via `curl -fsS -m 5`
           - priority="high" for Notification / StopFailure, else "normal"
           - sessionRef from `tmux display-message -p '#S'` when inside tmux
           - hostRef from `hostname -s`
        4. Merge these hooks into ~/.claude/settings.json (preserve existing keys). Valid Claude Code events only — do NOT use "AskUserQuestion" or "Error" (those are ignored with a warning). Each command must be gated on $SSHIDO_SESSION:
           - Notification → [ -z "$SSHIDO_SESSION" ] || ~/.claude/hooks/notify.sh Notification "Claude needs input" "Check your session"
           - Stop         → [ -z "$SSHIDO_SESSION" ] || ~/.claude/hooks/notify.sh Stop "Task complete" "Claude finished"
           - StopFailure  → [ -z "$SSHIDO_SESSION" ] || ~/.claude/hooks/notify.sh StopFailure "Claude error" "Claude stopped with an error"
           Use the canonical shape: { "hooks": { "<Event>": [ { "matcher": "", "hooks": [ { "type": "command", "command": "..." } ] } ] } }.
        5. Verify with: curl -fsS -X POST -H 'content-type: application/json' -d '{"title":"test","body":"hello from agent","priority":"high"}' "$(cat ~/.sshido/notify.url)" — expect HTTP 204.
        6. Print a one-line summary.
        """
    }

    private var trimmedServerURLInput: String {
        serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var subscribeActionLabel: String {
        guard let sub = subscription else { return "Subscribe" }
        return sub.serverURL == trimmedServerURLInput ? "Update subscription" : "Change server"
    }

    private func reload() async {
        settings = await PushService.shared.settings
        subscription = await PushService.shared.subscription
        deviceToken = await PushService.shared.deviceToken
        appearance = await AppearanceStore.shared.appearance
        groups = await ShortcutGroupStore.shared.groups
        if serverURLInput.isEmpty { serverURLInput = settings.serverURL }
    }

    private var shortcutsSummary: String {
        let groupCount = groups.count
        let shortcutCount = groups.reduce(0) { $0 + $1.shortcuts.count }
        let g = groupCount == 1 ? "group" : "groups"
        let s = shortcutCount == 1 ? "shortcut" : "shortcuts"
        return "\(groupCount) \(g), \(shortcutCount) \(s)"
    }

    private func applyServer() async {
        error = nil; working = true
        defer { working = false }
        let input = trimmedServerURLInput
        guard !input.isEmpty else { return }
        do {
            if let sub = subscription, sub.serverURL == input {
                try await PushService.shared.resubscribe()
                await reload()
                toast = "Resubscribed"
            } else {
                try await PushService.shared.setServerURL(input)
                await reload()
                toast = "Subscribed"
            }
        } catch {
            self.error = String(describing: error)
        }
    }

    // MARK: - Mascot

    @State private var showMascotGrid = false
    @State private var expandedGroup: String?

    /// Unique mascots for the grid: standalone packs + one representative per group.
    private var mascotGridItems: [SpritePack] {
        let manager = SpritePackManager.shared
        var seen = Set<String>()
        var items: [SpritePack] = []
        for pack in manager.installedPacks {
            if let group = pack.group {
                if seen.contains(group) { continue }
                seen.insert(group)
                // Show the active variant if one is selected, otherwise first
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

    /// All variants for a group.
    private func variants(for group: String) -> [SpritePack] {
        SpritePackManager.shared.installedPacks.filter { $0.group == group }
    }

    @ViewBuilder
    private var mascotSection: some View {
        let manager = SpritePackManager.shared
        Section {
            // Active mascot preview
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
                    // Variant picker for expanded group
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
                                        manager.setActive(vPack)
                                        toast = "Switched to \(vPack.name)"
                                    }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    // Main mascot grid
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(mascotGridItems, id: \.id) { pack in
                            mascotCell(pack, isActive: manager.activePack?.id == pack.id || (pack.group != nil && manager.activePack?.group == pack.group))
                                .onTapGesture {
                                    if let group = pack.group {
                                        expandedGroup = group
                                    } else {
                                        manager.setActive(pack)
                                        toast = "Switched to \(pack.name)"
                                    }
                                }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            DSSectionHeader("Mascot")
        }
        .listRowBackground(DS.Color.surface1)
    }

    @ViewBuilder
    private func mascotCell(_ pack: SpritePack, isActive: Bool) -> some View {
        let sheet = pack.sheets[.sitting]
        let label = pack.group?.capitalized ?? pack.name
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
                }
                if isActive {
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
                }
                if isActive {
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

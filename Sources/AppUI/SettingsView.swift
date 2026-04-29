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
    @EnvironmentObject private var router: AppRouter
    @State private var settings = PushSettings.default
    @State private var subscription: PushSubscription?
    @State private var deviceToken: String?
    @State private var serverURLInput = ""
    @State private var error: String?
    @State private var toast: String?
    @State private var working = false
    @State private var appearance: TerminalAppearance = .default
    @State private var groups: [ShortcutGroup] = []
    @State private var confirmClearSubscription = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        FAQView()
                    } label: {
                        Label {
                            Text("Help & FAQ")
                                .font(DS.Font.rowTitle)
                                .foregroundStyle(DS.Color.textPrimary)
                        } icon: {
                            Image(systemName: "questionmark.circle")
                        }
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
                                confirmClearSubscription = true
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
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text("Enter your push server URL and tap send. Then copy the agent setup prompt and paste it into Claude Code.")
                        Link("Run your own relay →",
                             destination: URL(string: "https://github.com/json9512/sshido/tree/main/server/sshido-relay")!)
                            .foregroundStyle(DS.Color.accent)
                    }
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
                                    .font(DS.Font.rowTitle)
                                    .foregroundStyle(DS.Color.textPrimary)
                                Text(shortcutsSummary)
                                    .font(DS.Font.caption)
                                    .foregroundStyle(DS.Color.textSecondary)
                            }
                        }
                    }
                    .dsRow()
                }
                Section {
                    Picker(selection: $appearance.returnKeyStyle) {
                        ForEach(ReturnKeyStyle.allCases, id: \.self) { s in
                            Text(s.displayName).tag(s)
                        }
                    } label: {
                        Text("Return key").font(DS.Font.rowTitle)
                    }
                    .dsRow()
                } header: {
                    DSSectionHeader("Keyboard")
                } footer: {
                    Text("Changes the bottom-right key on the software keyboard. \"Return\" is the usual ↵ arrow.")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                }
                Section(header: DSSectionHeader("Terminal")) {
                    Stepper(value: $appearance.fontSize, in: 8...22) {
                        Text("Font size: \(appearance.fontSize) pt").font(DS.Font.rowTitle)
                    }
                    .dsRow()
                    Toggle(isOn: $appearance.showMascotCompanion) {
                        Text("Show mascot").font(DS.Font.rowTitle)
                    }
                    .dsRow()
                }
                ThemesSettingsSection(appearance: $appearance, toast: $toast)
                FeedbackSettingsSection(toast: $toast)
                if appearance.showMascotCompanion {
                    MascotSettingsSection(toast: $toast)
                }
                if let error {
                    Section { InlineErrorText(error) }
                }
            }
            .dsFormStyle()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .dsKeyboardDismissToolbar()
            .task { await reload() }
            .onReceive(NotificationCenter.default.publisher(for: .hotkeyLayoutChanged)) { _ in
                Task { await reload() }
            }
            .onChange(of: appearance) { _, new in
                Task { try? await AppearanceStore.shared.set(new) }
            }
            .toast($toast)
            .confirmationDialog(
                "Clear push subscription?",
                isPresented: $confirmClearSubscription,
                titleVisibility: .visible
            ) {
                Button("Clear subscription", role: .destructive) {
                    Task {
                        try? await PushService.shared.clearSubscription()
                        await reload()
                        toast = "Subscription cleared"
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Stops pushes to this device. You can re-subscribe at any time.")
            }
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

}
#endif

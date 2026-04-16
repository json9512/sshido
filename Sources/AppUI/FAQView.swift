#if canImport(UIKit)
import SwiftUI
import UIKit

public struct FAQView: View {
    public init() {}

    @State private var toast: String?

    public var body: some View {
        List {
            Section("Push notifications") {
                FAQItem(
                    q: "Copy-paste prompt: let your agent register the hook",
                    a: SettingsView.agentSetupPrompt(notifyURL: "<NOTIFY_URL — get from Settings → Push notifications>"),
                    copyable: true,
                    onCopy: { copied in
                        UIPasteboard.general.string = copied
                        showToast("Prompt copied — replace <NOTIFY_URL> before pasting")
                    }
                )
                FAQItem(
                    q: "I'm not getting notifications",
                    a: "Check: (a) device token shows in the Push notifications section; (b) the Notify URL answers 204 when curled with a test payload; (c) iOS Settings → sshido → Notifications is on; (d) the hook script in ~/.claude/hooks/notify.sh is executable and references the correct Notify URL."
                )
            }
            Section("Connectivity") {
                FAQItem(
                    q: "Connecting from a different network (e.g. LTE)",
                    a: "Install Tailscale on both your phone and Mac (free tier fine). Then use the Mac's tailnet hostname (e.g. mac-name.tail-xxxxx.ts.net) as the Host when adding a server. No port forwarding needed."
                )
                FAQItem(
                    q: "Session survives app kill?",
                    a: "Yes. We run tmux on the server. Force-quitting the app doesn't touch tmux — reopen, tap the session, it reattaches to the same pane."
                )
            }
            Section("Shortcuts") {
                FAQItem(
                    q: "How do I add Shift+Tab or Ctrl+R?",
                    a: "Settings → Quick add. Tap the labeled chip for the key you want. The chip disappears from Quick add (since it's already in your bar) and appears in the hotkey bar at the bottom of each session."
                )
                FAQItem(
                    q: "Can I type a custom escape sequence?",
                    a: "Yes. Settings → Custom shortcuts → bottom row. Label is what you see on the button; Text supports \\e (Esc), \\n, \\r, \\t, \\xNN (hex byte). Example: \"\\e[H\" for Home."
                )
            }
            Section("Auth") {
                FAQItem(
                    q: "Key vs password",
                    a: "Keys are preferred (stored in iOS Keychain, Face-ID gated). Password auth works for Tailscale / dev boxes where you don't want to manage keys — paste your server password into Add Server → Authentication → Password."
                )
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: toast)
    }

    private func showToast(_ s: String) {
        toast = s
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if toast == s { toast = nil }
        }
    }
}

private struct FAQItem: View {
    let q: String
    let a: String
    var copyable: Bool = false
    var onCopy: ((String) -> Void)? = nil
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if copyable {
                    Button {
                        onCopy?(a)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                }
                Text(a)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding(.top, 4)
        } label: {
            Text(q).font(.callout).bold()
        }
    }
}
#endif

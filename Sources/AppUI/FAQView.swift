#if canImport(UIKit)
import SwiftUI
import UIKit

public struct FAQView: View {
    public init() {}

    public var body: some View {
        List {
            Section(header: DSSectionHeader("Server requirements")) {
                FAQItem(
                    q: "What do I need on my server?",
                    a: """
                    Required: OpenSSH.
                    Recommended: tmux (session persistence).

                    macOS: System Settings → General → Sharing → Remote Login.
                    Debian / Ubuntu: sudo apt install openssh-server tmux
                    Fedora / RHEL: sudo dnf install openssh-server tmux

                    Without tmux, sshido falls back to a plain login shell — it still works, just no persistence.
                    """
                )
                FAQItem(
                    q: "Does my shell need configuration?",
                    a: "No. Your normal login shell and rc files run as usual."
                )
            }
            Section(header: DSSectionHeader("Connectivity")) {
                FAQItem(
                    q: "Connecting from LTE or another network?",
                    a: "Install Tailscale on both your phone and Mac. Use the tailnet hostname (e.g. mac.tail-xxxxx.ts.net) as the host. No port forwarding."
                )
                FAQItem(
                    q: "Do sessions survive closing the app?",
                    a: "Yes. tmux keeps the session alive on the server. Reopen sshido and tap the session to reattach."
                )
            }
            Section(header: DSSectionHeader("Auth")) {
                FAQItem(
                    q: "Key or password?",
                    a: """
                    Keys are preferred — stored in the iOS Keychain, Face ID gated.

                    Password auth works for Tailscale and dev boxes where you don't want to manage keys.
                    """
                )
            }
            Section(header: DSSectionHeader("Privacy")) {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Text("Privacy Policy").font(DS.Font.callout).bold()
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .dsRow()
            }
        }
        .dsFormStyle()
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FAQItem: View {
    let q: String
    let a: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(a)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .padding(.top, DS.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(q).font(DS.Font.callout).bold()
                .foregroundStyle(DS.Color.textPrimary)
        }
        .tint(DS.Color.titanium)
        .dsRow()
    }
}
#endif

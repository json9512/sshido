#if canImport(UIKit)
import SwiftUI
import UIKit

public struct FAQView: View {
    public init() {}

    public var body: some View {
        List {
            Section(header: DSSectionHeader("Getting started")) {
                FAQItem(
                    q: "How do I add a server and connect?",
                    a: """
                    1. Tap + on the home screen to add your first server.
                    2. Fill in the server's Name, Host, Port, Username, and auth (Key or Password), then tap Save. sshido tests the connection before saving.
                    3. Tap your server in the list to open its sessions.
                    4. Tap New session to connect and open a terminal.

                    First-time users are walked through these steps with on-screen hints. The walkthrough runs once.
                    """
                )
            }
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
            Section(header: DSSectionHeader("Open-source libraries")) {
                FAQItem(
                    q: "What open-source software does sshido use?",
                    a: """
                    Direct dependencies:
                    • Citadel — SSH protocol (github.com/orlandos-nl/Citadel)
                    • SwiftTerm — terminal emulator (github.com/migueldeicaza/SwiftTerm)
                    • Sentry Cocoa — crash reporting (github.com/getsentry/sentry-cocoa)

                    Transitive (pulled in by the above):
                    • SwiftNIO, SwiftNIO SSH, SwiftCrypto
                    • swift-log, swift-collections, swift-atomics
                    • swift-asn1, swift-system, swift-argument-parser
                    • BigInt

                    Each library ships under its own license.
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
        .accentColor(DS.Color.titaniumLight)
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
        .tint(DS.Color.titaniumLight)
        .dsRow()
    }
}
#endif

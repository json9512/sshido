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
            Section(header: DSSectionHeader("Upgrades")) {
                FAQItem(
                    q: "What's sshido+?",
                    a: """
                    A one-time purchase that unlocks optional app features:
                    • Premium mascot packs
                    • Curated terminal themes
                    • CloudKit sync for hosts, identities, and shortcut groups across your devices
                    • Widgets, Live Activities, and Apple Watch glances
                    • Haptic and sound themes for agent events

                    Paid once, lifetime access. Family Sharing is enabled — one purchase covers everyone in your Apple Family group.
                    """
                )
                FAQItem(
                    q: "What's sshido Cloud Pro?",
                    a: """
                    A monthly or yearly subscription that unlocks hosted-relay features on push.sshido.com:
                    • Multiple named relay endpoints (home / work / CI, each with its own notify URL and label)
                    • Webhook-to-push bridge — forward GitHub, Linear, Sentry events to your phone
                    • Published 99.9% uptime SLA backed by a public status page

                    It's a subscription because the relay has real server costs (storage, egress, ops). Cancel anytime in iOS Settings → Apple ID → Subscriptions.
                    """
                )
                FAQItem(
                    q: "Are sshido+ and Cloud Pro the same thing?",
                    a: """
                    No. They unlock different things and stack.

                    • sshido+ = app features (cosmetic, client-side, one-time)
                    • Cloud Pro = hosted relay features (server-side, subscription)

                    Buying sshido+ does not unlock webhook forwarding or multiple endpoints. Subscribing to Cloud Pro does not unlock mascots or themes. Power users buy both.
                    """
                )
                FAQItem(
                    q: "What stays free forever?",
                    a: """
                    Everything that makes sshido useful as a terminal:
                    • SSH, Mosh, and tmux session persistence
                    • Push notifications (one endpoint per account, unlimited volume)
                    • All hosts, identities, and shortcut groups
                    • Agent bar, command palette, voice input

                    You can also self-host the relay (server/sshido-relay) — free forever. The paid Cloud Pro tier is for people who want the hosted version plus the extra features.
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

#if canImport(UIKit)
import SwiftUI
import UIKit

public struct FAQView: View {
    public init() {}

    public var body: some View {
        List {
            Section(header: SectionLabel("Getting started")) {
                FAQItem(
                    q: "How do I add a server and connect?",
                    a: """
                    1. Tap + on the home screen to add your first server.
                    2. Fill in the server's Name, Host, Port, Username, and auth (Key or Password), then tap ✓. sshido tests the connection before saving.
                    3. Tap your server in the list to open its sessions.
                    4. Tap + to open a new terminal session.

                    First-time users are walked through these steps with on-screen hints. The walkthrough runs once.
                    """
                )
            }
            Section(header: SectionLabel("Server requirements")) {
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
            Section(header: SectionLabel("Agents")) {
                FAQItem(
                    q: "What is agent mode?",
                    a: "A chat with coding agents that run on your own server. An orchestrator plans each request, starts subagents in Podman containers on your host when the work calls for it, checks their evidence, and replies with the result. Tap an agent in the chat to see its goal, verdict and desktop."
                )
                FAQItem(
                    q: "What does the agent host need?",
                    a: """
                    A Mac or Linux machine you reach over SSH, with Podman and the two sshido images built on it. About & help › Agent host guide has the commands.

                    Then turn agents on in Settings › Agents, pick the host, and tap the box button under Host. The app starts the agents daemon over SSH.
                    """
                )
                FAQItem(
                    q: "Which models can agents use?",
                    a: "Claude Code, Codex, Gemini CLI and Grok with your own subscriptions (tap Sign in in Settings › Agents), or a local model behind an OpenAI-compatible endpoint with the Responses API. sshido never sits between your server and the model provider."
                )
                FAQItem(
                    q: "Can agents use my MCP servers and connectors?",
                    a: """
                    On a Linux host, yes. Claude agents use that host's own Claude Code setup in ~/.claude and ~/.claude.json: your claude.ai sign-in, connectors, plugins and MCP servers. They use them without asking.

                    On a Mac host, agents keep their own sign-in and get none of these, because macOS keeps Claude Code's sign-ins in the Keychain. Codex, Gemini, Grok and local-model agents do not get MCP servers from the host.
                    """
                )
            }
            Section(header: SectionLabel("Connectivity")) {
                FAQItem(
                    q: "Connecting from LTE or another network?",
                    a: "Install Tailscale on both your phone and Mac. Use the tailnet hostname (e.g. mac.tail-xxxxx.ts.net) as the host. No port forwarding."
                )
                FAQItem(
                    q: "Do sessions survive closing the app?",
                    a: "Yes. tmux keeps the session alive on the server. Reopen sshido and tap the session to reattach."
                )
            }
            Section(header: SectionLabel("Auth")) {
                FAQItem(
                    q: "Key or password?",
                    a: """
                    Keys are preferred — stored in the iOS Keychain, accessible only while your device is unlocked.

                    Password auth works for Tailscale and dev boxes where you don't want to manage keys.
                    """
                )
            }
            Section(header: SectionLabel("Open-source libraries")) {
                FAQItem(
                    q: "What open-source software does sshido use?",
                    a: """
                    Direct dependencies:
                    • Citadel — SSH protocol (github.com/orlandos-nl/Citadel)
                    • SwiftTerm — terminal emulator (github.com/migueldeicaza/SwiftTerm)
                    • Sentry Cocoa — crash reporting (github.com/getsentry/sentry-cocoa)
                    • Lottie — animations (github.com/airbnb/lottie-ios)

                    Transitive (pulled in by the above):
                    • SwiftNIO, SwiftNIO SSH, SwiftCrypto
                    • swift-log, swift-collections, swift-atomics
                    • swift-asn1, swift-system, swift-argument-parser
                    • BigInt

                    Each library ships under its own license.
                    """
                )
            }
            Section(header: SectionLabel("Privacy")) {
                NavigationLink {
                    PrivacyPolicyView()
                } label: {
                    Text("Privacy Policy").font(DS.Font.callout).bold()
                        .foregroundStyle(DS.Color.textPrimary)
                }
                .tideRow()
            }
        }
        .tideList()
        .accentColor(DS.Color.textSecondary)
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
        .tint(DS.Color.textSecondary)
        .tideRow()
    }
}
#endif

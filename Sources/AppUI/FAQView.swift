#if canImport(UIKit)
import SwiftUI

public struct FAQView: View {
    public init() {}

    public var body: some View {
        List {
            Section("Push notifications") {
                FAQItem(
                    q: "How do I set up push alerts?",
                    a: """
                    sshido needs a small relay binary running on your dev server. Source + README live at github.com/json9512/sshido under server/sshido-relay/. Build and run it:

                    git clone https://github.com/json9512/sshido.git
                    cd sshido/server/sshido-relay
                    go build -o sshido-relay .
                    ./sshido-relay -addr 0.0.0.0:8787 \\
                      -public-url http://<your-host>:8787 \\
                      -bundle-id com.sshido.app \\
                      -key ~/AuthKey_XXXXXXXXXX.p8 \\
                      -key-id XXXXXXXXXX \\
                      -team-id XXXXXXXXXX

                    Get the .p8 / key-id / team-id from Apple Developer → Certificates, Keys → Keys → + → "Apple Push Notifications service (APNs)".

                    Then in the app: Settings → Push server → paste the relay URL → Save & subscribe. Copy the Notify URL the relay returns and put it in ~/.claude/hooks/notify.sh on your dev server. Done.
                    """
                )
                FAQItem(
                    q: "Tell your agent to set it up for you",
                    a: """
                    Because you probably have Claude Code running on the very server that needs the relay, ask it:

                    "Clone github.com/json9512/sshido, cd server/sshido-relay, read the README, and set up the relay as a systemd user unit. I have an APNs key at ~/AuthKey_XXXX.p8 with key-id XXXX and team-id XXXX. Make it reachable at <your-host>:8787."

                    The README under server/sshido-relay/ has everything an agent needs — flags, systemd template, Claude Code hook example, and a Linux cross-compile snippet.
                    """
                )
                FAQItem(
                    q: "I'm not getting notifications",
                    a: "Check: (a) APNs device token shows in the Device section; (b) the relay is reachable (curl the Notify URL with a test payload); (c) notifications are allowed for sshido in iOS Settings; (d) the hook script in ~/.claude/hooks/ is executable and references the Notify URL; (e) if you installed sshido from TestFlight/App Store, run the relay with -production."
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
    }
}

private struct FAQItem: View {
    let q: String
    let a: String
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text(a)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        } label: {
            Text(q).font(.callout).bold()
        }
    }
}
#endif

#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct AgentsFeature: AppFeature {
    let id = "agents"

    var home: [HomeEntry] {
        [HomeEntry(id: "agents", order: 10, title: "Agents") { AnyView(AgentsHomeSection()) }]
    }

    var settings: [SettingsEntry] {
        [
            SettingsEntry(id: "agents", group: .agents, order: 0, icon: "person.2.wave.2", title: "Agents",
                          summary: { _ in
                              let settings = AgentModeController.shared.settings
                              guard settings.enabled else { return "Off" }
                              let host = await AgentModeController.shared.host()?.name ?? "No host"
                              return "\(host) · \(settings.orchestrator.isFrontier ? settings.orchestrator.label : "Local")"
                          },
                          destination: { AnyView(AgentModeSettingsView()) }),
            SettingsEntry(id: "agents-guide", group: .agents, order: 1, icon: "book", title: "Set up a host",
                          summary: { _ in nil },
                          destination: { AnyView(AgentSetupGuideView()) }),
        ]
    }
}

struct AgentsHomeSection: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.homeIsSplit) private var split
    @ObservedObject private var agents = AgentModeController.shared

    var body: some View {
        if agents.settings.enabled {
            Section {
                Button { router.openAgentChats(regular: split) } label: { row }
                    .buttonStyle(.plain)
                    .listRowBackground(split && router.agentChatsOpenInDetail ? DS.Color.accentMuted : DS.Color.surface1)
            } header: {
                SectionLabel("Agents")
            }
        }
    }

    private var row: some View {
        TideRow(icon: "person.2.wave.2", title: "Agents", subtitle: subtitle) {
            HStack(spacing: DS.Spacing.sm) {
                if working > 0 { AnimatedGlyph(animation: .working, size: CGSize(width: 36, height: 20)) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }

    private var working: Int {
        agents.agents.filter { $0.status == .working || $0.status == .starting }.count
    }

    private var subtitle: String {
        guard agents.historyLoaded else { return "Chats" }
        let chats = agents.chats.count
        let base = chats == 0 ? "No chats yet" : "\(chats) \(chats == 1 ? "chat" : "chats")"
        return working > 0 ? "\(base) · \(working) working" : base
    }
}

struct AgentSetupGuideView: View {
    var body: some View {
        GuideView(title: "Set up a host", steps: [
            GuideStep(icon: "shippingbox", title: "Install Podman",
                      text: "Agents run in Podman containers on a Mac or Linux machine you already reach over SSH. On a Mac, Podman runs a small Linux VM; give it enough memory for several agents.",
                      code: "brew install podman\npodman machine init --memory 8192\npodman machine start"),
            GuideStep(icon: "hammer", title: "Build the images",
                      text: "Two images: the daemon that runs the chats, and the agent image with Claude Code, Codex, Gemini CLI, Grok, a browser and a desktop.",
                      code: "git clone https://github.com/json9512/sshido.git\ncd sshido/server/sshido-agents\npodman build -f images/daemon/Containerfile -t localhost/sshido-agents:latest .\npodman build -f images/agent/Containerfile -t localhost/sshido-agent:latest ."),
            GuideStep(icon: "switch.2", title: "Turn on agent mode",
                      text: "In Settings › Agents, turn agents on, pick the host, then tap the box button under Host. The app starts the daemon over SSH and connects pushes to it."),
            GuideStep(icon: "cpu", title: "Choose models",
                      text: "Frontier harnesses use your own subscriptions: tap Sign in and finish the login in the terminal that opens. Local models need an OpenAI-compatible endpoint with the Responses API (llama-swap, Ollama, LM Studio), as seen from inside a container.",
                      code: "http://host.containers.internal:8083/v1"),
            GuideStep(icon: "puzzlepiece.extension", title: "Connectors and plugins (Linux hosts)",
                      text: "On a Linux host, Claude agents use the host's own Claude Code setup in ~/.claude and ~/.claude.json: your claude.ai sign-in, connectors, plugins and MCP servers. They use them without asking. On a Mac host, agents keep their own sign-in and get no host plugins or MCP servers, because macOS keeps those sign-ins in the Keychain. An MCP server at 127.0.0.1 on the host is not reachable from agents; use host.containers.internal instead."),
            GuideStep(icon: "folder", title: "Share folders (optional)",
                      text: "Host folders are mounted read-only at /host/<name>. Agents copy what they change into their shared /workspace. On a Mac, only folders under /Users are visible to Podman."),
            GuideStep(icon: "bubble.left.and.bubble.right", title: "Start a chat",
                      text: "Tell the orchestrator what you need. It plans, starts subagents when that helps, checks their evidence, and reports back. Tap an agent to see its goal, verdict, track record and desktop."),
        ], link: ("Agent mode on GitHub", "https://github.com/json9512/sshido/tree/main/server/sshido-agents"))
    }
}

extension GuideStep {
    init(icon: String, title: String, text: String) {
        self.init(icon: icon, title: title, text: text, code: nil)
    }
}
#endif

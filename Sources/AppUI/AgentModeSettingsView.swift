#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct AgentModeSettingsView: View {
    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var agents = AgentModeController.shared
    @State private var hosts: [RemoteHost] = []
    @State private var orchestratorModel = ""
    @State private var workerModel = ""
    @State private var workerLocalModel = ""
    @State private var localURL = ""
    @State private var newFolder = ""
    @State private var confirmReset = false

    var body: some View {
        Form {
            hostSection
            orchestratorSection
            subagentSection
            if agents.settings.usesLocalEndpoint { localSection }
            hostFoldersSection
            signInSection
            setupSection
        }
        .dsFormStyle()
        .navigationTitle("Agent mode")
        .task {
            hosts = await HostStore.shared.all()
            orchestratorModel = agents.settings.orchestratorModel
            workerModel = agents.settings.workerModel
            workerLocalModel = agents.settings.workerLocalModel
            localURL = agents.settings.localURL
        }
        .onChange(of: orchestratorModel) { _, v in agents.update { $0.with(orchestratorModel: v) } }
        .onChange(of: workerModel) { _, v in agents.update { $0.with(workerModel: v) } }
        .onChange(of: localURL) { _, v in agents.update { $0.with(localURL: v) } }
        .onChange(of: workerLocalModel) { _, v in agents.update { $0.with(workerLocalModel: v) } }
        .confirmationDialog("Remove the agents and the chat history on the host?", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Remove agents", role: .destructive) { Task { await agents.resetHost() } }
        } message: {
            Text("Logins and the shared workspace stay. Needed after changing the orchestrator.")
        }
    }

    enum ModelKind: String, CaseIterable, Identifiable {
        case frontier, local, decides

        var id: String { rawValue }

        var label: String {
            switch self {
            case .frontier: return "Frontier"
            case .local: return "Local"
            case .decides: return "Auto"
            }
        }
    }

    private var orchestratorKind: Binding<ModelKind> {
        Binding(
            get: { agents.settings.orchestrator.isFrontier ? .frontier : .local },
            set: { kind in
                agents.update { s in
                    kind == .local ? s.with(orchestrator: .local)
                        : s.with(orchestrator: s.orchestrator.isFrontier ? s.orchestrator : .claude)
                }
            }
        )
    }

    private var subagentKind: Binding<ModelKind> {
        Binding(
            get: {
                if agents.settings.workerChoice == .orchestrator { return .decides }
                return agents.settings.worker.isFrontier ? .frontier : .local
            },
            set: { kind in
                agents.update { s in
                    switch kind {
                    case .decides:
                        return s.with(workerChoice: .orchestrator)
                    case .local:
                        return s.with(workerChoice: .fixed).with(worker: .local)
                    case .frontier:
                        return s.with(workerChoice: .fixed).with(worker: s.worker.isFrontier ? s.worker : .claude)
                    }
                }
            }
        )
    }

    private func kindPicker(_ selection: Binding<ModelKind>, options: [ModelKind]) -> some View {
        Picker("Models", selection: selection) {
            ForEach(options) { kind in Text(kind.label).tag(kind) }
        }
        .pickerStyle(.segmented)
        .dsRow()
    }

    private func frontierPicker(_ harness: AgentHarness, pick: @escaping (AgentHarness) -> Void) -> some View {
        Picker(selection: Binding(get: { harness }, set: pick)) {
            ForEach(AgentHarness.frontier) { h in Text(h.label).tag(h) }
        } label: {
            Text("Harness").font(DS.Font.rowTitle)
        }
        .dsRow()
    }

    private func modelField(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .dsRow()
    }

    private var orchestratorSection: some View {
        Section {
            kindPicker(orchestratorKind, options: [.frontier, .local])
            if agents.settings.orchestrator.isFrontier {
                frontierPicker(agents.settings.orchestrator) { h in agents.update { $0.with(orchestrator: h) } }
                modelField("Model (optional)", $orchestratorModel)
            } else {
                modelField("Local model name, e.g. qwen3.6:35b", $orchestratorModel)
            }
        } header: {
            DSSectionHeader("Orchestrator")
        } footer: {
            Text("You talk to the orchestrator. It works out what you need, plans, starts subagents when the work calls for them, checks their evidence and gives each a verdict.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var subagentSection: some View {
        Section {
            kindPicker(subagentKind, options: [.frontier, .local, .decides])
            switch subagentKind.wrappedValue {
            case .frontier:
                frontierPicker(agents.settings.worker) { h in agents.update { $0.with(worker: h) } }
                modelField("Model (optional)", $workerModel)
            case .local:
                modelField("Local model name, e.g. qwen3.6:35b", $workerModel)
            case .decides:
                ForEach(AgentHarness.allCases) { h in
                    Toggle(isOn: Binding(
                        get: { agents.settings.workerAllowed.contains(h) },
                        set: { on in agents.update { $0.allowing(h, on) } }
                    )) {
                        Text(h.label).font(DS.Font.rowTitle)
                    }
                    .dsRow()
                }
                if agents.settings.workerAllowed.contains(.local) {
                    modelField("Local model name, e.g. qwen3.6:35b", $workerLocalModel)
                }
            }
            if let problem = agents.settings.problem {
                Text(problem).font(DS.Font.caption).foregroundStyle(DS.Color.warning).dsRow()
            }
        } header: {
            DSSectionHeader("Subagents")
        } footer: {
            Text(subagentFooter).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var subagentFooter: String {
        switch subagentKind.wrappedValue {
        case .frontier: return "Every subagent runs on this harness, each in its own Podman container with a shell, a browser and a desktop."
        case .local: return "Every subagent runs on this model at the local endpoint below: private and free per token, but weaker than frontier models."
        case .decides: return "Auto: the orchestrator picks one of the ticked kinds for each subagent: frontier for hard work, local for simple or private work."
        }
    }

    private var folderProblem: String? {
        newFolder.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : AgentModeSettings.hostDirectoryProblem(newFolder, among: agents.settings.hostDirectories)
    }

    private var hostFoldersSection: some View {
        Section {
            ForEach(agents.settings.hostDirectories, id: \.self) { dir in
                HStack {
                    Image(systemName: "folder").foregroundStyle(DS.Color.accent)
                    Text(dir).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textPrimary).lineLimit(2)
                    Spacer()
                    Button(role: .destructive) {
                        agents.update { $0.with(hostDirectories: $0.hostDirectories.filter { $0 != dir }) }
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(DS.Color.error)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Stop sharing \(dir)")
                }
                .dsRow()
            }
            HStack {
                TextField("/Users/you/code", text: $newFolder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(DS.Font.monoSmall)
                Button("Add") {
                    let dir = AgentModeSettings.normalizedHostDirectory(newFolder)
                    agents.update { $0.with(hostDirectories: $0.hostDirectories + [dir]) }
                    newFolder = ""
                }
                .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty || folderProblem != nil)
            }
            .dsRow()
            if let folderProblem {
                Text(folderProblem).font(DS.Font.caption).foregroundStyle(DS.Color.warning).dsRow()
            }
        } header: {
            DSSectionHeader("Host folders")
        } footer: {
            Text("Every agent can read these host folders, read-only, at /host/<folder name>, and copies what it needs into /workspace. On a Mac, Podman can only see folders under /Users. Tap Apply settings below after changing this list.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var hostSection: some View {
        Section {
            Picker(selection: Binding(
                get: { agents.settings.hostID },
                set: { id in agents.update { $0.with(hostID: id) } }
            )) {
                Text("Choose a host").tag(UUID?.none)
                ForEach(hosts) { host in
                    Text(host.name).tag(UUID?.some(host.id))
                }
            } label: {
                Text("Agents host").font(DS.Font.rowTitle)
            }
            .dsRow()
        } header: {
            DSSectionHeader("Host")
        } footer: {
            Text("Agents run in Podman on this host, reached over its SSH login. Nothing runs on this phone except the chat.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var localSection: some View {
        Section {
            TextField("http://host.containers.internal:8083/v1", text: $localURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .dsRow()
        } header: {
            DSSectionHeader("Local models")
        } footer: {
            Text("An OpenAI-compatible endpoint (llama-swap, Ollama, LM Studio) as seen from inside a container. It must support the Responses API, which Codex uses.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var signInSection: some View {
        Section {
            ForEach(agents.settings.signInHarnesses) { harness in
                Button {
                    router.sheet = nil
                    Task { await agents.signIn(harness, router: router) }
                } label: {
                    Label("Sign in to \(harness.label)", systemImage: "person.badge.key")
                        .font(DS.Font.rowTitle)
                }
                .disabled(agents.settings.podmanPath.isEmpty)
                .dsRow()
            }
        } header: {
            DSSectionHeader("Sign in")
        } footer: {
            Text("Opens a terminal on the host with the harness's own sign-in; finish it on this phone. The login is kept for every agent. Check each provider's terms before running agents in parallel on a subscription.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var setupSection: some View {
        Section {
            Button {
                Task { await agents.checkHost() }
            } label: {
                Label("Check host", systemImage: "stethoscope").font(DS.Font.rowTitle)
            }
            .disabled(agents.busy || agents.settings.hostID == nil)
            .dsRow()
            Button {
                Task { await agents.setUpHost() }
            } label: {
                Label("Set up host", systemImage: "shippingbox").font(DS.Font.rowTitle)
            }
            .disabled(agents.busy || agents.settings.hostID == nil || agents.settings.problem != nil)
            .dsRow()
            Button {
                Task { await agents.applySettings() }
            } label: {
                Label("Apply settings", systemImage: "arrow.triangle.2.circlepath").font(DS.Font.rowTitle)
            }
            .disabled(agents.busy || agents.settings.hostID == nil || agents.settings.problem != nil)
            .dsRow()
            Button(role: .destructive) {
                confirmReset = true
            } label: {
                Label("Remove agents", systemImage: "trash").font(DS.Font.rowTitle)
            }
            .disabled(agents.busy || agents.settings.hostID == nil)
            .dsRow()
            if agents.busy {
                ProgressView().dsRow()
            }
            ForEach(Array(agents.setupLog.enumerated()), id: \.offset) { _, line in
                Text(line).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary).dsRow()
            }
        } header: {
            DSSectionHeader("Host setup")
        } footer: {
            Text("Needs Podman and the two sshido agent images on the host. Apply settings restarts the daemon with the settings above; running turns are interrupted, and chats and logins stay.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }
}
#endif

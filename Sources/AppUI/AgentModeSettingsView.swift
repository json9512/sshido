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
    @State private var localURL = ""
    @State private var pickerModel = ""
    @State private var newFolder = ""
    @State private var confirmReset = false

    var body: some View {
        Form {
            hostSection
            modelSection(title: "Orchestrator",
                         footer: "Reads your messages, splits the work and reports back.",
                         harness: agents.settings.orchestrator, model: $orchestratorModel,
                         pick: { h in agents.update { s in s.with(orchestrator: h) } })
            modelSection(title: "Workers",
                         footer: "Each worker runs in its own Podman container. The orchestrator may pick a different harness per task.",
                         harness: agents.settings.worker, model: $workerModel,
                         pick: { h in agents.update { s in s.with(worker: h) } })
            groupSection
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
            localURL = agents.settings.localURL
            pickerModel = agents.settings.pickerModel
        }
        .onChange(of: orchestratorModel) { _, v in agents.update { $0.with(orchestratorModel: v) } }
        .onChange(of: workerModel) { _, v in agents.update { $0.with(workerModel: v) } }
        .onChange(of: localURL) { _, v in agents.update { $0.with(localURL: v) } }
        .onChange(of: pickerModel) { _, v in agents.update { $0.with(pickerModel: v) } }
        .confirmationDialog("Remove the agents and the chat history on the host?", isPresented: $confirmReset,
                            titleVisibility: .visible) {
            Button("Remove agents", role: .destructive) { Task { await agents.resetHost() } }
        } message: {
            Text("Logins and the shared workspace stay. Needed after changing the orchestrator.")
        }
    }

    private var groupSection: some View {
        Section {
            TextField("Picker model, e.g. qwen3.6:35b-instruct", text: $pickerModel)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .dsRow()
        } header: {
            DSSectionHeader("Group chats")
        } footer: {
            Text("In a group chat, this model chooses who speaks next. It runs on the local endpoint below, answers with one letter, and must be an instruct (non-thinking) model whose server returns logprobs. Leave empty to turn group chats off.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
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

    private func modelSection(title: String, footer: String, harness: AgentHarness, model: Binding<String>,
                              pick: @escaping (AgentHarness) -> Void) -> some View {
        Section {
            Picker(selection: Binding(get: { harness }, set: pick)) {
                ForEach(AgentHarness.allCases) { h in
                    Text(h.label).tag(h)
                }
            } label: {
                Text("Harness").font(DS.Font.rowTitle)
            }
            .dsRow()
            TextField(harness == .local ? "Model name (required)" : "Model (optional)", text: model)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .dsRow()
        } header: {
            DSSectionHeader(title)
        } footer: {
            Text(footer).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
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

    private var signInHarnesses: [AgentHarness] {
        let orchestrator = agents.settings.orchestrator
        let worker = agents.settings.worker
        let both = worker == orchestrator ? [orchestrator] : [orchestrator, worker]
        return both.filter { $0.loginCommand != nil }
    }

    private var signInSection: some View {
        Section {
            ForEach(signInHarnesses) { harness in
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
            .disabled(agents.busy || agents.settings.hostID == nil)
            .dsRow()
            Button {
                Task { await agents.applySettings() }
            } label: {
                Label("Apply settings", systemImage: "arrow.triangle.2.circlepath").font(DS.Font.rowTitle)
            }
            .disabled(agents.busy || agents.settings.hostID == nil)
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

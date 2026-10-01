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
    @Environment(\.services) private var services
    @ObservedObject private var agents = AgentModeController.shared
    @State private var hosts: [RemoteHost] = []
    @State private var orchestratorModel = ""
    @State private var workerModel = ""
    @State private var workerLocalModel = ""
    @State private var localURL = ""
    @State private var newFolder = ""
    @State private var confirmReset = false

    enum ModelKind: String, CaseIterable, Identifiable {
        case frontier, local, auto

        var id: String { rawValue }

        var label: String {
            switch self {
            case .frontier: return "Frontier"
            case .local: return "Local"
            case .auto: return "Auto"
            }
        }
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(get: { agents.settings.enabled }, set: { on in agents.update { $0.with(enabled: on) } })) {
                    TideRow(icon: "person.2.wave.2", title: "Agents")
                }
                .tideRow()
                Picker(selection: Binding(get: { agents.settings.hostID }, set: { id in agents.update { $0.with(hostID: id) } })) {
                    Text("None").tag(UUID?.none)
                    ForEach(hosts) { Text($0.name).tag(UUID?.some($0.id)) }
                } label: {
                    TideRow(icon: "server.rack", title: "Host")
                }
                .tideRow()
            }
            orchestratorSection
            subagentSection
            if agents.settings.usesLocalEndpoint { localSection }
            foldersSection
            if !agents.settings.signInHarnesses.isEmpty { signInSection }
            setupSection
        }
        .tideList()
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDismissButton()
        .task {
            hosts = await services.hosts.all()
            orchestratorModel = agents.settings.orchestratorModel
            workerModel = agents.settings.workerModel
            workerLocalModel = agents.settings.workerLocalModel
            localURL = agents.settings.localURL
            if agents.settings.usesLocalEndpoint && agents.localModels.isEmpty { await agents.refreshLocalModels() }
        }
        .onChange(of: orchestratorModel) { _, v in agents.update { $0.with(orchestratorModel: v) } }
        .onChange(of: workerModel) { _, v in agents.update { $0.with(workerModel: v) } }
        .onChange(of: workerLocalModel) { _, v in agents.update { $0.with(workerLocalModel: v) } }
        .onChange(of: localURL) { _, v in agents.update { $0.with(localURL: v) } }
        .confirmationDialog("Remove all agents and chats on the host?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await agents.resetHost() } }
        } message: {
            Text("Logins and the shared workspace stay.")
        }
    }

    private var orchestratorKind: Binding<ModelKind> {
        Binding(
            get: { agents.settings.orchestrator.isFrontier ? .frontier : .local },
            set: { kind in
                agents.update { s in
                    kind == .local ? s.with(orchestrator: .local) : s.with(orchestrator: s.orchestrator.isFrontier ? s.orchestrator : .claude)
                }
            }
        )
    }

    private var subagentKind: Binding<ModelKind> {
        Binding(
            get: {
                if agents.settings.workerChoice == .orchestrator { return .auto }
                return agents.settings.worker.isFrontier ? .frontier : .local
            },
            set: { kind in
                agents.update { s in
                    switch kind {
                    case .auto: return s.with(workerChoice: .orchestrator)
                    case .local: return s.with(workerChoice: .fixed).with(worker: .local)
                    case .frontier: return s.with(workerChoice: .fixed).with(worker: s.worker.isFrontier ? s.worker : .claude)
                    }
                }
            }
        )
    }

    private func kindPicker(_ selection: Binding<ModelKind>, options: [ModelKind]) -> some View {
        Picker("Models", selection: selection) {
            ForEach(options) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .tideRow()
    }

    private func harnessPicker(_ harness: AgentHarness, pick: @escaping (AgentHarness) -> Void) -> some View {
        Picker(selection: Binding(get: { harness }, set: pick)) {
            ForEach(AgentHarness.frontier) { Text($0.label).tag($0) }
        } label: {
            TideRow(icon: "sparkles", title: "Harness")
        }
        .tideRow()
    }

    private func modelField(_ prompt: String, _ text: Binding<String>) -> some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "cpu").foregroundStyle(DS.Color.textTertiary).frame(width: 26)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(DS.Font.monoBody)
        }
        .frame(minHeight: DS.hitTarget)
        .tideRow()
    }

    @ViewBuilder
    private func localModelPicker(_ selection: Binding<String>) -> some View {
        if agents.localModels.isEmpty {
            HStack(spacing: DS.Spacing.sm) {
                modelField("Local model, e.g. qwen3.6:35b", selection)
                refreshModelsButton
            }
        } else {
            HStack(spacing: DS.Spacing.sm) {
                Menu {
                    ForEach(agents.localModels, id: \.self) { model in
                        Button { selection.wrappedValue = model } label: {
                            if model == selection.wrappedValue { Label(model, systemImage: "checkmark") } else { Text(model) }
                        }
                    }
                } label: {
                    TideRow(icon: "cpu", title: selection.wrappedValue.isEmpty ? "Choose a model" : selection.wrappedValue) {
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .accessibilityLabel("Model, \(selection.wrappedValue.isEmpty ? "none" : selection.wrappedValue)")
                refreshModelsButton
            }
            .tideRow()
        }
    }

    private var refreshModelsButton: some View {
        Group {
            if agents.loadingLocalModels {
                ProgressView().tint(DS.Color.accent).frame(width: 36, height: 36)
            } else {
                IconButton(systemName: "arrow.clockwise", label: "Load models from the endpoint", kind: .quiet, size: 36) {
                    Task { await agents.refreshLocalModels() }
                }
                .disabled(agents.settings.hostID == nil)
            }
        }
    }

    private var orchestratorSection: some View {
        Section {
            kindPicker(orchestratorKind, options: [.frontier, .local])
            if agents.settings.orchestrator.isFrontier {
                harnessPicker(agents.settings.orchestrator) { h in agents.update { $0.with(orchestrator: h) } }
                modelField("Model (optional)", $orchestratorModel)
            } else {
                localModelPicker($orchestratorModel)
            }
        } header: {
            SectionLabel("Orchestrator")
        }
    }

    private var subagentSection: some View {
        Section {
            kindPicker(subagentKind, options: [.frontier, .local, .auto])
            switch subagentKind.wrappedValue {
            case .frontier:
                harnessPicker(agents.settings.worker) { h in agents.update { $0.with(worker: h) } }
                modelField("Model (optional)", $workerModel)
            case .local:
                localModelPicker($workerModel)
            case .auto:
                ForEach(AgentHarness.allCases) { h in
                    Toggle(isOn: Binding(get: { agents.settings.workerAllowed.contains(h) }, set: { on in agents.update { $0.allowing(h, on) } })) {
                        Text(h.label).font(DS.Font.rowTitle)
                    }
                    .tideRow()
                }
                if agents.settings.workerAllowed.contains(.local) {
                    localModelPicker($workerLocalModel)
                }
            }
            if let problem = agents.settings.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.warning).tideRow()
            }
        } header: {
            SectionLabel("Subagents")
        }
    }

    private var localSection: some View {
        Section {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "link").foregroundStyle(DS.Color.textTertiary).frame(width: 26)
                TextField("http://host.containers.internal:8083/v1", text: $localURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(DS.Font.monoSmall)
            }
            .frame(minHeight: DS.hitTarget)
            .tideRow()
        } header: {
            SectionLabel("Local endpoint")
        }
    }

    private var folderProblem: String? {
        newFolder.trimmingCharacters(in: .whitespaces).isEmpty
            ? nil
            : AgentModeSettings.hostDirectoryProblem(newFolder, among: agents.settings.hostDirectories)
    }

    private var foldersSection: some View {
        Section {
            ForEach(agents.settings.hostDirectories, id: \.self) { dir in
                TideRow(icon: "folder", title: dir)
                    .tideRow()
                    .swipeActions {
                        Button {
                            agents.update { $0.with(hostDirectories: $0.hostDirectories.filter { $0 != dir }) }
                        } label: { Label("Remove", systemImage: "trash") }
                            .tint(DS.Color.error)
                    }
            }
            HStack(spacing: DS.Spacing.sm) {
                TextField("/Users/you/code", text: $newFolder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(DS.Font.monoSmall)
                IconButton(systemName: "plus", label: "Share folder", kind: .primary, size: 36) {
                    let dir = AgentModeSettings.normalizedHostDirectory(newFolder)
                    agents.update { $0.with(hostDirectories: $0.hostDirectories + [dir]) }
                    newFolder = ""
                }
                .disabled(newFolder.trimmingCharacters(in: .whitespaces).isEmpty || folderProblem != nil)
            }
            .tideRow()
            if let folderProblem {
                Text(folderProblem).font(DS.Font.caption).foregroundStyle(DS.Color.warning).tideRow()
            }
        } header: {
            SectionLabel("Read-only host folders")
        }
    }

    private var signInSection: some View {
        Section {
            ForEach(agents.settings.signInHarnesses) { harness in
                Button {
                    router.sheet = nil
                    Task { await agents.signIn(harness, router: router) }
                } label: {
                    TideRow(icon: "person.badge.key", title: harness.label) {
                        Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.Color.textTertiary)
                    }
                }
                .disabled(agents.settings.podmanPath.isEmpty)
                .tideRow()
            }
        } header: {
            SectionLabel("Sign in")
        }
    }

    private var setupSection: some View {
        Section {
            HStack(spacing: DS.Spacing.lg) {
                action("stethoscope", "Check host") { await agents.checkHost() }
                action("shippingbox", "Set up host") { await agents.setUpHost() }
                action("arrow.triangle.2.circlepath", "Apply settings") { await agents.applySettings() }
                Spacer()
                IconButton(systemName: "trash", label: "Remove agents", kind: .destructive) { confirmReset = true }
                    .disabled(agents.busy || agents.settings.hostID == nil)
            }
            .tideRow()
            if agents.busy {
                HStack(spacing: DS.Spacing.md) {
                    AnimatedGlyph(animation: .working, size: CGSize(width: 48, height: 24))
                    Spacer()
                }
                .tideRow()
            }
            ForEach(Array(agents.setupLog.reversed().enumerated()), id: \.offset) { _, line in
                Text(line).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textSecondary).tideRow()
            }
        } header: {
            SectionLabel("Host")
        }
    }

    private func action(_ icon: String, _ label: String, run: @escaping () async -> Void) -> some View {
        IconButton(systemName: icon, label: label) { Task { await run() } }
            .disabled(agents.busy || agents.settings.hostID == nil || agents.settings.problem != nil)
    }
}
#endif

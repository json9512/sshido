#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct AgentRecordView: View {
    let agentID: String

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var agents = AgentModeController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var trackRecord: TrackRecord = .loading
    @State private var desktop: DesktopState = .closed
    @State private var confirmStop = false

    enum TrackRecord: Equatable {
        case loading
        case loaded(String)
        case failed(String)
    }

    enum DesktopState: Equatable {
        case closed
        case opening
        case open(URL)
        case failed(String)
    }

    private var agent: AgentInfo? { agents.agents.first { $0.id == agentID } }

    var body: some View {
        Form {
            if let agent {
                summarySection(agent)
                recordSection(agent)
                trackRecordSection
                actionsSection(agent)
            } else {
                Text("This agent is gone.").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).dsRow()
            }
        }
        .dsFormStyle()
        .navigationTitle(agent?.name ?? "Agent")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task(id: agent?.updatedAt) { await loadTrackRecord() }
        .sheet(isPresented: Binding(
            get: { if case .open = desktop { return true } else { return false } },
            set: { if !$0 { closeDesktop() } }
        )) {
            if case .open(let url) = desktop {
                SafariSheet(url: url) { closeDesktop() }.ignoresSafeArea()
            }
        }
        .confirmationDialog("Stop \(agent?.name ?? "this agent")?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop agent", role: .destructive) {
                guard let agent else { return }
                Task { await agents.stop(agent: agent) }
            }
        } message: {
            Text("Its container stops. Its work record and files stay.")
        }
        .onDisappear { closeDesktop() }
    }

    private func summarySection(_ agent: AgentInfo) -> some View {
        Section {
            row("Role", agent.isOrchestrator ? "Orchestrator" : "Subagent")
            row("Runs on", [agent.harness, agent.model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
            row("Right now", Self.label(agent.status))
            if let task = agent.task, !task.isEmpty {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Task").font(DS.Font.captionMedium).foregroundStyle(DS.Color.textSecondary)
                    Text(task).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
                }
                .dsRow()
            }
        } header: {
            DSSectionHeader("Agent")
        }
    }

    private func recordSection(_ agent: AgentInfo) -> some View {
        Section {
            field("Goal", agent.goal, empty: agent.isOrchestrator ? "Not set yet. The orchestrator sets it after reading your request." : "Not set.")
            HStack {
                Text("Status").font(DS.Font.rowTitle)
                Spacer()
                workStatusBadge(agent.workStatus)
            }
            .dsRow()
            field("Verification", agent.verification, empty: "No evidence recorded yet.")
            verdictRow(agent)
        } header: {
            DSSectionHeader("Work record")
        } footer: {
            Text("Kept on the host in /workspace/.sshido/records/\(agent.id)/. Every turn of the agent starts from it.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private var trackRecordSection: some View {
        Section {
            switch trackRecord {
            case .loading:
                ProgressView().frame(maxWidth: .infinity).dsRow()
            case .failed(let reason):
                HStack(alignment: .top) {
                    Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                    Spacer()
                    Button("Retry") { Task { await loadTrackRecord() } }.font(DS.Font.captionMedium)
                }
                .dsRow()
            case .loaded(let text) where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                Text("Nothing recorded yet.").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).dsRow()
            case .loaded(let text):
                ForEach(Array(AgentTrackEntry.parse(text).reversed().enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(entry.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? entry.heading).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textTertiary)
                        Text(entry.body).font(DS.Font.caption).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
                    }
                    .dsRow()
                }
            }
        } header: {
            DSSectionHeader("Track record, newest first")
        }
    }

    private func actionsSection(_ agent: AgentInfo) -> some View {
        Section {
            Button {
                Task { await openDesktop(agent) }
            } label: {
                HStack {
                    Label("Watch its desktop", systemImage: "display").font(DS.Font.rowTitle)
                    Spacer()
                    if desktop == .opening { ProgressView() }
                }
            }
            .disabled(agent.status == .stopped || desktop == .opening)
            .dsRow()
            if case .failed(let reason) = desktop {
                Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.warning).dsRow()
            }
            Button {
                dismiss()
                Task { await agents.peek(agent, router: router) }
            } label: {
                Label("Peek in terminal", systemImage: "terminal").font(DS.Font.rowTitle)
            }
            .dsRow()
            if agent.status != .stopped {
                Button(role: .destructive) { confirmStop = true } label: {
                    Label("Stop agent", systemImage: "stop.circle").font(DS.Font.rowTitle)
                }
                .dsRow()
            }
        } footer: {
            Text("The desktop opens in the in-app browser over your SSH connection. You can watch and take over the mouse and keyboard.")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(DS.Font.rowTitle)
            Spacer()
            Text(value.isEmpty ? "–" : value).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
        }
        .dsRow()
    }

    private func field(_ title: String, _ value: String?, empty: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            Text(title).font(DS.Font.captionMedium).foregroundStyle(DS.Color.textSecondary)
            if let value, !value.isEmpty {
                Text(value).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
            } else {
                Text(empty).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .dsRow()
    }

    private func verdictRow(_ agent: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack {
                Text("Verdict").font(DS.Font.captionMedium).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                if let verdict = agent.verdict {
                    Label(verdict == .pass ? "Pass" : "Fail",
                          systemImage: verdict == .pass ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(DS.Font.captionMedium)
                        .foregroundStyle(verdict == .pass ? DS.Color.success : DS.Color.error)
                }
            }
            if agent.verdict != nil, let note = agent.verdictNote, !note.isEmpty {
                Text(note).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
            } else if agent.verdict == nil {
                Text(agent.isOrchestrator ? "The orchestrator judges its own work against your request before it answers." : "Waiting for the orchestrator's review.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .dsRow()
    }

    private func workStatusBadge(_ status: AgentWorkStatus?) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case .inProgress: return ("In progress", DS.Color.accent)
            case .blocked: return ("Blocked", DS.Color.warning)
            case .done: return ("Done", DS.Color.success)
            case nil: return ("Not started", DS.Color.textTertiary)
            }
        }()
        return Text(text)
            .font(DS.Font.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, DS.Spacing.sm)
            .padding(.vertical, DS.Spacing.xxs)
            .background(color.opacity(0.15), in: Capsule())
    }

    static func label(_ status: AgentStatus) -> String {
        switch status {
        case .starting: return "Starting"
        case .working: return "Working"
        case .idle: return "Idle"
        case .failed: return "Failed"
        case .stopped: return "Stopped"
        }
    }

    private func loadTrackRecord() async {
        guard let agent else { return }
        do {
            trackRecord = .loaded(try await agents.trackRecord(of: agent))
        } catch {
            trackRecord = .failed(AgentModeController.message(for: error))
        }
    }

    private func openDesktop(_ agent: AgentInfo) async {
        desktop = .opening
        do {
            desktop = .open(try await agents.openDesktop(of: agent))
        } catch {
            desktop = .failed(AgentModeController.message(for: error))
        }
    }

    private func closeDesktop() {
        guard desktop != .closed else { return }
        desktop = .closed
        Task { await agents.closeDesktop() }
    }
}
#endif

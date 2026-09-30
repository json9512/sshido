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
                Text("This agent is gone.").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).tideRow()
            }
        }
        .tideList()
        .navigationTitle(agent?.name ?? "Agent")
        .toolbarTitleDisplayMode(.inline)
        .sheetActions(cancel: { dismiss() })
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
                .tideRow()
            }
        } header: {
            SectionLabel("Agent")
        }
    }

    private func recordSection(_ agent: AgentInfo) -> some View {
        Section {
            field("Goal", agent.goal, empty: "Not set")
            HStack {
                Text("Status").font(DS.Font.rowTitle)
                Spacer()
                workStatusBadge(agent.workStatus)
            }
            .tideRow()
            field("Verification", agent.verification, empty: "No evidence yet")
            verdictRow(agent)
        } header: {
            SectionLabel("Work record")
        }
    }

    private var trackRecordSection: some View {
        Section {
            switch trackRecord {
            case .loading:
                AnimatedGlyph(animation: .working, size: CGSize(width: 48, height: 24)).frame(maxWidth: .infinity).tideRow()
            case .failed(let reason):
                HStack(alignment: .top) {
                    Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                    Spacer()
                    IconButton(systemName: "arrow.clockwise", label: "Retry", kind: .quiet, size: 36) { Task { await loadTrackRecord() } }
                }
                .tideRow()
            case .loaded(let text) where text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
                Text("Nothing yet").font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).tideRow()
            case .loaded(let text):
                ForEach(Array(AgentTrackEntry.parse(text).reversed().enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                        Text(entry.date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? entry.heading).font(DS.Font.monoSmall).foregroundStyle(DS.Color.textTertiary)
                        Text(entry.body).font(DS.Font.caption).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
                    }
                    .tideRow()
                }
            }
        } header: {
            SectionLabel("Track record, newest first")
        }
    }

    private func actionsSection(_ agent: AgentInfo) -> some View {
        Section {
            HStack(spacing: DS.Spacing.lg) {
                if desktop == .opening {
                    ProgressView().tint(DS.Color.accent).frame(width: DS.hitTarget, height: DS.hitTarget)
                } else {
                    IconButton(systemName: "display", label: "Watch its desktop", kind: .primary) { Task { await openDesktop(agent) } }
                        .disabled(agent.status == .stopped)
                }
                IconButton(systemName: "terminal", label: "Peek in terminal") {
                    dismiss()
                    Task { await agents.peek(agent, router: router) }
                }
                Spacer()
                if agent.status != .stopped {
                    IconButton(systemName: "stop.fill", label: "Stop agent", kind: .destructive) { confirmStop = true }
                }
            }
            .tideRow()
            if case .failed(let reason) = desktop {
                Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.warning).tideRow()
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(DS.Font.rowTitle)
            Spacer()
            Text(value.isEmpty ? "–" : value).font(DS.Font.body).foregroundStyle(DS.Color.textSecondary).lineLimit(1)
        }
        .tideRow()
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
        .tideRow()
    }

    private func verdictRow(_ agent: AgentInfo) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
            HStack {
                Text("Verdict").font(DS.Font.captionMedium).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                if let verdict = agent.verdict {
                    HStack(spacing: DS.Spacing.xs) {
                        AnimatedGlyph(animation: verdict == .pass ? .pass : .fail, loop: false, size: CGSize(width: 26, height: 26))
                        Text(verdict == .pass ? "Pass" : "Fail").font(DS.Font.captionMedium)
                            .foregroundStyle(verdict == .pass ? DS.Color.success : DS.Color.error)
                    }
                }
            }
            if agent.verdict != nil, let note = agent.verdictNote, !note.isEmpty {
                Text(note).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
            } else if agent.verdict == nil {
                Text(agent.isOrchestrator ? "Not judged yet" : "Waiting for review")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
        .tideRow()
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

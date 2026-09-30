#if canImport(UIKit)
import AVKit
import QuickLook
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif
#if canImport(sshidoUI)
import sshidoUI
#endif

struct AgentChatView: View {
    let chatID: String

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var agents = AgentModeController.shared
    @State private var draft = ""
    @State private var dictator = SpeechDictator()
    @State private var voiceEnabled = false
    @State private var dictationLocaleID = ""
    @State private var notice: String?
    @State private var selectedAgent: AgentInfo?

    private var chat: AgentChat? { agents.chat(chatID) }
    private var chatAgents: [AgentInfo] { agents.agents(in: chatID) }
    private var chatMessages: [AgentChatMessage] { agents.messages(in: chatID) }
    private var isGroup: Bool { chat?.kind == .group }

    var body: some View {
        VStack(spacing: 0) {
            if !chatAgents.isEmpty { agentStrip }
            AgentConnectionBanner()
            if agents.historyLoaded && chat == nil {
                ContentUnavailableView("Chat removed", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            } else {
                messageList
                composer
            }
        }
        .background(DS.Color.surface0)
        .navigationTitle(chat?.title ?? "Agents")
        .toolbarTitleDisplayMode(.inline)
        .task {
            let appearance = await AppearanceStore.shared.appearance
            voiceEnabled = appearance.voiceDictationEnabled
            dictationLocaleID = appearance.dictationLocaleID
        }
        .onAppear { agents.hold() }
        .onDisappear {
            dictator.cancel()
            agents.release()
        }
        .confirmationDialog(selectedAgent?.name ?? "", isPresented: Binding(
            get: { selectedAgent != nil }, set: { if !$0 { selectedAgent = nil } }
        ), titleVisibility: .visible, presenting: selectedAgent) { agent in
            Button("Peek in terminal") { Task { await agents.peek(agent, router: router) } }
            if agent.status != .stopped {
                Button("Stop agent", role: .destructive) { Task { await agents.stop(agent: agent) } }
            }
        } message: { agent in
            Text([agent.harness, agent.status.rawValue, agent.task].compactMap { $0 }.joined(separator: " · "))
        }
    }

    private var agentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.sm) {
                ForEach(chatAgents) { agent in
                    Button { selectedAgent = agent } label: { AgentStatusChip(agent: agent) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
        }
        .background(DS.Color.surface1)
    }

    private var working: [AgentInfo] {
        chatAgents.filter { $0.status == .working || $0.status == .starting }
    }

    private var bottomID: String {
        let pendingCount = agents.pending(in: chatID).count
        let workingIDs = working.map(\.id).joined(separator: ",")
        return "\(chatMessages.last?.id ?? 0)-\(pendingCount)-\(workingIDs)-\(chat?.status.rawValue ?? "")"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    if !agents.historyLoaded && chatMessages.isEmpty {
                        ForEach(0..<4, id: \.self) { i in AgentMessageSkeleton(trailing: i == 0) }
                    } else if chatMessages.isEmpty && agents.pending(in: chatID).isEmpty {
                        Text(isGroup
                             ? "Say what you want. The picker chooses which member answers, one at a time, until it hands the chat back to you."
                             : "Tell the orchestrator what you want done. It starts agents on your host and reports back here.")
                            .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, DS.Spacing.xl)
                    }
                    ForEach(chatMessages) { message in
                        AgentMessageRow(message: message).id(message.id)
                    }
                    ForEach(agents.pending(in: chatID)) { entry in
                        PendingMessageRow(text: entry.text)
                    }
                    activity
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(DS.Spacing.md)
            }
            .onChange(of: bottomID) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    @ViewBuilder
    private var activity: some View {
        if chat?.status == .picking {
            ActivityRow(text: "Choosing who speaks next…", since: nil)
        }
        ForEach(working) { agent in
            ActivityRow(text: "\(agent.name) is working", since: Date(timeIntervalSince1970: TimeInterval(agent.updatedAt) / 1000))
        }
    }

    private var composer: some View {
        VStack(spacing: DS.Spacing.xs) {
            if dictator.isListening {
                Text(dictator.partialTranscript.isEmpty ? "Listening…" : dictator.partialTranscript)
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let notice {
                Text(notice).font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .bottom, spacing: DS.Spacing.sm) {
                TextField(isGroup ? "Message the group" : "Message the orchestrator", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(DS.Font.body)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                if voiceEnabled { micButton }
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agents.connection != .connected)
                .accessibilityLabel("Send")
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.surface1)
    }

    private var micButton: some View {
        Button {
            notice = nil
            if dictator.isListening {
                dictator.stop()
                return
            }
            Task {
                guard await dictator.requestAuthorization() else {
                    if case .unavailable(let reason) = dictator.state { notice = reason }
                    return
                }
                dictator.start(localeID: dictationLocaleID) { text in
                    draft = draft.isEmpty ? text : draft + " " + text
                }
                if case .unavailable(let reason) = dictator.state { notice = reason }
            }
        } label: {
            Image(systemName: dictator.isListening ? "stop.circle.fill" : "mic.circle")
                .font(.system(size: 30))
                .foregroundStyle(dictator.isListening ? DS.Color.error : DS.Color.accent)
        }
        .accessibilityLabel(dictator.isListening ? "Stop dictation" : "Dictate")
    }

    private func send() async {
        dictator.cancel()
        let text = draft
        draft = ""
        guard await agents.send(text, to: chatID) else {
            draft = text
            notice = "Not sent. The agents are not connected."
            return
        }
        notice = nil
    }
}

private struct ActivityRow: View {
    let text: String
    let since: Date?

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            DSStatusIndicator(style: .dot(active: true))
            Text(text).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            if let since {
                TimelineView(.periodic(from: since, by: 1)) { context in
                    Text(Self.elapsed(from: since, to: context.date))
                        .font(DS.Font.monoSmall).foregroundStyle(DS.Color.textTertiary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 3600
            ? String(format: "%d:%02d", seconds / 60, seconds % 60)
            : String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

private struct PendingMessageRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
            Spacer(minLength: DS.Spacing.xxl)
            ProgressView().controlSize(.mini)
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textOnAccent)
                .padding(DS.Spacing.sm)
                .background(DS.Color.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sending: \(text)")
    }
}

private struct AgentMessageSkeleton: View {
    let trailing: Bool

    var body: some View {
        HStack {
            if trailing { Spacer(minLength: DS.Spacing.xxl) }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surface3).frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surface3).frame(height: 12)
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surface3).frame(width: 180, height: 12)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: trailing ? 220 : .infinity, alignment: .leading)
            .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .modifier(AgentShimmer())
        .accessibilityHidden(true)
    }
}

private struct AgentStatusChip: View {
    let agent: AgentInfo

    var body: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(agent.name).font(DS.Font.captionMedium).foregroundStyle(DS.Color.textPrimary)
            Text(agent.harness).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface2, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(agent.name), \(agent.status.rawValue)")
    }

    private var color: Color {
        switch agent.status {
        case .working, .starting: return DS.Color.accent
        case .idle: return DS.Color.success
        case .failed: return DS.Color.error
        case .stopped: return DS.Color.textTertiary
        }
    }
}

private struct AgentMessageRow: View {
    let message: AgentChatMessage

    var body: some View {
        if message.kind == .user {
            HStack {
                Spacer(minLength: DS.Spacing.xxl)
                Text(message.text)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.textOnAccent)
                    .padding(DS.Spacing.sm)
                    .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md))
                    .textSelection(.enabled)
            }
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Image(systemName: icon).foregroundStyle(tint)
                    Text(message.author).font(DS.Font.captionMedium).foregroundStyle(DS.Color.textSecondary)
                }
                if let attachment = message.attachment {
                    AgentAttachmentView(message: message, attachment: attachment)
                } else {
                    Text(LocalizedStringKey(message.text))
                        .font(message.kind == .progress ? DS.Font.caption : DS.Font.body)
                        .foregroundStyle(message.kind == .progress ? DS.Color.textSecondary : DS.Color.textPrimary)
                        .textSelection(.enabled)
                }
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    private var icon: String {
        switch message.kind {
        case .reply, .user: return "bubble.left"
        case .progress: return "ellipsis.circle"
        case .done: return "checkmark.circle"
        case .needsInput: return "questionmark.circle"
        case .error: return "exclamationmark.triangle"
        case .file: return "paperclip"
        }
    }

    private var tint: Color {
        switch message.kind {
        case .done: return DS.Color.success
        case .needsInput: return DS.Color.warning
        case .error: return DS.Color.error
        default: return DS.Color.textTertiary
        }
    }

    private var background: Color {
        message.kind == .progress ? DS.Color.surface0 : DS.Color.surface2
    }
}
private struct AgentAttachmentView: View {
    let message: AgentChatMessage
    let attachment: AgentAttachment
    @ObservedObject private var agents = AgentModeController.shared
    @State private var url: URL?
    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var failure: String?
    @State private var preview: URL?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            content
            if !message.text.isEmpty {
                Text(message.text).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary).textSelection(.enabled)
            }
        }
        .task(id: attempt) { await load() }
        .quickLookPreview($preview)
    }

    @ViewBuilder
    private var content: some View {
        if let failure {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(DS.Color.warning)
                Text("\(attachment.name): \(failure)").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button("Retry") { attempt += 1 }.font(DS.Font.captionMedium)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .onTapGesture { preview = url }
                .accessibilityLabel("Picture \(attachment.name). Double tap to open.")
        } else if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        } else if let url {
            Button { preview = url } label: { fileRow(icon: "doc") }
                .buttonStyle(.plain)
        } else {
            fileRow(icon: "arrow.down.circle", loading: true)
        }
    }

    private func fileRow(icon: String, loading: Bool = false) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            if loading { ProgressView() } else { Image(systemName: icon).foregroundStyle(DS.Color.accent) }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(attachment.name).font(DS.Font.body).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: attachment.size, countStyle: .file))
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
            Spacer()
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func load() async {
        failure = nil
        do {
            let loaded = try await agents.attachmentURL(for: message)
            url = loaded
            if attachment.isImage {
                image = UIImage(contentsOfFile: loaded.path)
            } else if attachment.isVideo {
                player = AVPlayer(url: loaded)
            }
        } catch {
            failure = AgentModeController.message(for: error)
        }
    }
}
#endif

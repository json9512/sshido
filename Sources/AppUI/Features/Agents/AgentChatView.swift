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
    @State private var notice: String?
    @State private var selectedAgent: AgentInfo?
    @State private var signIn: SignInDesktop?

    private var chat: AgentChat? { agents.chat(chatID) }
    private var chatAgents: [AgentInfo] { agents.agents(in: chatID) }
    private var chatMessages: [AgentChatMessage] { agents.messages(in: chatID) }

    var body: some View {
        VStack(spacing: 0) {
            if !chatAgents.isEmpty { agentStrip }
            AgentConnectionBanner()
            if agents.historyLoaded && chat == nil {
                ContentUnavailableView("Chat removed", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            } else {
                messageList
                AgentChatComposer(chatID: chatID, notice: $notice)
            }
        }
        .background(DS.Color.surface0)
        .navigationTitle(chat?.title ?? "Agents")
        .toolbarTitleDisplayMode(.inline)
        .keyboardDismissButton()
        .onAppear { agents.hold() }
        .onDisappear { agents.release() }
        .signInDesktop($signIn) { id in Task { await openSignIn(agentID: id) } }
        .sheet(item: $selectedAgent) { agent in
            NavigationStack {
                AgentRecordView(agentID: agent.id)
            }
            .environmentObject(router)
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
        return "\(chatMessages.last?.id ?? 0)-\(pendingCount)-\(workingIDs)"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if !agents.historyLoaded && chatMessages.isEmpty {
                        ForEach(0..<4, id: \.self) { i in AgentMessageSkeleton(trailing: i == 0) }
                    } else if chatMessages.isEmpty && agents.pending(in: chatID).isEmpty {
                        AnimatedGlyph(animation: .empty, size: CGSize(width: 110, height: 110))
                            .frame(maxWidth: .infinity)
                            .padding(.top, DS.Spacing.xxl)
                    }
                    ForEach(ChatItem.build(chatMessages, agents: chatAgents)) { item in
                        ChatItemView(item: item, retry: retryAction(for: item), signIn: signInAction(for: item),
                                     signInStatus: signInStatus(for: item), openSignIn: openSignIn).id(item.id)
                    }
                    ForEach(agents.pending(in: chatID)) { entry in
                        UserMessageBubble(text: entry.text, sending: true)
                    }
                    activity
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(DS.Spacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: bottomID) { _, _ in
                withAnimation(agents.historyLoaded ? .easeOut(duration: 0.2) : nil) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var activity: some View {
        ForEach(working) { agent in
            ActivityRow(text: "\(agent.name) is working", since: Date(timeIntervalSince1970: TimeInterval(agent.updatedAt) / 1000))
        }
    }

    static let continuePrompt = "Continue where you left off."

    private func retryAction(for item: ChatItem) -> (() -> Void)? {
        guard case .event(let message, _, .error) = item,
              message.id == chatMessages.last?.id,
              agents.pending(in: chatID).isEmpty,
              !chatAgents.contains(where: { $0.status == .working || $0.status == .starting }),
              agents.connection == .connected else { return nil }
        return { Task { _ = await agents.send(Self.continuePrompt, to: chatID) } }
    }

    private func signInAction(for item: ChatItem) -> (() -> Void)? {
        guard case .event(let message, _, .error) = item,
              let harness = AgentHarness.signInNeeded(by: chatAgents.first { $0.id == message.agentId }, error: message.text)
        else { return nil }
        return { Task { await agents.signIn(harness, router: router) } }
    }

    private func signInStatus(for item: ChatItem) -> AgentSignInCard.Status {
        guard case .signIn(let message, _) = item else { return .ready }
        if chatMessages.contains(where: { $0.id > message.id && $0.kind == .user }) { return .done }
        switch signIn {
        case .opening(let id) where id == message.agentId: return .opening
        case .failed(let id, let reason) where id == message.agentId: return .failed(reason)
        default: return .ready
        }
    }

    private func openSignIn(agentID: String?) async {
        guard let agentID else {
            notice = "This sign-in request has no agent attached."
            return
        }
        guard let agent = chatAgents.first(where: { $0.id == agentID }) else {
            signIn = .failed(agentID: agentID, reason: "This agent is gone.")
            return
        }
        signIn = .opening(agentID: agentID)
        do {
            signIn = .open(agentID: agentID, url: try await agents.openDesktop(of: agent))
        } catch {
            signIn = .failed(agentID: agentID, reason: AgentModeController.message(for: error))
        }
    }
}

private struct AgentChatComposer: View {
    let chatID: String
    @Binding var notice: String?

    @ObservedObject private var agents = AgentModeController.shared
    @State private var draft = ""
    @State private var dictator = SpeechDictator()
    @State private var voiceEnabled = false
    @State private var dictationLocaleID = ""

    var body: some View {
        composer
            .task {
                let appearance = await AppearanceStore.shared.appearance
                voiceEnabled = appearance.voiceDictationEnabled
                dictationLocaleID = appearance.dictationLocaleID
            }
            .onDisappear { dictator.cancel() }
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
                TextField("Message", text: $draft, axis: .vertical)
                    .lineLimit(1...6)
                    .font(DS.Font.body)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.vertical, 11)
                    .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(DS.Color.line, lineWidth: 1))
                if voiceEnabled { micButton }
                IconButton(systemName: "arrow.up", label: "Send", kind: .primary) { Task { await send() } }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || agents.connection != .connected)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.surface0)
        .overlay(alignment: .top) { Rectangle().fill(DS.Color.line).frame(height: 1) }
    }

    private var micButton: some View {
        IconButton(systemName: dictator.isListening ? "stop.fill" : "mic", label: dictator.isListening ? "Stop dictation" : "Dictate",
                   kind: dictator.isListening ? .destructive : .plain) {
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
        }
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
            AnimatedGlyph(animation: .working, size: CGSize(width: 32, height: 18))
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

private struct AgentMessageSkeleton: View {
    let trailing: Bool

    var body: some View {
        HStack {
            if trailing { Spacer(minLength: DS.Spacing.xxl) }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                RoundedRectangle(cornerRadius: DS.Radius.small).fill(DS.Color.line).frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: DS.Radius.small).fill(DS.Color.line).frame(height: 12)
                RoundedRectangle(cornerRadius: DS.Radius.small).fill(DS.Color.line).frame(width: 180, height: 12)
            }
            .padding(DS.Spacing.sm)
            .frame(maxWidth: trailing ? 220 : .infinity, alignment: .leading)
            .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.control))
        }
        .modifier(AgentShimmer())
        .accessibilityHidden(true)
    }
}

private struct AgentStatusChip: View {
    let agent: AgentInfo

    var body: some View {
        Chip(text: agent.name, detail: agent.harness, dot: color,
             trailingIcon: agent.verdict.map { ($0 == .pass ? "checkmark.seal.fill" : "xmark.seal.fill", $0 == .pass ? DS.Color.success : DS.Color.error) })
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(agent.name), \(agent.status.rawValue)\(agent.verdict.map { ", verdict \($0.rawValue)" } ?? "")")
            .accessibilityHint("Shows its goal, verification, verdict and track record")
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

private struct ChatItemView: View {
    let item: ChatItem
    let retry: (() -> Void)?
    let signIn: (() -> Void)?
    let signInStatus: AgentSignInCard.Status
    let openSignIn: (String?) async -> Void

    var body: some View {
        switch item {
        case .user(let message):
            UserMessageBubble(text: message.text)
                .padding(.top, DS.Spacing.xs)
        case .agent(let message, let identity, let header, let collapsible):
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                if header {
                    AgentMessageHeader(identity: identity, date: Date(timeIntervalSince1970: TimeInterval(message.createdAt) / 1000))
                }
                Group {
                    if let attachment = message.attachment {
                        AgentAttachmentView(message: message, attachment: attachment)
                    } else {
                        AgentMessageBody(text: message.text, collapsible: collapsible)
                    }
                }
                .padding(.leading, 36)
            }
            .padding(.top, header ? DS.Spacing.sm : 0)
        case .event(let message, let identity, let style):
            AgentEventRow(identity: identity, text: message.text, style: style, onRetry: style == .error ? retry : nil, onSignIn: signIn)
        case .question(let message, let identity):
            AgentQuestionCard(identity: identity, text: message.text)
        case .signIn(let message, let identity):
            AgentSignInCard(identity: identity, text: message.text, status: signInStatus) {
                Task { await openSignIn(message.agentId) }
            }
        }
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
                IconButton(systemName: "arrow.clockwise", label: "Retry", kind: .quiet, size: 36) { attempt += 1 }
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 280, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
                .onTapGesture { preview = url }
                .accessibilityLabel("Picture \(attachment.name). Double tap to open.")
        } else if let player {
            VideoPlayer(player: player)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.control))
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
        .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.control))
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

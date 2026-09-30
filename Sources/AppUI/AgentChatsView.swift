#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif
#if canImport(sshidoCore)
import sshidoCore
#endif

struct AgentChatsView: View {
    @ObservedObject private var agents = AgentModeController.shared
    @State private var creatingChat = false
    @State private var pendingDelete: AgentChat?
    @State private var openedChat: String?

    var body: some View {
        List {
            AgentConnectionBanner()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            if !agents.historyLoaded && agents.chats.isEmpty {
                ForEach(0..<3, id: \.self) { _ in AgentChatRowSkeleton().dsRow() }
            } else if agents.chats.isEmpty {
                Text("No chats yet. Start one with the + button.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
            ForEach(agents.chats.reversed()) { chat in
                NavigationLink(value: AppRouter.Destination.agentConversation(chat.id)) {
                    AgentChatRow(chat: chat, last: agents.messages(in: chat.id).last,
                                 busy: busy(chat))
                }
                .dsRow()
                .swipeActions {
                    Button("Delete", role: .destructive) { pendingDelete = chat }
                }
            }
        }
        .dsFormStyle()
        .navigationTitle("Agent chats")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creatingChat = true } label: {
                    Image(systemName: "plus")
                }
                .disabled(agents.connection != .connected)
                .accessibilityLabel("New chat")
            }
        }
        .navigationDestination(item: $openedChat) { id in AgentChatView(chatID: id) }
        .sheet(isPresented: $creatingChat) {
            NavigationStack {
                NewAgentChatView { id in
                    creatingChat = false
                    openedChat = id
                }
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.title ?? "this chat")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { chat in
            Button("Delete chat", role: .destructive) { Task { await agents.deleteChat(chat.id) } }
        } message: { _ in
            Text("Removes its agents, their containers and the chat history on the host. Files in the shared workspace stay.")
        }
        .onAppear { agents.hold() }
        .onDisappear { agents.release() }
    }

    private func busy(_ chat: AgentChat) -> Bool {
        agents.agents(in: chat.id).contains { $0.status == .working || $0.status == .starting }
    }
}

private struct AgentChatRow: View {
    let chat: AgentChat
    let last: AgentChatMessage?
    let busy: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 18))
                .foregroundStyle(DS.Color.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                HStack(spacing: DS.Spacing.xs) {
                    Text(chat.title).font(DS.Font.rowTitle).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                    if busy { DSStatusIndicator(style: .dot(active: true)) }
                }
                Text(preview).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary).lineLimit(2)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chat.title)\(busy ? ", working" : ""). \(preview)")
    }

    private var preview: String {
        guard let last else { return "No messages yet" }
        let text = last.kind == .file ? "sent a file" : last.text
        return "\(last.author): \(text)"
    }
}

private struct AgentChatRowSkeleton: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Circle().fill(DS.Color.surface3).frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surface3).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: DS.Radius.sm).fill(DS.Color.surface2).frame(height: 10)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .modifier(AgentShimmer())
        .accessibilityHidden(true)
    }
}

struct AgentShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity(0.6)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                content.opacity(0.45 + 0.35 * (0.5 + 0.5 * cos(phase * 2 * .pi)))
            }
        }
    }
}

struct AgentConnectionBanner: View {
    @ObservedObject private var agents = AgentModeController.shared

    var body: some View {
        switch agents.connection {
        case .connected:
            if let notice = agents.notice {
                banner(icon: "exclamationmark.triangle", text: notice, action: "Dismiss") { agents.notice = nil }
            }
        case .connecting, .disconnected:
            HStack(spacing: DS.Spacing.sm) {
                ProgressView()
                Text(agents.historyLoaded ? "Reconnecting to your agents…" : "Connecting to your agents…")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.sm)
        case .failed(let reason):
            banner(icon: "exclamationmark.triangle", text: reason, action: "Retry") { agents.startChat() }
        }
    }

    private func banner(icon: String, text: String, action: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: icon).foregroundStyle(DS.Color.warning)
            Text(text).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            Spacer()
            Button(action, action: perform).font(DS.Font.captionMedium)
        }
        .padding(DS.Spacing.sm)
        .background(DS.Color.surface2)
    }
}
#endif

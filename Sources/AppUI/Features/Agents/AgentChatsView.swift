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
    @State private var creating = false
    @State private var pendingDelete: AgentChat?
    @State private var openedChat: String?

    var body: some View {
        Group {
            if agents.historyLoaded && agents.chats.isEmpty {
                VStack(spacing: 0) {
                    AgentConnectionBanner()
                    EmptyStateView(title: "No chats", action: agents.connection == .connected
                                   ? (icon: "plus", label: "New chat", run: { creating = true }) : nil)
                }
            } else {
                list
            }
        }
        .tideScreen()
        .navigationTitle("Agents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ToolbarIcon(systemName: "plus", label: "New chat", tint: DS.Color.accent) { creating = true }
                    .disabled(agents.connection != .connected)
            }
        }
        .navigationDestination(item: $openedChat) { AgentChatView(chatID: $0) }
        .sheet(isPresented: $creating) {
            NavigationStack {
                NewAgentChatView { id in
                    creating = false
                    openedChat = id
                }
            }
        }
        .confirmationDialog("Delete \(pendingDelete?.title ?? "this chat")?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible, presenting: pendingDelete) { chat in
            Button("Delete chat", role: .destructive) { Task { await agents.deleteChat(chat.id) } }
        } message: { _ in
            Text("Removes its agents, containers and history. Workspace files stay.")
        }
        .onAppear { agents.hold() }
        .onDisappear { agents.release() }
    }

    private var list: some View {
        List {
            AgentConnectionBanner()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            if !agents.historyLoaded {
                ForEach(0..<3, id: \.self) { _ in AgentChatRowSkeleton().tideRow() }
            }
            ForEach(agents.chats.reversed()) { chat in
                NavigationLink(value: AppRouter.Destination.agentConversation(chat.id)) {
                    AgentChatRow(chat: chat, last: agents.messages(in: chat.id).last, busy: busy(chat))
                }
                .tideRow()
                .swipeActions {
                    Button { pendingDelete = chat } label: { Label("Delete", systemImage: "trash") }
                        .tint(DS.Color.error)
                }
            }
        }
        .tideList()
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
        TideRow(icon: "bubble.left.and.bubble.right", title: chat.title, subtitle: preview) {
            if busy { AnimatedGlyph(animation: .working, size: CGSize(width: 36, height: 20)) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(chat.title)\(busy ? ", working" : ""). \(preview)")
    }

    private var preview: String {
        guard let last else { return "No messages yet" }
        return "\(last.author): \(last.kind == .file ? "sent a file" : last.text)"
    }
}

private struct AgentChatRowSkeleton: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Circle().fill(DS.Color.surface2).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                RoundedRectangle(cornerRadius: DS.Radius.small).fill(DS.Color.surface2).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: DS.Radius.small).fill(DS.Color.surface2).frame(height: 10)
            }
        }
        .frame(minHeight: DS.hitTarget)
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
                banner(icon: "exclamationmark.triangle.fill", text: notice, actionIcon: "xmark", actionLabel: "Dismiss") { agents.notice = nil }
            }
        case .connecting, .disconnected:
            HStack(spacing: DS.Spacing.sm) {
                AnimatedGlyph(animation: .connecting, size: CGSize(width: 22, height: 22))
                Text(agents.historyLoaded ? "Reconnecting" : "Connecting").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(DS.Spacing.sm)
        case .failed(let reason):
            banner(icon: "exclamationmark.triangle.fill", text: reason, actionIcon: "arrow.clockwise", actionLabel: "Retry") { agents.startChat() }
        }
    }

    private func banner(icon: String, text: String, actionIcon: String, actionLabel: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.sm) {
            Image(systemName: icon).foregroundStyle(DS.Color.warning)
            Text(text).font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            Spacer()
            IconButton(systemName: actionIcon, label: actionLabel, kind: .quiet, size: 36, action: perform)
        }
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.xs)
        .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: DS.Radius.control))
        .padding(.horizontal, DS.Spacing.lg)
    }
}
#endif

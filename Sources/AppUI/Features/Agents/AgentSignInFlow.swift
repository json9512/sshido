#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif

enum SignInDesktop: Equatable {
    case opening(agentID: String)
    case open(agentID: String, url: URL)
    case confirming(agentID: String)
    case failed(agentID: String, reason: String)

    var agentID: String {
        switch self {
        case .opening(let id), .open(let id, _), .confirming(let id), .failed(let id, _): return id
        }
    }

    var url: URL? {
        guard case .open(_, let url) = self else { return nil }
        return url
    }
}

struct AgentSignInCard: View {
    enum Status: Equatable {
        case ready
        case opening
        case failed(String)
        case done
    }

    let identity: AgentIdentity
    let text: String
    let status: Status
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: "person.badge.key.fill").font(.system(size: 18)).foregroundStyle(DS.Color.accent)
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                Text("\(identity.name) needs you to sign in").font(DS.Font.sans(12, .semibold)).foregroundStyle(DS.Color.accent)
                Text(ChatMarkdown.attributed(text)).font(DS.Font.sans(15)).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
                action
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Color.accent.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var action: some View {
        switch status {
        case .done:
            Label("Signed in", systemImage: "checkmark.circle.fill").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        case .opening:
            HStack(spacing: DS.Spacing.sm) {
                ProgressView().tint(DS.Color.accent)
                Text("Opening the desktop…").font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
        case .ready, .failed:
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Button(action: open) {
                    Label("Sign in on the desktop", systemImage: "display")
                        .font(DS.Font.sans(14, .semibold))
                        .padding(.horizontal, DS.Spacing.md)
                        .padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.accent, in: Capsule())
                        .foregroundStyle(DS.Color.textOnAccent)
                }
                .buttonStyle(.plain)
                if case .failed(let reason) = status {
                    Text(reason).font(DS.Font.caption).foregroundStyle(DS.Color.warning)
                }
                Text("Tap Done when you have signed in. The agent continues by itself.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            }
        }
    }
}

private struct SignInDesktopModifier: ViewModifier {
    @Binding var state: SignInDesktop?
    let reopen: (String) -> Void
    @ObservedObject private var agents = AgentModeController.shared

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(get: { state?.url != nil }, set: { shown in if !shown { finish() } })) {
                if let url = state?.url {
                    SafariSheet(url: url) { finish() }.ignoresSafeArea()
                }
            }
            .confirmationDialog("Did you finish signing in?", isPresented: Binding(
                get: { if case .confirming = state { return true } else { return false } },
                set: { shown in if !shown, case .confirming = state { state = nil } }
            ), titleVisibility: .visible) {
                if let id = state?.agentID {
                    Button("Yes, continue") {
                        state = nil
                        Task { await agents.signedIn(agentID: id) }
                    }
                    Button("Not yet, open the desktop") { reopen(id) }
                }
                Button("Cancel", role: .cancel) { state = nil }
            } message: {
                Text("The agent keeps the sign-in for every agent and carries on.")
            }
    }

    private func finish() {
        guard case .open(let id, _) = state else { return }
        state = .confirming(agentID: id)
        Task { await agents.closeDesktop() }
    }
}

extension View {
    func signInDesktop(_ state: Binding<SignInDesktop?>, reopen: @escaping (String) -> Void) -> some View {
        modifier(SignInDesktopModifier(state: state, reopen: reopen))
    }
}
#endif

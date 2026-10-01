#if canImport(UIKit)
import SwiftUI
#if canImport(sshidoModels)
import sshidoModels
#endif

struct AgentIdentity: Equatable {
    let name: String
    let isOrchestrator: Bool
    let role: String?

    static let palette: [Color] = [
        Color(hex: 0x9B8AFB), Color(hex: 0xF5A524), Color(hex: 0x4CC38A),
        Color(hex: 0xF08A7E), Color(hex: 0x6CA8FF), Color(hex: 0xE879C6),
    ]

    var color: Color {
        guard !isOrchestrator else { return DS.Color.accent }
        let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &* 33) &+ $1.value }
        return Self.palette[Int(hash % UInt32(Self.palette.count))]
    }

    var initials: String {
        let parts = name.split(whereSeparator: { $0 == "-" || $0 == "_" || $0 == " " })
        let letters = parts.prefix(2).compactMap(\.first)
        return String(letters.isEmpty ? Array(name.prefix(2)) : letters).uppercased()
    }
}

struct AgentAvatar: View {
    let identity: AgentIdentity
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle().fill(identity.color.opacity(0.18))
            Circle().stroke(identity.color.opacity(0.55), lineWidth: 1)
            if identity.isOrchestrator {
                Image(systemName: "sparkles").font(.system(size: size * 0.46, weight: .semibold)).foregroundStyle(identity.color)
            } else {
                Text(identity.initials).font(DS.Font.sans(size * 0.4, .bold)).foregroundStyle(identity.color)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct AgentMessageHeader: View {
    let identity: AgentIdentity
    let date: Date

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            AgentAvatar(identity: identity)
            Text(identity.name).font(DS.Font.sans(14, .semibold)).foregroundStyle(identity.color)
            if let role = identity.role {
                Text(role)
                    .font(DS.Font.sans(11, .medium))
                    .foregroundStyle(DS.Color.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.Color.surface2, in: Capsule())
            }
            Spacer(minLength: 0)
            Text(date.formatted(date: .omitted, time: .shortened)).font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }
}

enum ChatMarkdown {
    static func attributed(_ source: String) -> AttributedString {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .filter { !isTableSeparator($0) }
        return lines.enumerated().reduce(AttributedString()) { acc, pair in
            acc + (pair.offset == 0 ? AttributedString() : AttributedString("\n")) + line(pair.element)
        }
    }

    static func isTableSeparator(_ raw: String) -> Bool {
        raw.range(of: #"^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$"#, options: .regularExpression) != nil
    }

    private static func line(_ raw: String) -> AttributedString {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 1 {
            let cells = trimmed.dropFirst().dropLast().split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return cells.enumerated().reduce(AttributedString()) { acc, pair in
                acc + (pair.offset == 0 ? AttributedString() : AttributedString("  ·  ")) + inline(pair.element)
            }
        }
        if let heading = trimmed.firstMatch(of: /^#{1,6}\s+(.*)$/) {
            return inline(String(heading.1)).mergingAttributes(AttributeContainer().font(DS.Font.sans(16, .semibold)))
        }
        if trimmed.range(of: #"^([-*_]\s*){3,}$"#, options: .regularExpression) != nil {
            return AttributedString("")
        }
        if let bullet = raw.firstMatch(of: /^(\s*)[-*+]\s+(.*)$/) {
            let indent = String(repeating: "  ", count: bullet.1.count / 2)
            return AttributedString(indent + "•  ") + inline(String(bullet.2))
        }
        return inline(raw)
    }

    private static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

struct AgentMessageBody: View {
    let text: String
    var collapsible = false
    @State private var expanded = false

    private var isLong: Bool { text.count > 420 || text.filter { $0 == "\n" }.count > 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(ChatMarkdown.attributed(text))
                .font(DS.Font.sans(15))
                .lineSpacing(3)
                .foregroundStyle(DS.Color.textPrimary)
                .tint(DS.Color.accent)
                .textSelection(.enabled)
                .lineLimit(collapsible && isLong && !expanded ? 6 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .mask {
                    if collapsible && isLong && !expanded {
                        LinearGradient(colors: [.black, .black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle()
                    }
                }
            if collapsible && isLong {
                Button {
                    withAnimation(DS.Motion.spring) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.textSecondary)
                        .frame(width: 44, height: 24)
                        .background(DS.Color.surface2, in: Capsule())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(expanded ? "Show less" : "Show all")
            }
        }
    }
}

struct AgentEventRow: View {
    enum Style { case progress, started, pass, fail, error }

    let identity: AgentIdentity?
    let text: String
    let style: Style
    var onRetry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            ZStack {
                Circle().fill(DS.Color.surface0).frame(width: 22, height: 22)
                Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            }
            .frame(width: 28)
            Group {
                if let identity {
                    Text(identity.name).foregroundStyle(identity.color).fontWeight(.semibold) + Text("  ") + Text(text)
                } else {
                    Text(text)
                }
            }
            .font(DS.Font.sans(13))
            .foregroundStyle(DS.Color.textSecondary)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 3)
            .accessibilityElement(children: .combine)
            if let onRetry {
                IconButton(systemName: "arrow.clockwise", label: "Retry", kind: .plain, size: 32, action: onRetry)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var icon: String {
        switch style {
        case .progress: return "circle.dotted"
        case .started: return "arrow.triangle.branch"
        case .pass: return "checkmark"
        case .fail: return "xmark"
        case .error: return "exclamationmark"
        }
    }

    private var tint: Color {
        switch style {
        case .progress: return DS.Color.textTertiary
        case .started: return DS.Color.accent
        case .pass: return DS.Color.success
        case .fail, .error: return DS.Color.error
        }
    }
}

struct AgentQuestionCard: View {
    let identity: AgentIdentity
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(systemName: "questionmark.bubble.fill").font(.system(size: 18)).foregroundStyle(DS.Color.warning)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("\(identity.name) asks").font(DS.Font.sans(12, .semibold)).foregroundStyle(DS.Color.warning)
                Text(ChatMarkdown.attributed(text)).font(DS.Font.sans(15)).foregroundStyle(DS.Color.textPrimary).textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: DS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).stroke(DS.Color.warning.opacity(0.35), lineWidth: 1))
    }
}

struct UserMessageBubble: View {
    let text: String
    var sending = false

    var body: some View {
        HStack(alignment: .bottom, spacing: DS.Spacing.xs) {
            Spacer(minLength: 56)
            if sending {
                Image(systemName: "clock").font(.system(size: 11)).foregroundStyle(DS.Color.textTertiary)
            }
            Text(text)
                .font(DS.Font.sans(15))
                .foregroundStyle(DS.Color.textOnAccent)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(DS.Color.accent.opacity(sending ? 0.55 : 1),
                            in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(sending ? "Sending: \(text)" : "You: \(text)")
    }
}
enum ChatItem: Identifiable {
    case user(AgentChatMessage)
    case agent(AgentChatMessage, identity: AgentIdentity, header: Bool, collapsible: Bool)
    case event(AgentChatMessage, identity: AgentIdentity?, style: AgentEventRow.Style)
    case question(AgentChatMessage, identity: AgentIdentity)

    var id: Int64 {
        switch self {
        case .user(let m), .agent(let m, _, _, _), .event(let m, _, _), .question(let m, _): return m.id
        }
    }

    static let groupWindow: Int64 = 5 * 60 * 1000

    static func build(_ messages: [AgentChatMessage], agents: [AgentInfo]) -> [ChatItem] {
        let byID = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        return messages.enumerated().map { index, message in
            let previous = index > 0 ? messages[index - 1] : nil
            return item(message, previous: previous, identity: identity(for: message, byID: byID))
        }
    }

    private static func identity(for message: AgentChatMessage, byID: [String: AgentInfo]) -> AgentIdentity {
        guard let id = message.agentId, let info = byID[id], info.name == message.author else {
            return AgentIdentity(name: message.author, isOrchestrator: message.author == "orchestrator", role: nil)
        }
        return AgentIdentity(name: info.name, isOrchestrator: info.isOrchestrator,
                             role: info.isOrchestrator ? info.harness : "subagent · \(info.harness)")
    }

    private static func continues(_ message: AgentChatMessage, after previous: AgentChatMessage?) -> Bool {
        guard let previous, previous.author == message.author, message.createdAt - previous.createdAt < groupWindow else { return false }
        return [.reply, .done, .file].contains(previous.kind)
    }

    private static func item(_ message: AgentChatMessage, previous: AgentChatMessage?, identity: AgentIdentity) -> ChatItem {
        switch message.kind {
        case .user:
            return .user(message)
        case .needsInput:
            return .question(message, identity: identity)
        case .error:
            return .event(message, identity: message.author == "sshido" ? nil : identity, style: .error)
        case .progress:
            return .event(message, identity: identity, style: eventStyle(message.text))
        case .reply, .file, .done:
            return .agent(message, identity: identity, header: !continues(message, after: previous), collapsible: message.kind == .done)
        }
    }

    static func eventStyle(_ text: String) -> AgentEventRow.Style {
        if text.hasPrefix("Started ") { return .started }
        guard text.hasPrefix("Verdict for ") else { return .progress }
        return text.contains(": pass") ? .pass : .fail
    }
}
#endif

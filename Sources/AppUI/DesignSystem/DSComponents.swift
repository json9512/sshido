#if canImport(UIKit)
import Lottie
import SwiftUI
import UIKit

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(DS.Motion.quick, value: configuration.isPressed)
    }
}

struct IconButton: View {
    enum Kind { case plain, primary, destructive, quiet }

    let systemName: String
    let label: String
    var kind: Kind = .plain
    var size: CGFloat = DS.hitTarget
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    private var foreground: Color {
        switch kind {
        case .plain, .quiet: return DS.Color.textPrimary
        case .primary: return DS.Color.textOnAccent
        case .destructive: return DS.Color.error
        }
    }

    private var background: Color {
        switch kind {
        case .plain, .destructive: return DS.Color.surface2
        case .primary: return DS.Color.accent
        case .quiet: return .clear
        }
    }
}

struct ToolbarIcon: View {
    let systemName: String
    let label: String
    var tint: Color = DS.Color.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).foregroundStyle(tint)
        }
        .accessibilityLabel(label)
    }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.textTertiary)
            .textCase(nil)
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay {
                if pulsing && !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8
                        let eased = 1 - pow(1 - t, 2)
                        Circle().stroke(color, lineWidth: 1.5).scaleEffect(1 + 0.9 * eased).opacity(0.7 * (1 - eased))
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}

struct TideRow<Trailing: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color = DS.Color.accent
    var monoSubtitle = false
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(DS.Font.rowTitle).foregroundStyle(DS.Color.textPrimary).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(monoSubtitle ? DS.Font.monoSmall : DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(monoSubtitle ? .middle : .tail)
                }
            }
            Spacer(minLength: DS.Spacing.sm)
            trailing()
        }
        .frame(minHeight: DS.hitTarget)
        .contentShape(Rectangle())
    }
}

extension TideRow where Trailing == EmptyView {
    init(icon: String, title: String, subtitle: String? = nil, tint: Color = DS.Color.accent, monoSubtitle: Bool = false) {
        self.init(icon: icon, title: title, subtitle: subtitle, tint: tint, monoSubtitle: monoSubtitle) { EmptyView() }
    }
}

struct Chip: View {
    let text: String
    var detail: String?
    var dot: Color?
    var trailingIcon: (name: String, color: Color)?

    var body: some View {
        HStack(spacing: 6) {
            if let dot { StatusDot(color: dot) }
            Text(text).font(DS.Font.sans(13, .medium)).foregroundStyle(DS.Color.textPrimary)
            if let detail { Text(detail).font(DS.Font.sans(13)).foregroundStyle(DS.Color.textTertiary) }
            if let trailingIcon {
                Image(systemName: trailingIcon.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(trailingIcon.color)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(DS.Color.surface2, in: Capsule())
        .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))
    }
}

enum TideAnimation: String {
    case connecting, working, pass, fail, empty
}

struct AnimatedGlyph: View {
    let animation: TideAnimation
    var loop = true
    var size: CGSize = CGSize(width: 64, height: 64)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LottieView(animation: .named(animation.rawValue))
            .playbackMode(reduceMotion
                          ? .paused(at: .progress(loop ? 0.5 : 1))
                          : .playing(.fromProgress(0, toProgress: 1, loopMode: loop ? .loop : .playOnce)))
            .resizable()
            .frame(width: size.width, height: size.height)
            .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let title: String
    var message: String?
    var action: (icon: String, label: String, run: () -> Void)?

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            AnimatedGlyph(animation: .empty, size: CGSize(width: 120, height: 120))
            Text(title).font(DS.Font.title).foregroundStyle(DS.Color.textPrimary)
            if let message {
                Text(message).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal, DS.Spacing.xl)
            }
            if let action {
                IconButton(systemName: action.icon, label: action.label, kind: .primary, size: 56, action: action.run)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingStateView: View {
    var title: String?

    var body: some View {
        VStack(spacing: DS.Spacing.md) {
            AnimatedGlyph(animation: .connecting, size: CGSize(width: 72, height: 72))
            if let title { Text(title).font(DS.Font.callout).foregroundStyle(DS.Color.textSecondary) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct InlineErrorText: View {
    let message: String
    init(_ message: String) { self.message = message }

    var body: some View {
        Label {
            Text(message).font(DS.Font.callout).foregroundStyle(DS.Color.error)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DS.Color.error)
        }
    }
}

struct CopyableCode: View {
    let text: String
    var onCopied: () -> Void = {}

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Text(text)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "doc.on.doc", label: "Copy", kind: .quiet, size: 36) {
                UIPasteboard.general.string = text
                onCopied()
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Color.void, in: RoundedRectangle(cornerRadius: DS.Radius.control))
    }
}

private struct TideListModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .listSectionSpacing(DS.Spacing.lg)
            .scrollContentBackground(.hidden)
            .background(DS.Color.surface0)
            .foregroundStyle(DS.Color.textPrimary)
            .tint(DS.Color.accent)
            .font(DS.Font.body)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(DS.Font.sans(14, .medium))
                        .foregroundStyle(DS.Color.textPrimary)
                        .padding(.horizontal, DS.Spacing.lg)
                        .padding(.vertical, 10)
                        .background(DS.Color.surface2, in: Capsule())
                        .overlay(Capsule().stroke(DS.Color.line, lineWidth: 1))
                        .padding(.top, DS.Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .animation(DS.Motion.spring, value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                if !Task.isCancelled { message = nil }
            }
    }
}

private struct SheetActionsModifier: ViewModifier {
    let cancel: (() -> Void)?
    let confirm: (() -> Void)?
    let confirmEnabled: Bool
    let working: Bool

    func body(content: Content) -> some View {
        content.toolbar {
            if let cancel {
                ToolbarItem(placement: .cancellationAction) {
                    ToolbarIcon(systemName: "xmark", label: "Close", tint: DS.Color.textSecondary, action: cancel)
                        .disabled(working)
                }
            }
            if let confirm {
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView().tint(DS.Color.accent)
                    } else {
                        ToolbarIcon(systemName: "checkmark", label: "Save", tint: confirmEnabled ? DS.Color.accent : DS.Color.textTertiary, action: confirm)
                            .disabled(!confirmEnabled)
                    }
                }
            }
        }
    }
}

private struct KeyboardDismissModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                ToolbarIcon(systemName: "keyboard.chevron.compact.down", label: "Hide keyboard") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

extension View {
    func tideList() -> some View { modifier(TideListModifier()) }

    func tideRow() -> some View {
        listRowBackground(DS.Color.surface1).listRowSeparatorTint(DS.Color.line)
    }

    func tideScreen() -> some View {
        background(DS.Color.surface0.ignoresSafeArea())
            .foregroundStyle(DS.Color.textPrimary)
            .tint(DS.Color.accent)
    }

    func toast(_ message: Binding<String?>, duration: Duration = .seconds(1.6)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }

    func sheetActions(cancel: (() -> Void)? = nil, confirm: (() -> Void)? = nil, confirmEnabled: Bool = true, working: Bool = false) -> some View {
        modifier(SheetActionsModifier(cancel: cancel, confirm: confirm, confirmEnabled: confirmEnabled, working: working))
    }

    func keyboardDismissButton() -> some View { modifier(KeyboardDismissModifier()) }
}
#endif

#if canImport(UIKit)
import SwiftUI

// MARK: - Button Styles

struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.textOnAccent)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.accent, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(DS.Animation.quick, value: configuration.isPressed)
    }
}

struct DSSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.textPrimary)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.titaniumDark, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct DSGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.accent)
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.xs)
            .opacity(configuration.isPressed ? 0.5 : 1)
    }
}

struct DSChipButtonStyle: ButtonStyle {
    var armed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Font.chip)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(
                armed ? DS.Color.accent.opacity(0.55) : DS.Color.surface2,
                in: RoundedRectangle(cornerRadius: DS.Radius.md)
            )
            .foregroundStyle(armed ? DS.Color.textOnAccent : DS.Color.textPrimary)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// Legacy name preserved for backward compatibility during migration.
struct TintedChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                Color.accentColor.opacity(0.15),
                in: RoundedRectangle(cornerRadius: DS.cornerRadius)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Inline Error

struct InlineErrorText: View {
    let message: String
    init(_ message: String) { self.message = message }
    var body: some View {
        Text(message)
            .font(DS.Font.callout)
            .foregroundStyle(DS.Color.error)
    }
}

// MARK: - Toast

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(DS.Font.callout)
                        .foregroundStyle(DS.Color.textPrimary)
                        .padding(.horizontal, DS.Spacing.md).padding(.vertical, DS.Spacing.sm)
                        .background(DS.Color.surface2, in: Capsule())
                        .overlay(Capsule().stroke(DS.Color.titaniumDark, lineWidth: 0.5))
                        .padding(.top, DS.Spacing.sm)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(DS.Animation.quick, value: message)
            .task(id: message) {
                guard message != nil else { return }
                try? await Task.sleep(for: duration)
                if !Task.isCancelled { message = nil }
            }
    }
}

extension View {
    func toast(_ message: Binding<String?>, duration: Duration = .seconds(1.5)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}

// MARK: - Card

struct DSCard<Content: View>: View {
    let cornerRadius: CGFloat
    @ViewBuilder let content: Content

    init(cornerRadius: CGFloat = DS.Radius.lg, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(DS.Spacing.xl)
            .background(DS.Color.surface1, in: RoundedRectangle(cornerRadius: cornerRadius))
            .dsShadowSubtle()
    }
}

// MARK: - List Row

struct DSListRow<Accessories: View, Trailing: View>: View {
    let icon: String?
    let iconTint: Color
    let title: String
    let subtitle: String?
    @ViewBuilder let accessories: Accessories
    @ViewBuilder let trailing: Trailing

    init(
        icon: String? = nil,
        iconTint: Color = DS.Color.titanium,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessories: () -> Accessories = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.icon = icon
        self.iconTint = iconTint
        self.title = title
        self.subtitle = subtitle
        self.accessories = accessories()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(iconTint)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.textSecondary)
                        .lineLimit(1)
                }
                accessories
            }
            Spacer(minLength: 0)
            trailing
        }
    }
}

// MARK: - Status Indicator

struct DSStatusIndicator: View {
    enum Style {
        case dot(active: Bool)
        case pill(phase: Phase)
    }
    enum Phase { case online, connecting, offline }

    let style: Style
    @State private var pulsing = false

    var body: some View {
        switch style {
        case .dot(let active):
            dotView(active: active, color: active ? DS.Color.success : DS.Color.titaniumDark)
        case .pill(let phase):
            pillView(phase: phase)
        }
    }

    @ViewBuilder
    private func dotView(active: Bool, color: Color) -> some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.5), lineWidth: 6)
                .frame(width: 10, height: 10)
                .scaleEffect(active && pulsing ? 2.2 : 1)
                .opacity(active && pulsing ? 0 : 0.5)
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
        }
        .onAppear { startPulse(active) }
        .onChange(of: active) { _, newVal in
            pulsing = false
            startPulse(newVal)
        }
    }

    @ViewBuilder
    private func pillView(phase: Phase) -> some View {
        HStack(spacing: 6) {
            Circle().fill(phaseColor(phase)).frame(width: 7, height: 7)
                .overlay(
                    Circle().stroke(phaseColor(phase).opacity(0.4), lineWidth: 6)
                        .scaleEffect(phase == .connecting ? 1.6 : 1)
                        .opacity(phase == .connecting ? 0 : 0.4)
                        .animation(
                            phase == .connecting
                            ? .easeOut(duration: 1.0).repeatForever(autoreverses: false)
                            : .default,
                            value: phase
                        )
                )
            Text(phaseLabel(phase))
                .font(DS.Font.captionMedium)
                .foregroundStyle(DS.Color.textSecondary)
        }
    }

    private func startPulse(_ active: Bool) {
        guard active else { return }
        withAnimation(DS.Animation.pulse) { pulsing = true }
    }

    private func phaseColor(_ phase: Phase) -> Color {
        switch phase {
        case .online:     return DS.Color.success
        case .connecting: return DS.Color.warning
        case .offline:    return DS.Color.error
        }
    }

    private func phaseLabel(_ phase: Phase) -> String {
        switch phase {
        case .online:     return "online"
        case .connecting: return "connecting"
        case .offline:    return "offline"
        }
    }
}

// MARK: - Input

struct DSInput: View {
    let title: String
    @Binding var text: String
    var isMonospaced = true
    var isSecure = false

    var body: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
        }
        .font(isMonospaced ? DS.Font.mono : DS.Font.body)
        .padding(DS.Spacing.md)
        .background(DS.Color.surface2, in: RoundedRectangle(cornerRadius: DS.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.titaniumDark, lineWidth: 0.5)
        )
    }
}
#endif

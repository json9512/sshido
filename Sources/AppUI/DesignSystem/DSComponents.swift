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

// MARK: - Form & Row Styling

struct DSFormModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(DS.Color.surface0)
            .foregroundStyle(DS.Color.textPrimary)
            .tint(DS.Color.accent)
    }
}

extension View {
    func dsFormStyle() -> some View { modifier(DSFormModifier()) }

    func dsRow() -> some View {
        self.listRowBackground(DS.Color.surface1)
            .listRowSeparator(.hidden)
    }
}

struct DSSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title.uppercased())
            .font(DS.Font.caption)
            .foregroundStyle(DS.Color.titanium)
            .tracking(1.2)
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
            dotView(active: active, color: active ? DS.Color.accent : DS.Color.titaniumDark)
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
        case .online:     return DS.Color.accent
        case .connecting: return DS.Color.spark
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

#endif

#if canImport(UIKit)
import SwiftUI

public enum CoachStep: Int, CaseIterable, Comparable {
    case addHost = 0
    case save = 1
    case tapHost = 2
    case newSession = 3

    public static func < (a: CoachStep, b: CoachStep) -> Bool { a.rawValue < b.rawValue }

    var tooltip: String {
        switch self {
        case .addHost:    return "Tap + to add your first server."
        case .save:       return "Fill in the fields above, then tap Save."
        case .tapHost:    return "Tap your server to open its sessions."
        case .newSession: return "Tap New session to connect and open a terminal."
        }
    }
}

@MainActor
public final class OnboardingCoach: ObservableObject {
    public static let shared = OnboardingCoach()
    private let completedKey = "sshido.onboardingCompleted"
    @Published public var currentStep: CoachStep?

    public func startIfNeeded(hostCount: Int) {
        guard currentStep == nil,
              !UserDefaults.standard.bool(forKey: completedKey),
              hostCount == 0 else { return }
        currentStep = .addHost
    }

    public func advance(past step: CoachStep) {
        guard currentStep == step else { return }
        if let next = CoachStep(rawValue: step.rawValue + 1) {
            currentStep = next
        } else {
            finish()
        }
    }

    public func finish() {
        UserDefaults.standard.set(true, forKey: completedKey)
        currentStep = nil
    }

    public func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        currentStep = nil
    }
}

private struct CoachAnchorKey: PreferenceKey {
    static var defaultValue: [CoachStep: Anchor<CGRect>] = [:]
    static func reduce(value: inout [CoachStep: Anchor<CGRect>],
                       nextValue: () -> [CoachStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, b in b })
    }
}

extension View {
    @ViewBuilder
    func coachTarget(_ step: CoachStep?) -> some View {
        if let step {
            anchorPreference(key: CoachAnchorKey.self, value: .bounds) { [step: $0] }
        } else {
            self
        }
    }

    func coachmarks() -> some View { modifier(CoachmarksModifier()) }
}

private struct CoachmarksModifier: ViewModifier {
    @ObservedObject private var coach = OnboardingCoach.shared

    func body(content: Content) -> some View {
        content.overlayPreferenceValue(CoachAnchorKey.self) { anchors in
            GeometryReader { geo in
                if let step = coach.currentStep, let anchor = anchors[step] {
                    CoachOverlay(rect: geo[anchor], containerSize: geo.size, step: step)
                        .id(step)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.2), value: coach.currentStep)
        }
    }
}

private struct CoachOverlay: View {
    let rect: CGRect
    let containerSize: CGSize
    let step: CoachStep
    @ObservedObject private var coach = OnboardingCoach.shared
    @State private var pulse: CGFloat = 0
    @State private var keyboardHeight: CGFloat = 0
    @State private var dismissed = false

    private let padding: CGFloat = 10
    private let cornerRadius: CGFloat = 14

    private var cutout: CGRect { rect.insetBy(dx: -padding, dy: -padding) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !dismissed {
                dimmer
                pulseRing
                tooltip
                if step == .save {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                        }
                }
                skipButton
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
            if let frame = (notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
                keyboardHeight = frame.height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
    }

    private var dimmer: some View {
        Path { p in
            p.addRect(CGRect(origin: .zero, size: containerSize))
            p.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        }
        .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private var pulseRing: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(DS.Color.accent, lineWidth: 2)
            .frame(width: cutout.width, height: cutout.height)
            .scaleEffect(1 + 0.18 * pulse)
            .opacity(1 - pulse)
            .position(x: cutout.midX, y: cutout.midY)
            .allowsHitTesting(false)
            .onAppear {
                pulse = 0
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulse = 1
                }
            }
    }

    @ViewBuilder
    private var tooltip: some View {
        let placement = tooltipPlacement()
        VStack(spacing: DS.Spacing.xs) {
            Text(step.tooltip)
                .font(DS.Font.callout).bold()
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Step \(step.rawValue + 1) of \(CoachStep.allCases.count)")
                .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Color.surface1)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
        .frame(maxWidth: min(320, containerSize.width - 48))
        .position(placement)
        .allowsHitTesting(false)
    }

    private var skipButton: some View {
        Button {
            coach.finish()
        } label: {
            Text("Skip tour")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textSecondary)
                .padding(.horizontal, DS.Spacing.sm)
                .padding(.vertical, DS.Spacing.xs)
                .background(
                    Capsule().fill(DS.Color.surface1.opacity(0.85))
                )
        }
        .position(x: containerSize.width - 60, y: 50)
    }

    private func tooltipPlacement() -> CGPoint {
        let bottomBuffer: CGFloat = keyboardHeight > 0 ? keyboardHeight + 70 : 120
        let y = containerSize.height - bottomBuffer
        return CGPoint(x: containerSize.width / 2, y: y)
    }
}
#endif

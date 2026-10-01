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
        case .save:       return "Fill in the server, then tap ✓."
        case .tapHost:    return "Tap your server to open its sessions."
        case .newSession: return "Tap + to open a terminal."
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
    @State private var dismissed = false

    private let padding: CGFloat = 6
    private let gap: CGFloat = 10
    private let edge: CGFloat = 16
    private let arrowSize = CGSize(width: 18, height: 9)

    private var cutout: CGRect {
        let padded = rect.insetBy(dx: -padding, dy: -padding)
        guard abs(padded.width - padded.height) < 16 else { return padded }
        let side = max(padded.width, padded.height)
        return CGRect(x: padded.midX - side / 2, y: padded.midY - side / 2, width: side, height: side)
    }
    private var cornerRadius: CGFloat { cutout.width == cutout.height ? cutout.width / 2 : 16 }
    private var cardWidth: CGFloat { min(300, containerSize.width - edge * 2) }
    private var placeBelow: Bool { cutout.midY < containerSize.height / 2 }
    private var cardMinX: CGFloat { min(max(cutout.midX - cardWidth / 2, edge), containerSize.width - cardWidth - edge) }
    private var arrowX: CGFloat { min(max(cutout.midX - cardMinX, 22), cardWidth - 22) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !dismissed {
                dimmer
                pulseRing
                if step == .save {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.2)) { dismissed = true }
                        }
                }
                tooltip
            }
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
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(DS.Color.accent, lineWidth: 2)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(DS.Color.accent, lineWidth: 2)
                .scaleEffect(1 + 0.12 * pulse)
                .opacity(1 - pulse)
        }
        .frame(width: cutout.width, height: cutout.height)
        .position(x: cutout.midX, y: cutout.midY)
        .allowsHitTesting(false)
        .onAppear {
            pulse = 0
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = 1
            }
        }
    }

    private var tooltip: some View {
        VStack(spacing: 0) {
            if placeBelow { arrow(pointingUp: true) }
            card
            if !placeBelow { arrow(pointingUp: false) }
        }
        .frame(width: cardWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placeBelow ? .topLeading : .bottomLeading)
        .padding(.leading, cardMinX)
        .padding(.top, placeBelow ? cutout.maxY + gap : 0)
        .padding(.bottom, placeBelow ? 0 : containerSize.height - cutout.minY + gap)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(step.tooltip)
                .font(DS.Font.callout).bold()
                .foregroundStyle(DS.Color.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Step \(step.rawValue + 1) of \(CoachStep.allCases.count)")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                Spacer()
                Button("Skip tour") { coach.finish() }
                    .font(DS.Font.caption.bold())
                    .foregroundStyle(DS.Color.accent)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Color.surface1)
                .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
        )
    }

    private func arrow(pointingUp: Bool) -> some View {
        CoachArrow(pointingUp: pointingUp)
            .fill(DS.Color.surface1)
            .frame(width: arrowSize.width, height: arrowSize.height)
            .padding(.leading, arrowX - arrowSize.width / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CoachArrow: Shape {
    let pointingUp: Bool

    func path(in r: CGRect) -> Path {
        let tip = CGPoint(x: r.midX, y: pointingUp ? r.minY : r.maxY)
        let baseY = pointingUp ? r.maxY : r.minY
        return Path { p in
            p.move(to: tip)
            p.addLine(to: CGPoint(x: r.maxX, y: baseY))
            p.addLine(to: CGPoint(x: r.minX, y: baseY))
            p.closeSubpath()
        }
    }
}
#endif

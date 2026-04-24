import Foundation

/// Describes why the paywall is being presented. Lives in Core so
/// `AppRouter.Sheet` can carry it as an associated value.
public enum PaywallContext: Hashable, Sendable {
    /// A sshido+ feature was tapped (mascot, theme, sync, etc.).
    case plusLocked(feature: String)
    /// A Cloud Pro feature was tapped (multiple endpoints, webhook, etc.).
    case cloudLocked(feature: String)
    /// User opened the paywall from Settings without a specific trigger.
    case upgrade

    public var headline: String {
        switch self {
        case .plusLocked: return "Unlock with sshido+"
        case .cloudLocked: return "Upgrade to sshido Cloud Pro"
        case .upgrade: return "Upgrade sshido"
        }
    }

    public var subheadline: String {
        switch self {
        case .plusLocked(let feature):
            return "\(feature) is part of sshido+. One-time purchase, lifetime access, Family Sharing."
        case .cloudLocked(let feature):
            return "\(feature) is part of sshido Cloud Pro. Cancel anytime."
        case .upgrade:
            return "Choose what fits. Core SSH, Mosh, and push notifications stay free, forever."
        }
    }

    public var emphasis: Emphasis {
        switch self {
        case .plusLocked: return .plus
        case .cloudLocked: return .cloud
        case .upgrade: return .none
        }
    }

    public enum Emphasis: Sendable { case plus, cloud, none }
}

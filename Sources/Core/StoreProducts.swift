import Foundation

/// Product identifiers that match entries in App Store Connect and
/// `XcodeProject/StoreKit.storekit`. Changing any of these breaks existing
/// purchases — treat as append-only.
public enum StoreProducts {
    /// One-time, non-consumable. Unlocks all sshido+ cosmetics & QoL
    /// (mascot packs, premium themes, CloudKit sync, widgets/Live
    /// Activities, haptic & sound themes). Family Sharing enabled.
    public static let plusLifetime = "com.sshido.app.plus.lifetime"

    /// Auto-renewable subscription — sshido Cloud Pro tier, monthly billing.
    /// Unlocks multiple relay endpoints, webhook-to-push bridge, SLA.
    public static let cloudMonthly = "com.sshido.app.cloud.monthly"

    /// Auto-renewable subscription — sshido Cloud Pro tier, yearly billing.
    public static let cloudYearly = "com.sshido.app.cloud.yearly"

    public static let all: [String] = [plusLifetime, cloudMonthly, cloudYearly]

    public static let cloudProductIDs: Set<String> = [cloudMonthly, cloudYearly]
    public static let plusProductIDs: Set<String> = [plusLifetime]
}

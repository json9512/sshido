import Foundation
import StoreKit

/// Source of truth for what the current user has paid for.
///
/// Reads directly from StoreKit's `Transaction.currentEntitlements` — no
/// local caching, no receipt validation servers. StoreKit 2's signed
/// verification result is authoritative.
///
/// Usage pattern:
///   - `sshidoApp` calls `Entitlements.shared.startObservingTransactionUpdates()`
///     once at launch.
///   - SwiftUI views observe `@ObservedObject` / `@EnvironmentObject` and
///     read `hasPlus` / `hasCloudPro`.
///   - Gating helpers `requirePlus(_:)` / `requireCloudPro(_:)` push the
///     paywall sheet via the router when an entitlement is missing.
@MainActor
public final class Entitlements: ObservableObject {
    public static let shared = Entitlements()

    @Published public private(set) var hasPlus: Bool = false
    @Published public private(set) var hasCloudPro: Bool = false
    @Published public private(set) var cloudProExpiry: Date?

    /// Cached `Product` objects fetched from StoreKit. Populated by `loadProducts()`.
    @Published public private(set) var products: [Product] = []

    private var transactionUpdatesTask: Task<Void, Never>?

    public init() {}

    /// Begin observing Transaction.updates in the background.
    /// Call exactly once at app launch (before the first UI that could
    /// trigger a purchase).
    public func startObservingTransactionUpdates() {
        guard transactionUpdatesTask == nil else { return }
        transactionUpdatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
        Task { await refresh() }
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    /// Re-read current entitlements from StoreKit. Call after any purchase
    /// or restore, and at launch.
    public func refresh() async {
        var plus = false
        var cloud = false
        var cloudExpiry: Date?

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if transaction.revocationDate != nil { continue }
            if StoreProducts.plusProductIDs.contains(transaction.productID) {
                plus = true
            }
            if StoreProducts.cloudProductIDs.contains(transaction.productID) {
                // Subscription is active if expiration is in the future (or
                // unset for legacy non-expiring subs).
                if let expiry = transaction.expirationDate {
                    if expiry > Date() {
                        cloud = true
                        if cloudExpiry == nil || expiry > cloudExpiry! {
                            cloudExpiry = expiry
                        }
                    }
                } else {
                    cloud = true
                }
            }
        }

        self.hasPlus = plus
        self.hasCloudPro = cloud
        self.cloudProExpiry = cloudExpiry
    }

    /// Fetch products from the App Store (or StoreKit config file in dev).
    /// Call before presenting the paywall so prices are localized.
    public func loadProducts() async {
        do {
            let loaded = try await Product.products(for: StoreProducts.all)
            // Stable sort: sshido+ first, then monthly, then yearly.
            self.products = loaded.sorted { a, b in
                let order: [String: Int] = [
                    StoreProducts.plusLifetime: 0,
                    StoreProducts.cloudMonthly: 1,
                    StoreProducts.cloudYearly: 2,
                ]
                return (order[a.id] ?? 99) < (order[b.id] ?? 99)
            }
        } catch {
            Log.store.error("loadProducts failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func product(for id: String) -> Product? {
        products.first { $0.id == id }
    }

    /// Attempt to purchase a product. Returns the successful transaction,
    /// or nil if the user cancelled. Throws on verification failure.
    @discardableResult
    public func purchase(_ product: Product) async throws -> Transaction? {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification)
            await transaction.finish()
            await refresh()
            return transaction
        case .userCancelled:
            return nil
        case .pending:
            // Ask-to-Buy / SCA deferred transactions — resolution arrives
            // via Transaction.updates and updates entitlements then.
            return nil
        @unknown default:
            return nil
        }
    }

    /// Trigger StoreKit's "Restore Purchases" sync. The actual entitlement
    /// refresh happens automatically via Transaction.updates, but this
    /// nudges the sync and refreshes immediately afterwards.
    public func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    #if DEBUG
    /// Developer-only entitlement override for smoke-testing premium
    /// gating without a real StoreKit purchase. DEBUG builds only — the
    /// #if DEBUG block ensures release binaries cannot flip entitlements
    /// through any path other than a signed transaction.
    public func debugSetEntitlements(plus: Bool, cloud: Bool) {
        self.hasPlus = plus
        self.hasCloudPro = cloud
        if !cloud { self.cloudProExpiry = nil }
    }
    #endif

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else {
            Log.store.error("Entitlements received unverified transaction")
            return
        }
        await transaction.finish()
        await refresh()
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}

#if canImport(UIKit)
import SwiftUI
import StoreKit
#if canImport(sshidoCore)
import sshidoCore
#endif

struct PaywallView: View {
    let context: PaywallContext

    @EnvironmentObject private var router: AppRouter
    @ObservedObject private var entitlements = Entitlements.shared
    @Environment(\.dismiss) private var dismiss

    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var loadFinished = false
    @State private var productsUnavailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    hero
                    stackingHint
                    plusCard
                    cloudCard
                    if productsUnavailable {
                        productsUnavailableNote
                    }
                    if let error = errorMessage {
                        InlineErrorText(error)
                    }
                    legalFooter
                }
                .padding(.horizontal, DS.Spacing.lg)
                .padding(.vertical, DS.Spacing.lg)
            }
            .background(DS.Color.surface0)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { Task { await restore() } }
                        .disabled(isPurchasing)
                }
            }
            .task {
                await entitlements.loadProducts()
                loadFinished = true
                productsUnavailable = entitlements.products.isEmpty
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundStyle(DS.Color.accent)
                .padding(.top, DS.Spacing.lg)
            Text(context.headline)
                .font(DS.Font.displayLarge)
                .foregroundStyle(DS.Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(context.subheadline)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Stacking hint

    /// Most users pick one tier, but the two products stack. This banner
    /// sets that expectation so nobody buys sshido+ expecting Cloud Pro.
    @ViewBuilder
    private var stackingHint: some View {
        if !(entitlements.hasPlus && entitlements.hasCloudPro) {
            HStack(alignment: .top, spacing: DS.Spacing.sm) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(DS.Color.accent)
                Text("These stack. sshido+ unlocks app features; Cloud Pro unlocks hosted relay features. Power users buy both.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            .padding(DS.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.surface2))
        }
    }

    // MARK: - sshido+ card

    @ViewBuilder
    private var plusCard: some View {
        let product = entitlements.product(for: StoreProducts.plusLifetime)
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("sshido+ — app features").font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("One-time · Lifetime · Family Sharing")
                        .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                priceLabel(product: product, placeholder: "$14.99")
            }

            featureList([
                ("paintpalette.fill", "Premium mascot packs"),
                ("swatchpalette.fill", "Curated terminal themes"),
                ("icloud.fill",        "CloudKit sync across devices"),
                ("rectangle.stack.fill.badge.plus", "Widgets, Live Activities, Watch"),
                ("waveform",           "Haptic & sound themes"),
            ])

            cta(
                product: product,
                alreadyOwned: entitlements.hasPlus,
                ownedLabel: "You already own sshido+",
                buyLabel: "Unlock"
            )
        }
        .padding(DS.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg).fill(DS.Color.surface1))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(context.emphasis == .plus ? DS.Color.accent : DS.Color.titaniumDark,
                        lineWidth: context.emphasis == .plus ? 2 : 1)
        )
    }

    // MARK: - Cloud Pro card

    @ViewBuilder
    private var cloudCard: some View {
        let monthly = entitlements.product(for: StoreProducts.cloudMonthly)
        let yearly  = entitlements.product(for: StoreProducts.cloudYearly)

        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("sshido Cloud Pro — hosted features").font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Hosted relay with power features · Cancel anytime")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }

            featureList([
                ("link",                "Multiple named relay endpoints"),
                ("arrow.triangle.branch","Webhook-to-push bridge (GitHub, Linear, Sentry)"),
                ("shield.lefthalf.filled", "Published 99.9% SLA"),
            ])

            Text("Not included in sshido+. Cloud features require hosted infrastructure.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)

            if entitlements.hasCloudPro {
                Text("Already subscribed\(entitlements.cloudProExpiry.map { " · renews \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    subscriptionButton(
                        product: monthly,
                        placeholderPrice: "$4.99",
                        periodSuffix: "/ month",
                        style: .secondary
                    )
                    subscriptionButton(
                        product: yearly,
                        placeholderPrice: "$39.99",
                        periodSuffix: "/ year",
                        badge: "Save ~33%",
                        style: .primary
                    )
                }
                .disabled(isPurchasing || (monthly == nil && yearly == nil))
            }
        }
        .padding(DS.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: DS.Radius.lg).fill(DS.Color.surface1))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(context.emphasis == .cloud ? DS.Color.accent : DS.Color.titaniumDark,
                        lineWidth: context.emphasis == .cloud ? 2 : 1)
        )
    }

    // MARK: - Helpers

    @ViewBuilder
    private func priceLabel(product: Product?, placeholder: String) -> some View {
        if let product {
            Text(product.displayPrice)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.textPrimary)
        } else if loadFinished {
            // StoreKit returned no product. Show the intended retail price
            // greyed out so the paywall remains informative.
            Text(placeholder)
                .font(DS.Font.headline)
                .foregroundStyle(DS.Color.textTertiary)
        } else {
            ProgressView().controlSize(.small)
        }
    }

    @ViewBuilder
    private func featureList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            ForEach(items, id: \.1) { icon, label in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 14))
                        .frame(width: 20, alignment: .center)
                    Text(label)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                }
            }
        }
    }

    @ViewBuilder
    private func cta(product: Product?,
                     alreadyOwned: Bool,
                     ownedLabel: String,
                     buyLabel: String) -> some View {
        if alreadyOwned {
            Text(ownedLabel)
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)
        } else if let product {
            Button {
                Task { await purchase(product) }
            } label: {
                if isPurchasing {
                    ProgressView().tint(DS.Color.textOnAccent)
                } else {
                    Text(buyLabel).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(DSPrimaryButtonStyle())
            .disabled(isPurchasing)
        } else {
            Button(buyLabel) {}
                .buttonStyle(DSPrimaryButtonStyle())
                .frame(maxWidth: .infinity)
                .disabled(true)
                .opacity(loadFinished ? 0.5 : 1)
        }
    }

    private enum CTAStyle { case primary, secondary }

    @ViewBuilder
    private func subscriptionButton(
        product: Product?,
        placeholderPrice: String,
        periodSuffix: String,
        badge: String? = nil,
        style: CTAStyle
    ) -> some View {
        let price = product?.displayPrice ?? placeholderPrice
        let priceText = "\(price) \(periodSuffix)"
        let label = VStack(spacing: 2) {
            Text(priceText)
                .font(DS.Font.headline)
                .opacity(product == nil ? 0.6 : 1)
            if let badge {
                Text(badge).font(DS.Font.caption)
            }
        }
        .frame(maxWidth: .infinity)

        Group {
            if let product {
                Button { Task { await purchase(product) } } label: { label }
            } else {
                Button {} label: { label }
                    .disabled(true)
                    .opacity(loadFinished ? 0.5 : 1)
            }
        }
        .buttonStyle(style == .primary ? AnyButtonStyle(DSPrimaryButtonStyle())
                                       : AnyButtonStyle(DSSecondaryButtonStyle()))
    }

    @ViewBuilder
    private var productsUnavailableNote: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(DS.Color.textTertiary)
            Text("In-app purchases are not available yet on this build. Products are pending App Store Connect setup. Launch from Xcode to test against the local StoreKit configuration.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)
        }
        .padding(DS.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.surface2))
    }

    @ViewBuilder
    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Self-hosting the relay stays free forever. sshido Cloud Pro adds hosted features on top; you can always run your own.")
            Text("Subscriptions auto-renew until cancelled in iOS Settings → Apple ID → Subscriptions. Purchases are subject to Apple's Terms.")
        }
        .font(DS.Font.caption)
        .foregroundStyle(DS.Color.textTertiary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Actions

    private func purchase(_ product: Product) async {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if let tx = try await entitlements.purchase(product) {
                Log.store.info("Purchase succeeded: \(tx.productID, privacy: .public)")
                dismiss()
            }
        } catch {
            errorMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    private func restore() async {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await entitlements.restore()
            if entitlements.hasPlus || entitlements.hasCloudPro {
                dismiss()
            } else {
                errorMessage = "Nothing to restore on this Apple ID."
            }
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }
}

/// Type-erased button style wrapper — lets us choose primary/secondary at
/// runtime without the compiler complaining about heterogeneous `.buttonStyle`.
private struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        self._makeBody = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View {
        _makeBody(configuration)
    }
}
#endif

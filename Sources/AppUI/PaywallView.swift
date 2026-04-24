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
    @State private var toast: String?
    @State private var loadFinished = false
    @State private var productsUnavailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xxl) {
                    hero
                    plusCard
                    cloudCard
                    if productsUnavailable {
                        productsUnavailableNote
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
            .toast($toast)
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

    // MARK: - sshido+ card

    @ViewBuilder
    private var plusCard: some View {
        let product = entitlements.product(for: StoreProducts.plusLifetime)
        card(emphasized: context.emphasis == .plus) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                cardHeader(
                    title: "sshido+ — app features",
                    subtitle: "One-time · Lifetime · Family Sharing",
                    priceText: product?.displayPrice ?? "$14.99",
                    priceActive: product != nil || !loadFinished
                )
                featureList([
                    ("paintpalette.fill", "Premium mascot packs"),
                    ("swatchpalette.fill", "Curated terminal themes"),
                    ("icloud.fill",        "CloudKit sync across devices"),
                    ("rectangle.stack.fill.badge.plus", "Widgets, Live Activities, Watch"),
                    ("waveform",           "Haptic & sound themes"),
                ])
                if entitlements.hasPlus {
                    ownedNote("You already own sshido+")
                } else {
                    ctaButton(
                        primaryText: "Unlock",
                        secondaryText: nil,
                        product: product,
                        style: .primary
                    )
                }
            }
        }
    }

    // MARK: - Cloud Pro card

    @ViewBuilder
    private var cloudCard: some View {
        let monthly = entitlements.product(for: StoreProducts.cloudMonthly)
        let yearly  = entitlements.product(for: StoreProducts.cloudYearly)

        card(emphasized: context.emphasis == .cloud) {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                cardHeader(
                    title: "sshido Cloud Pro — hosted features",
                    subtitle: "Hosted relay with power features · Cancel anytime",
                    priceText: nil,
                    priceActive: true
                )
                featureList([
                    ("link",                    "Multiple named relay endpoints"),
                    ("arrow.triangle.branch",   "Webhook-to-push bridge (GitHub, Linear, Sentry)"),
                    ("shield.lefthalf.filled",  "Published 99.9% SLA"),
                ])
                Text("Not included in sshido+. Cloud features require hosted infrastructure.")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                if entitlements.hasCloudPro {
                    ownedNote(
                        "Already subscribed" +
                        (entitlements.cloudProExpiry.map { " · renews \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")
                    )
                } else {
                    HStack(spacing: DS.Spacing.md) {
                        ctaButton(
                            primaryText: monthly?.displayPrice ?? "$4.99",
                            secondaryText: "/ month",
                            product: monthly,
                            style: .secondary
                        )
                        ctaButton(
                            primaryText: yearly?.displayPrice ?? "$39.99",
                            secondaryText: "/ year · Save ~33%",
                            product: yearly,
                            style: .primary
                        )
                    }
                }
            }
        }
    }

    // MARK: - Card primitives

    @ViewBuilder
    private func card<Content: View>(emphasized: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(DS.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: DS.Radius.lg).fill(DS.Color.surface1))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .stroke(emphasized ? DS.Color.accent : DS.Color.titaniumDark,
                            lineWidth: emphasized ? 2 : 1)
            )
    }

    @ViewBuilder
    private func cardHeader(title: String, subtitle: String, priceText: String?, priceActive: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text(subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.textSecondary)
            }
            Spacer(minLength: DS.Spacing.md)
            if let priceText {
                Text(priceText)
                    .font(DS.Font.headline)
                    .foregroundStyle(priceActive ? DS.Color.textPrimary : DS.Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func featureList(_ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            ForEach(items, id: \.1) { icon, label in
                HStack(alignment: .top, spacing: DS.Spacing.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(DS.Color.accent)
                        .font(.system(size: 14))
                        .frame(width: 20, alignment: .center)
                    Text(label)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func ownedNote(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.caption)
            .foregroundStyle(DS.Color.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - CTA button

    private enum CTAStyle { case primary, secondary }

    /// Single unified button builder so every CTA (sshido+ Unlock, Cloud
    /// Pro monthly, Cloud Pro yearly) has identical height, padding, and
    /// font sizing. Primary style fills with accent; secondary outlines.
    @ViewBuilder
    private func ctaButton(
        primaryText: String,
        secondaryText: String?,
        product: Product?,
        style: CTAStyle
    ) -> some View {
        let enabled = product != nil && !isPurchasing
        let label = VStack(spacing: 2) {
            Text(primaryText)
                .font(DS.Font.headline)
            if let secondaryText {
                Text(secondaryText)
                    .font(DS.Font.caption)
                    .opacity(0.9)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 22)
        .padding(.vertical, DS.Spacing.sm)

        Group {
            if let product {
                Button { Task { await purchase(product) } } label: {
                    if isPurchasing {
                        ProgressView()
                            .tint(style == .primary ? DS.Color.textOnAccent : DS.Color.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else {
                        label
                    }
                }
            } else {
                Button {} label: { label }
                    .disabled(true)
            }
        }
        .buttonStyle(style == .primary ? AnyButtonStyle(DSPrimaryButtonStyle())
                                       : AnyButtonStyle(DSSecondaryButtonStyle()))
        .opacity(enabled ? 1 : 0.5)
        .disabled(!enabled)
    }

    // MARK: - Unavailable + footer

    @ViewBuilder
    private var productsUnavailableNote: some View {
        HStack(alignment: .top, spacing: DS.Spacing.sm) {
            Image(systemName: "info.circle")
                .foregroundStyle(DS.Color.textTertiary)
            Text("In-app purchases are not available yet on this build. Products are pending App Store Connect setup. Launch from Xcode to test against the local StoreKit configuration.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if let tx = try await entitlements.purchase(product) {
                Log.store.info("Purchase succeeded: \(tx.productID, privacy: .public)")
                dismiss()
            }
        } catch {
            toast = "Purchase failed: \(error.localizedDescription)"
        }
    }

    private func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await entitlements.restore()
            if entitlements.hasPlus || entitlements.hasCloudPro {
                dismiss()
            } else {
                toast = "Nothing to restore on this Apple ID."
            }
        } catch {
            toast = "Restore failed: \(error.localizedDescription)"
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

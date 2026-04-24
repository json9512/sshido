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
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DS.Spacing.xl) {
                    hero
                    if !loaded {
                        ProgressView().padding(.vertical, DS.Spacing.xl)
                    } else {
                        products
                        legalFooter
                    }
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
                loaded = true
            }
        }
    }

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

    @ViewBuilder
    private var products: some View {
        VStack(spacing: DS.Spacing.md) {
            if let plus = entitlements.product(for: StoreProducts.plusLifetime) {
                productCard(
                    product: plus,
                    title: "sshido+",
                    subtitle: "One-time. Lifetime. Family Sharing.",
                    bullets: [
                        "Premium mascot packs",
                        "Curated terminal themes",
                        "CloudKit sync across devices",
                        "Widgets, Live Activities, Watch",
                        "Haptic & sound themes",
                    ],
                    emphasized: context.emphasis == .plus,
                    alreadyOwned: entitlements.hasPlus,
                    cta: "Unlock"
                )
            }
            if let monthly = entitlements.product(for: StoreProducts.cloudMonthly),
               let yearly = entitlements.product(for: StoreProducts.cloudYearly) {
                cloudCard(monthly: monthly, yearly: yearly)
            }
            if let error = errorMessage {
                InlineErrorText(error)
            }
        }
    }

    @ViewBuilder
    private func productCard(
        product: Product,
        title: String,
        subtitle: String,
        bullets: [String],
        emphasized: Bool,
        alreadyOwned: Bool,
        cta: String
    ) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(title).font(DS.Font.headline)
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(subtitle).font(DS.Font.caption)
                        .foregroundStyle(DS.Color.textSecondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textPrimary)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                ForEach(bullets, id: \.self) { bullet in
                    HStack(alignment: .top, spacing: DS.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Color.accent)
                            .font(.system(size: 14))
                        Text(bullet).font(DS.Font.body)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                }
            }
            if alreadyOwned {
                Text("You already own this.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            } else {
                Button {
                    Task { await purchase(product) }
                } label: {
                    if isPurchasing {
                        ProgressView().tint(DS.Color.textOnAccent)
                    } else {
                        Text(cta).frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(isPurchasing)
            }
        }
        .padding(DS.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(emphasized ? DS.Color.accent : DS.Color.titaniumDark, lineWidth: emphasized ? 2 : 1)
        )
    }

    @ViewBuilder
    private func cloudCard(monthly: Product, yearly: Product) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("sshido Cloud Pro").font(DS.Font.headline)
                    .foregroundStyle(DS.Color.textPrimary)
                Text("Hosted relay with power features. Cancel anytime.")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                ForEach([
                    "Multiple named relay endpoints",
                    "Webhook-to-push bridge (GitHub, Linear, Sentry)",
                    "Published 99.9% SLA",
                ], id: \.self) { bullet in
                    HStack(alignment: .top, spacing: DS.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Color.accent)
                            .font(.system(size: 14))
                        Text(bullet).font(DS.Font.body)
                            .foregroundStyle(DS.Color.textPrimary)
                    }
                }
            }
            if entitlements.hasCloudPro {
                Text("Already subscribed\(entitlements.cloudProExpiry.map { " · renews \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "").")
                    .font(DS.Font.caption).foregroundStyle(DS.Color.textTertiary)
            } else {
                HStack(spacing: DS.Spacing.sm) {
                    Button {
                        Task { await purchase(monthly) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Monthly").font(DS.Font.caption)
                            Text(monthly.displayPrice).font(DS.Font.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DSSecondaryButtonStyle())
                    Button {
                        Task { await purchase(yearly) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Yearly · best value").font(DS.Font.caption)
                            Text(yearly.displayPrice).font(DS.Font.headline)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(DSPrimaryButtonStyle())
                }
                .disabled(isPurchasing)
            }
        }
        .padding(DS.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .fill(DS.Color.surface1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(context.emphasis == .cloud ? DS.Color.accent : DS.Color.titaniumDark,
                        lineWidth: context.emphasis == .cloud ? 2 : 1)
        )
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
#endif

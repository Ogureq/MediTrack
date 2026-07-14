import SwiftUI
import StoreKit

/// Premium upsell sheet. Presented from Profile & Settings (and, later,
/// from the AI report flow once its lifetime free allowance is used up).
///
/// Copy is deliberately educational, never promising a medical outcome:
/// premium only unlocks *more AI narration* of the same deterministic,
/// rule-based analysis that stays free for everyone. If StoreKit products
/// fail to resolve — expected in this build, since no Apple Developer
/// account is connected yet — the sheet says so plainly instead of showing
/// broken purchase buttons.
struct PaywallView: View {
    @ObservedObject private var store = PremiumStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var purchasingProductID: String?
    @State private var purchaseErrorMessage: String?
    @State private var isRestoring = false
    @State private var presentedLegalDocument: LegalDocument?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PaywallHeader()

                if store.isPremium {
                    activeCard
                }

                featureList

                if store.loadState == .unavailable {
                    unavailableCard
                } else {
                    productSection
                }

                restoreButton

                freeTierFootnote

                footerLinks
            }
            .padding()
        }
        .ambientScreen()
        .overlay(alignment: .topTrailing) { closeButton }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        .task {
            await store.loadProducts()
        }
        .alert(
            "Purchase",
            isPresented: Binding(
                get: { purchaseErrorMessage != nil },
                set: { if !$0 { purchaseErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(purchaseErrorMessage ?? "")
        }
        .sheet(item: $presentedLegalDocument) { document in
            LegalView(document: document)
        }
    }

    // MARK: Sections

    private var activeCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text("Premium is active on this device. Thank you for supporting Gemocode.")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .tintedGlassCard(.green)
        .accessibilityElement(children: .combine)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaywallFeatureRow(
                icon: "doc.viewfinder",
                title: "Scan & decode lab reports",
                detail: "Photograph any lab report — values extracted and organized automatically."
            )
            PaywallFeatureRow(
                icon: "doc.text.magnifyingglass",
                title: "Unlimited AI health reports",
                detail: "Plain-language narration of your health score and findings, any time."
            )
            PaywallFeatureRow(
                icon: "wand.and.stars",
                title: "AI-assisted Quick Add and future AI features",
                detail: "New AI tools land here first as Gemocode grows."
            )
            PaywallFeatureRow(
                icon: "heart.fill",
                title: "Support ongoing development",
                detail: "Gemocode has no ads and sells no data — premium is what keeps it going."
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var unavailableCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Purchases aren't available in this build yet.")
                    .font(.subheadline.weight(.semibold))
                Text("This preview isn't connected to the App Store yet, so premium plans can't be shown or purchased here. Everything else in Gemocode works normally.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .tintedGlassCard(.orange)
        .accessibilityElement(children: .combine)
    }

    private var productSection: some View {
        VStack(spacing: 10) {
            if store.loadState == .loading {
                ProgressView("Loading plans…")
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ForEach(store.products, id: \.id) { product in
                    PaywallProductCard(
                        product: product,
                        isYearly: product.id == PremiumStore.yearlyProductID,
                        isLifetime: product.id == PremiumStore.lifetimeProductID,
                        isPurchasing: purchasingProductID == product.id,
                        isDisabled: purchasingProductID != nil && purchasingProductID != product.id
                    ) {
                        performPurchase(product)
                    }
                }
            }
        }
    }

    private var restoreButton: some View {
        Button {
            performRestore()
        } label: {
            if isRestoring {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Restoring…")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Restore Purchases")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(isRestoring)
    }

    private var freeTierFootnote: some View {
        Text("Tracking vitals, medications, symptoms, and goals — with your health score, trends, and backups — stays free. Your first AI scan and health report is included free; Premium unlocks unlimited lab report scanning, AI reports, chat, and AI-assisted entry.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var footerLinks: some View {
        HStack(spacing: 6) {
            Button {
                presentedLegalDocument = .termsOfService
            } label: {
                Text("Terms of Service").underline()
            }
            Text("•")
                .foregroundStyle(.tertiary)
            Button {
                presentedLegalDocument = .privacyPolicy
            } label: {
                Text("Privacy Policy").underline()
            }
        }
        .font(.caption2)
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary, .ultraThinMaterial)
                .symbolRenderingMode(.palette)
        }
        .padding(12)
        .accessibilityLabel("Close")
    }

    // MARK: Actions

    private func performPurchase(_ product: Product) {
        purchasingProductID = product.id
        Task {
            do {
                try await store.purchase(product)
                purchasingProductID = nil
                if store.isPremium {
                    Haptics.success()
                    dismiss()
                }
            } catch {
                purchasingProductID = nil
                purchaseErrorMessage = error.localizedDescription
            }
        }
    }

    private func performRestore() {
        isRestoring = true
        Task {
            await store.restorePurchases()
            isRestoring = false
            if store.isPremium {
                Haptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - Header

private struct PaywallHeader: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Glass.accentGradient)
                    .frame(width: 68, height: 68)
                Image(systemName: "crown.fill")
                    .font(.title.weight(.semibold))
                    .foregroundStyle(.white)
                Image(systemName: "sparkles")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .offset(x: 20, y: -20)
            }
            .accessibilityHidden(true)

            Text("Gemocode Premium")
                .font(.title2.bold())
                .fontDesign(.rounded)

            Text("More AI narration of your health data. Nothing you track today ever gets locked away.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

// MARK: - Feature row

private struct PaywallFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Glass.accentGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Product card

private struct PaywallProductCard: View {
    let product: Product
    let isYearly: Bool
    var isLifetime: Bool = false
    let isPurchasing: Bool
    let isDisabled: Bool
    let action: () -> Void

    private var planName: String {
        if product.displayName.isEmpty {
            if isLifetime { return "Lifetime" }
            return isYearly ? "Yearly" : "Monthly"
        }
        return product.displayName
    }

    private var periodSuffix: String {
        if isLifetime { return " once" }
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return period.value == 1 ? "/day" : "/\(period.value) days"
        case .week: return period.value == 1 ? "/week" : "/\(period.value) weeks"
        case .month: return period.value == 1 ? "/month" : "/\(period.value) months"
        case .year: return period.value == 1 ? "/year" : "/\(period.value) years"
        @unknown default: return ""
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(planName)
                            .font(.subheadline.weight(.semibold))
                        if isYearly {
                            StatusPill(text: "Best value", color: .green)
                        } else if isLifetime {
                            StatusPill(text: "One-time", color: .teal)
                        }
                    }
                    Text("\(product.displayPrice)\(periodSuffix)")
                        .font(.title3.weight(.bold))
                        .fontDesign(.rounded)
                }
                Spacer(minLength: 0)
                if isPurchasing {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: Glass.chipRadius)
        .opacity(isDisabled && !isPurchasing ? 0.5 : 1)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(planName) plan, \(product.displayPrice)\(periodSuffix)\(isYearly ? ", best value" : "")\(isLifetime ? ", one-time purchase" : "")"
        )
        .accessibilityHint(
            isPurchasing
                ? "Purchase in progress"
                : (isLifetime ? "Double tap to purchase" : "Double tap to subscribe")
        )
    }
}

#Preview {
    PaywallView()
}

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
///
/// Presentation follows the editorial "two ledger columns" grammar: an
/// "Always Free" list and a "Premium Adds" list stand side by side in
/// reading order, then the real `store.products` render as price rows
/// (the best-value plan filled with the one accent color, everything else
/// outlined) — restyled only; the StoreKit calls, product IDs, and
/// double-tap/double-purchase guards below are unchanged.
struct PaywallView: View {
    @ObservedObject private var store = PremiumStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var purchasingProductID: String?
    @State private var purchaseErrorMessage: String?
    @State private var isRestoring = false
    @State private var presentedLegalDocument: LegalDocument?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaywallHeader()

                if store.isPremium {
                    // Nulled: `.task { await store.loadProducts() }` and
                    // `store`'s async entitlement refresh can both land
                    // during sheet presentation, moments after this view
                    // first appears. Without this, an ambient transaction
                    // already in flight at that moment gets inherited by
                    // this card's insertion and animates it in from a
                    // stale/offset frame — same reasoning as ReviewScreen's
                    // cards.
                    activeCard
                        .transaction { $0.animation = nil }
                }

                freeLedger
                premiumLedger

                if store.loadState == .unavailable {
                    unavailableCard
                        .transaction { $0.animation = nil }
                } else {
                    productSection
                        .transaction { $0.animation = nil }
                }

                restoreButton

                footerLinks
            }
            .padding()
        }
        .ambientScreen()
        .overlay(alignment: .topTrailing) { closeButton }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Editorial.canvas(colorScheme))
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
                .foregroundStyle(Editorial.tagGood(colorScheme))
                .accessibilityHidden(true)
            Text("Premium is active on this device. Thank you for supporting Gemocode.")
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .tintedGlassCard(.green)
        .accessibilityElement(children: .combine)
    }

    /// "Always Free" ledger — everything Gemocode's local, on-device
    /// tracking already gives away for free, stated up front so the
    /// comparison below reads as an honest add-on, not a lock.
    private var freeLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroLabel("Always Free")
                .padding(.bottom, 6)
            PaywallLedgerRow(marker: "✓", markerColor: Editorial.tagGood(colorScheme), title: "Tracking, health score, trends & backups")
            PaywallLedgerRow(marker: "✓", markerColor: Editorial.tagGood(colorScheme), title: "Retest schedule & reminders")
            PaywallLedgerRow(marker: "✓", markerColor: Editorial.tagGood(colorScheme), title: "Your first AI scan & report")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "Premium Adds" ledger, reflowed as ledger rows. The middle row is a
    /// deliberate softening of the source mockup's "exact supplements &
    /// doses" — an orchestrator-level copy decision to avoid implying a
    /// prescriptive/diagnostic promise (see `AnalysisEngine`'s
    /// educational-not-diagnostic stance).
    private var premiumLedger: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Premium Adds")
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.6)
                .textCase(.uppercase)
                .foregroundStyle(Editorial.accent(colorScheme))
                .padding(.bottom, 6)
            PaywallLedgerRow(
                marker: "+",
                markerColor: Editorial.accent(colorScheme),
                title: "Unlimited scans, decoded in seconds"
            )
            PaywallLedgerRow(
                marker: "+",
                markerColor: Editorial.accent(colorScheme),
                title: "Action plan — supplements & doses to discuss"
            )
            PaywallLedgerRow(
                marker: "+",
                markerColor: Editorial.accent(colorScheme),
                title: "AI chat about your results"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var unavailableCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Editorial.tagWarn(colorScheme))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Purchases aren't available in this build yet.")
                    .font(.subheadline.weight(.semibold))
                Text("This preview isn't connected to the App Store yet, so premium plans can't be shown or purchased here. Everything else in Gemocode works normally.")
                    .font(.footnote)
                    .foregroundStyle(Editorial.muted(colorScheme))
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
                        // Any purchase in flight disables every card,
                        // including the one being purchased — otherwise the
                        // purchasing product's own button stays tappable
                        // mid-purchase and a second tap can fire a second
                        // `product.purchase()` before the first resolves.
                        isDisabled: purchasingProductID != nil
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
                        .controlSize(.small)
                    Text("Restoring…")
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Restore Purchases")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(Editorial.muted(colorScheme))
        .underline()
        .disabled(isRestoring)
        .padding(.top, 2)
    }

    private var footerLinks: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    presentedLegalDocument = .termsOfService
                } label: {
                    Text("Terms of Service").underline()
                }
                Text("•")
                Button {
                    presentedLegalDocument = .privacyPolicy
                } label: {
                    Text("Privacy Policy").underline()
                }
            }
            .font(.caption2)
            .buttonStyle(.plain)
        }
        .foregroundStyle(Editorial.muted(colorScheme))
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Close")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
        }
        .padding(20)
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                Text("Premium")
                    .font(.system(size: 10, weight: .medium))
                    .kerning(1.2)
                    .textCase(.uppercase)
            }
            .foregroundStyle(Editorial.accent(colorScheme))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .overlay(
                Capsule().strokeBorder(Editorial.accent(colorScheme), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)

            (
                Text("One skipped test\n")
                    .foregroundStyle(Editorial.ink(colorScheme))
                + Text("pays for a year.")
                    .foregroundStyle(Editorial.accent(colorScheme))
            )
            .font(.system(size: 28, weight: .regular))
            .tracking(-0.5)

            Text("Scans, plain-words analysis, and your action plan — decided for you after every report.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Editorial.muted(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - Ledger row

/// One line of the "Always Free" / "Premium Adds" comparison: a colored
/// marker glyph (✓ or +) followed by the feature title. `detail`, when
/// given, isn't shown as a second line — it rides along as an
/// accessibility hint so VoiceOver users still get the fuller explanation
/// the old icon-card layout used to show everyone.
private struct PaywallLedgerRow: View {
    let marker: String
    let markerColor: Color
    let title: LocalizedStringKey
    var detail: LocalizedStringKey?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(marker)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(markerColor)
                .frame(width: 14, alignment: .leading)
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Editorial.ink(colorScheme))
            Spacer(minLength: 0)
        }
        .ledgerRow()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { Text(title) + Text(verbatim: ". ") + Text($0) } ?? Text(title))
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

    @Environment(\.colorScheme) private var colorScheme

    private var planName: String {
        if product.displayName.isEmpty {
            if isLifetime { return String(localized: "Lifetime") }
            return isYearly ? String(localized: "Yearly") : String(localized: "Monthly")
        }
        return product.displayName
    }

    private var periodSuffix: String {
        if isLifetime { return String(localized: " once") }
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day: return period.value == 1 ? String(localized: "/day") : String(localized: "/\(period.value) days")
        case .week: return period.value == 1 ? String(localized: "/week") : String(localized: "/\(period.value) weeks")
        case .month: return period.value == 1 ? String(localized: "/month") : String(localized: "/\(period.value) months")
        case .year: return period.value == 1 ? String(localized: "/year") : String(localized: "/\(period.value) years")
        @unknown default: return ""
        }
    }

    private var labelColor: Color {
        isYearly ? .white : Editorial.ink(colorScheme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text("\(planName) — \(product.displayPrice)\(periodSuffix)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if isPurchasing {
                    ProgressView()
                } else if isYearly {
                    Text("2 months free")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                } else if isLifetime {
                    Text("One-time")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Editorial.muted(colorScheme))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, isYearly ? 16 : 14)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(isYearly ? Editorial.accent(colorScheme) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .strokeBorder(isYearly ? Color.clear : Editorial.controlBorder(colorScheme), lineWidth: 1)
            )
            .shadow(
                color: isYearly ? Editorial.accent(colorScheme).opacity(0.30) : .clear,
                radius: isYearly ? 20 : 0,
                x: 0,
                y: isYearly ? 14 : 0
            )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled && !isPurchasing ? 0.5 : 1)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(planName) plan, \(product.displayPrice)\(periodSuffix)\(isYearly ? String(localized: ", best value") : "")\(isLifetime ? String(localized: ", one-time purchase") : "")"
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

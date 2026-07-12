import Foundation
import StoreKit

// MARK: - Premium entitlement (StoreKit 2)
//
// MediTrack has no backend and no accounts, so "premium" is nothing more
// than a local StoreKit entitlement: two auto-renewable subscription
// products (monthly / yearly) plus a one-time non-consumable lifetime
// unlock, any of which unlocks unlimited AI health reports.
// Every free-tier tracking feature (OCR scanning, health score,
// interactions, trends, backups) stays free forever — this store only
// gates the optional AI report count via `AIReportQuota` below.
//
// No Apple Developer account is connected in this build yet, so the
// products will not resolve from App Store Connect. `loadProducts()`
// degrades to `.unavailable` in that case (and whenever the returned
// product list is empty) rather than pretending purchases work.

/// Drives the paywall UI and the app's premium entitlement. `isPremium` is
/// derived solely from `Transaction.currentEntitlements` — there is no
/// separate "premium" flag to fall out of sync with StoreKit.
@MainActor
final class PremiumStore: ObservableObject {

    /// Shared instance. Views hold this via `@ObservedObject` rather than
    /// `@StateObject` owning a fresh instance, so the entitlement state and
    /// transaction listener are shared app-wide without needing an
    /// `environmentObject` injected at the app root.
    static let shared = PremiumStore()

    // MARK: Product identifiers

    static let monthlyProductID = "com.ogureq.meditrack.premium.monthly"
    static let yearlyProductID = "com.ogureq.meditrack.premium.yearly"
    /// One-time non-consumable unlock — same entitlement as the
    /// subscriptions, it just never renews.
    static let lifetimeProductID = "com.ogureq.meditrack.premium.lifetime"
    static let productIDs: [String] = [monthlyProductID, yearlyProductID, lifetimeProductID]

    enum LoadState: Equatable {
        case loading
        case loaded
        case unavailable
    }

    // MARK: Published state

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var isPremium = false
    @Published private(set) var isPurchasing = false
    @Published var lastErrorMessage: String?

    private var transactionListenerTask: Task<Void, Never>?

    init() {
        transactionListenerTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
        Task { [weak self] in
            await self?.refreshEntitlements()
        }
    }

    deinit {
        transactionListenerTask?.cancel()
    }

    // MARK: Loading products

    /// Fetches the two subscription products from StoreKit. In this
    /// unsigned build (no Apple Developer account connected) this either
    /// throws or returns an empty list — both cases are treated as
    /// `.unavailable` so the paywall can show an honest message instead of
    /// a broken purchase button.
    func loadProducts() async {
        loadState = .loading
        do {
            let storeProducts = try await Product.products(for: Self.productIDs)
            if storeProducts.isEmpty {
                products = []
                loadState = .unavailable
            } else {
                products = storeProducts.sorted { $0.price < $1.price }
                loadState = .loaded
            }
        } catch {
            products = []
            loadState = .unavailable
        }
    }

    // MARK: Purchase

    /// Starts a purchase for `product`. On a verified success the
    /// entitlement is refreshed and the transaction is finished; a user
    /// cancellation or a pending purchase (e.g. Ask to Buy) is not an
    /// error and simply leaves `isPremium` unchanged.
    func purchase(_ product: Product) async throws {
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await refreshEntitlements()
                await transaction.finish()
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    /// Re-syncs with the App Store and re-checks entitlements — used by the
    /// paywall's "Restore Purchases" action.
    func restorePurchases() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    // MARK: Entitlements

    /// Recomputes `isPremium` from `Transaction.currentEntitlements`,
    /// ignoring unverified transactions and anything that's been revoked.
    private func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard Self.productIDs.contains(transaction.productID) else { continue }
            if transaction.revocationDate == nil {
                active = true
            }
        }
        isPremium = active
    }

    /// Long-running listener for `Transaction.updates` (renewals, refunds,
    /// purchases completed outside the app). Started once from `init`.
    private func listenForTransactionUpdates() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            await refreshEntitlements()
            await transaction.finish()
        }
    }
}

// MARK: - AI report metering
//
// Deliberately pure and StoreKit-free so it's testable without a StoreKit
// test session: a plain UserDefaults counter plus arithmetic. `PremiumStore`
// only supplies `isPremium`; everything else here is free functions over an
// injected `UserDefaults`.

enum AIReportQuota {
    /// Free-tier lifetime cap on AI-generated reports (never resets): one
    /// taste of the AI report, then Premium. Chat and AI-assisted entry are
    /// premium-only from the start.
    static let freeLifetimeLimit = 1
    static let usedCountKey = "premium.aiReportsUsed"

    static func usedCount(defaults: UserDefaults) -> Int {
        defaults.integer(forKey: usedCountKey)
    }

    /// Reports left on the free tier. Never negative, even if `usedCount`
    /// somehow exceeds the limit.
    static func remaining(defaults: UserDefaults) -> Int {
        max(0, freeLifetimeLimit - usedCount(defaults: defaults))
    }

    /// Premium users can always generate; free users need remaining > 0.
    static func canGenerate(isPremium: Bool, defaults: UserDefaults) -> Bool {
        isPremium || remaining(defaults: defaults) > 0
    }

    /// Records one AI report generation. No cap on the counter itself —
    /// `remaining` clamps at 0 regardless of how high this climbs.
    static func recordUse(defaults: UserDefaults) {
        defaults.set(usedCount(defaults: defaults) + 1, forKey: usedCountKey)
    }
}

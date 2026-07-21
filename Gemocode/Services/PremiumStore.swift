import Foundation
import StoreKit

// MARK: - Premium entitlement (StoreKit 2)
//
// Gemocode has no backend and no accounts, so "premium" is nothing more
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
/// separate "premium" flag to fall out of sync with StoreKit. (DEBUG builds
/// only: `isPremium` also overlays a manual `debugPremiumOverride` toggle
/// for testing — see below. That path does not exist in Release.)
@MainActor
final class PremiumStore: ObservableObject {

    /// Shared instance. Views hold this via `@ObservedObject` rather than
    /// `@StateObject` owning a fresh instance, so the entitlement state and
    /// transaction listener are shared app-wide without needing an
    /// `environmentObject` injected at the app root.
    static let shared = PremiumStore()

    // MARK: Product identifiers

    static let monthlyProductID = "com.ogureq.gemocode.premium.monthly"
    static let yearlyProductID = "com.ogureq.gemocode.premium.yearly"
    /// One-time non-consumable unlock — same entitlement as the
    /// subscriptions, it just never renews.
    static let lifetimeProductID = "com.ogureq.gemocode.premium.lifetime"
    static let productIDs: [String] = [monthlyProductID, yearlyProductID, lifetimeProductID]

    enum LoadState: Equatable {
        case loading
        case loaded
        case unavailable
    }

    // MARK: Published state

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .loading
    /// Backing store for the real StoreKit entitlement. Nothing outside
    /// this file reads this directly — every call site (paywall gates,
    /// scan lock, AI features) reads `isPremium` below, which is the single
    /// source of truth.
    @Published private var isPremiumEntitlement = false
    @Published private(set) var isPurchasing = false

    /// The one property every premium gate in the app reads. Derived from
    /// the real StoreKit entitlement (`isPremiumEntitlement`) plus — in
    /// DEBUG builds only — the developer test toggle below. Every existing
    /// call site keeps reading `store.isPremium` with zero changes; only
    /// this accessor changed from a stored property to a computed one.
    ///
    /// Release-build safety: the `#if DEBUG` means the override branch,
    /// `debugPremiumOverride` itself, and its UserDefaults key do not exist
    /// in a compiled Release/TestFlight/App Store binary — not hidden
    /// behind a runtime flag, but absent as a symbol. There is no code path
    /// for App Review or a shipped build to discover or flip.
    var isPremium: Bool {
        #if DEBUG
        return isPremiumEntitlement || debugPremiumOverride
        #else
        return isPremiumEntitlement
        #endif
    }

    #if DEBUG
    /// Debug-only manual override so the owner can exercise every
    /// premium-gated path (paywall, scan lock, AI report/chat/quick-add)
    /// without completing a StoreKit sandbox purchase. Persisted directly
    /// in UserDefaults rather than as a plain `@Published` stored property,
    /// because a property wrapper can't carry a `didSet` to persist itself;
    /// `objectWillChange` is sent manually in the setter instead, so every
    /// view observing this store (e.g. Profile's toggle, or any screen
    /// reading `isPremium`) still re-renders correctly on toggle. Compiled
    /// out entirely in Release — see `isPremium` above.
    static let debugPremiumOverrideKey = "debug.premiumOverride"

    var debugPremiumOverride: Bool {
        get { UserDefaults.standard.bool(forKey: Self.debugPremiumOverrideKey) }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: Self.debugPremiumOverrideKey)
        }
    }
    #endif

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

    /// Thrown when StoreKit returns a purchase whose local JWS verification
    /// fails — premium is not granted and the transaction is deliberately
    /// left unfinished so the App Store retries delivery.
    struct UnverifiedPurchaseError: LocalizedError {
        var errorDescription: String? {
            "The App Store couldn't verify this purchase. You haven't been charged premium access — please try again, and use Restore Purchases if you were billed."
        }
    }

    /// Starts a purchase for `product`. On a verified success the
    /// entitlement is refreshed and the transaction is finished; a user
    /// cancellation or a pending purchase (e.g. Ask to Buy) is not an
    /// error and simply leaves `isPremium` unchanged. An unverified result
    /// throws so the paywall can tell the user instead of silently
    /// resetting.
    func purchase(_ product: Product) async throws {
        // Re-entrancy guard: `PaywallView` also disables every product card
        // while a purchase is in flight, but that's a UI-layer defense —
        // this is the last line of defense against two concurrent
        // `product.purchase()` calls (e.g. a second call site, or a race
        // between disabling and a tap already in flight) double-charging
        // or double-processing a transaction.
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await refreshEntitlements()
                await transaction.finish()
            case .unverified:
                throw UnverifiedPurchaseError()
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

    /// True once `refreshEntitlements()` has completed at least once —
    /// before that, `isPremium == false` may just mean "not loaded yet".
    private(set) var hasLoadedEntitlements = false

    /// Awaits the first entitlement resolution if it hasn't happened yet.
    /// Callers about to make an is-this-user-free decision (e.g. spending
    /// the free-report quota) must call this first so a paying subscriber
    /// on a cold launch isn't misclassified as free.
    func ensureEntitlementsLoaded() async {
        guard !hasLoadedEntitlements else { return }
        await refreshEntitlements()
    }

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
        isPremiumEntitlement = active
        hasLoadedEntitlements = true
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

    #if DEBUG
    /// Debug-only: clears the used-count key so the owner can re-test the
    /// one-free-report flow repeatedly in a debug build. The quota is
    /// otherwise a lifetime cap that never resets (see `freeLifetimeLimit`)
    /// — this bypass does not exist in a compiled Release build.
    static func debugResetUsedCount(defaults: UserDefaults) {
        defaults.removeObject(forKey: usedCountKey)
    }
    #endif
}

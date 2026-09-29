import Foundation
import StoreKit
import Observation

/// Real StoreKit 2 subscription handling for NomadCompass Pro. Product
/// IDs match `Configuration.storekit` (local testing) and must be created
/// to match exactly in App Store Connect before shipping.
@MainActor
@Observable
final class SubscriptionManager {
    static let shared = SubscriptionManager()

    static let monthlyID = "io.nomadterminal.pro.monthly"
    static let annualID = "io.nomadterminal.pro.annual"
    static let productIDs = [monthlyID, annualID]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoadingProducts = false
    /// Set when points were redeemed for temporary Pro (see NomadPoints'
    /// `redeem_reward` → `profiles.bonus_pro_until`). `isPro` is true while
    /// this is in the future, independent of any real StoreKit purchase.
    private(set) var bonusProUntil: Date?
    var purchaseError: String?

    private var hasRealSubscription = false

    private init() {
        // Fire-and-forget: `shared` is a singleton that lives for the app's
        // whole lifetime, so this task never needs cancelling.
        Task { [weak self] in await self?.observeTransactionUpdates() }
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshEntitlements()
            await self?.refreshBonusPro()
        }
    }

    /// Re-reads `profiles.bonus_pro_until` — call after redeeming a points
    /// reward so Pro unlocks immediately without waiting for next launch.
    func refreshBonusPro() async {
        if let summary = try? await RouteRepository.shared.fetchPointsSummary() {
            bonusProUntil = summary.bonusProUntil
        }
        recomputeIsPro()
    }

    private func recomputeIsPro() {
        let bonusActive = (bonusProUntil ?? .distantPast) > .now
        isPro = hasRealSubscription || bonusActive
    }

    /// Fetches the two subscription `Product`s from StoreKit, sorted cheapest first.
    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Couldn't load subscription options — check your connection."
        }
    }

    /// Runs the native purchase sheet for a product and updates `isPro` on success.
    func purchase(_ product: Product) async {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    RouteRepository.shared.logEvent("subscription_purchased", metadata: ["product_id": product.id])
                } else {
                    purchaseError = "Purchase couldn't be verified — try again."
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = "Purchase failed — try again."
        }
    }

    /// Re-syncs with the App Store — used by the "Restore purchases" link,
    /// required by App Store review guidelines for any subscription app.
    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = "Couldn't restore purchases — try again."
        }
    }

    /// Walks current entitlements and flips `isPro` if either subscription is active.
    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        hasRealSubscription = active
        recomputeIsPro()
    }

    private func observeTransactionUpdates() async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            await transaction.finish()
            await refreshEntitlements()
        }
    }
}

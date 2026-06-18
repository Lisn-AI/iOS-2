import Foundation
import StoreKit
import CryptoKit
import FirebaseAuth

/// StoreKit 2 owner for LisnAI subscriptions.
///
/// Single source of truth for in-app product loading, purchase, restore, and
/// renewal/refund listening. Talks to `SubscriptionService` after a successful
/// purchase so the rest of the app sees the new tier instantly.
@MainActor
final class PurchaseService: ObservableObject {
    static let shared = PurchaseService()

    // MARK: - Product IDs (must match App Store Connect → Monetization → Subscriptions)

    static let productIds: [String] = [
        "com.lisnai.app.pro.monthly",
        "com.lisnai.app.pro.annual",
        "com.lisnai.app.max.monthly",
        "com.lisnai.app.max.yearly",
    ]

    // MARK: - Published State

    /// Products loaded from the App Store. Empty until `loadProducts()` succeeds.
    @Published private(set) var products: [Product] = []
    /// The product the user is currently purchasing, if any.
    @Published private(set) var purchaseInProgressId: String?
    @Published private(set) var isLoadingProducts = false
    /// True when the user has at least one entitlement that's still active.
    @Published private(set) var hasActiveEntitlement = false
    /// Last verified product ID with an active entitlement (for UI badges).
    @Published private(set) var activeProductId: String?

    // MARK: - Private State

    private var updatesTask: Task<Void, Never>?

    enum PurchaseError: LocalizedError {
        case productNotFound
        case verificationFailed
        case userCancelled
        case pending
        case unknown(String?)

        var errorDescription: String? {
            switch self {
            case .productNotFound: return "This subscription isn't available yet. Please try again later."
            case .verificationFailed: return "Apple couldn't verify the purchase. Please try again."
            case .userCancelled: return "Purchase cancelled."
            case .pending: return "Your purchase is pending approval (e.g. parental approval)."
            case .unknown(let msg): return msg ?? "Something went wrong with the purchase."
            }
        }
    }

    private init() {}

    // MARK: - Lifecycle

    /// Start listening for transaction updates. Call once from AppDelegate.
    func configure() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update, source: "Transaction.updates")
            }
        }
        Task { await refreshEntitlements() }
    }

    // MARK: - Products

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: Self.productIds)
            // Sort: Pro before Max, monthly before yearly (matches paywall order)
            products = fetched.sorted { lhs, rhs in
                let order: [String: Int] = [
                    "com.lisnai.app.pro.monthly": 0,
                    "com.lisnai.app.pro.annual": 1,
                    "com.lisnai.app.max.monthly": 2,
                    "com.lisnai.app.max.yearly": 3,
                ]
                return (order[lhs.id] ?? 99) < (order[rhs.id] ?? 99)
            }
        } catch {
            print("[PurchaseService] Failed to load products: \(error.localizedDescription)")
            products = []
        }
    }

    func product(for id: String) -> Product? {
        products.first(where: { $0.id == id })
    }

    // MARK: - Purchase

    /// Initiate a purchase. Throws on failure or cancellation. Returns silently
    /// on success — observers should listen to `hasActiveEntitlement`.
    func purchase(productId: String) async throws {
        guard let product = product(for: productId) else {
            throw PurchaseError.productNotFound
        }

        purchaseInProgressId = productId
        defer { purchaseInProgressId = nil }

        var options: Set<Product.PurchaseOption> = []
        if let token = appAccountToken() {
            options.insert(.appAccountToken(token))
        }

        let result = try await product.purchase(options: options)

        switch result {
        case .success(let verification):
            await handle(transactionResult: verification, source: "purchase")
        case .userCancelled:
            throw PurchaseError.userCancelled
        case .pending:
            throw PurchaseError.pending
        @unknown default:
            throw PurchaseError.unknown(nil)
        }
    }

    // MARK: - Restore

    func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
        AnalyticsService.shared.track(.subscriptionRestored)
    }

    // MARK: - Product → Tier mapping

    static let productTierMap: [String: String] = [
        "com.lisnai.app.pro.monthly": "pro",
        "com.lisnai.app.pro.annual": "pro",
        "com.lisnai.app.max.monthly": "max",
        "com.lisnai.app.max.yearly": "max",
    ]

    /// Derived tier from local StoreKit entitlements — NOT from backend.
    /// "free" if no active entitlement.
    var localTier: String {
        guard let id = activeProductId else { return "free" }
        return Self.productTierMap[id] ?? "free"
    }

    // MARK: - Entitlements

    /// Re-scan `Transaction.currentEntitlements` and update local state.
    /// Picks the HIGHEST active entitlement (max > pro).
    func refreshEntitlements() async {
        var bestProduct: String?
        var bestTierRank = 0

        let tierRank: [String: Int] = ["pro": 1, "max": 2]

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            if let exp = transaction.expirationDate, exp < Date() { continue }
            guard Self.productIds.contains(transaction.productID) else { continue }

            let tier = Self.productTierMap[transaction.productID] ?? "free"
            let rank = tierRank[tier] ?? 0
            if rank > bestTierRank {
                bestTierRank = rank
                bestProduct = transaction.productID
            }
        }

        let wasActive = hasActiveEntitlement
        let previousProduct = activeProductId

        hasActiveEntitlement = bestProduct != nil
        activeProductId = bestProduct

        // Detect state changes and sync backend
        if previousProduct != bestProduct {
            let newTier = bestProduct.flatMap { Self.productTierMap[$0] } ?? "free"
            print("[PurchaseService] Entitlement changed: \(previousProduct ?? "none") → \(bestProduct ?? "none") (tier: \(newTier))")

            // If user lost entitlement (cancel/expire), tell backend
            if wasActive && !hasActiveEntitlement {
                print("[PurchaseService] Entitlement lost — syncing backend to free tier")
            }

            await SubscriptionService.shared.syncUsageFromBackend()
        }
    }

    /// Called when the app comes to foreground. Re-checks StoreKit entitlements
    /// (catches cancellations, expirations, family sharing changes) and syncs
    /// the backend so the UI always reflects reality.
    func syncOnForeground() async {
        await refreshEntitlements()
        await SubscriptionService.shared.syncUsageFromBackend()
    }

    // MARK: - Transaction Handling

    private func handle(
        transactionResult: VerificationResult<Transaction>,
        source: String
    ) async {
        switch transactionResult {
        case .verified(let transaction):
            print("[PurchaseService] Verified \(source) for product \(transaction.productID) (txId \(transaction.id))")

            // Tell backend to upgrade the tier immediately — don't wait for the
            // server-to-server notification, that's just for renewals/cancels.
            // The JWS lives on VerificationResult, not Transaction.
            do {
                let txJWS = transactionResult.jwsRepresentation
                try await APIService.shared.verifyAppStoreTransaction(jws: txJWS)
            } catch {
                print("[PurchaseService] Backend verify failed: \(error.localizedDescription) — will retry on next foreground sync")
            }

            await refreshEntitlements()
            await SubscriptionService.shared.syncUsageFromBackend()

            AnalyticsService.shared.track(.subscriptionPurchased, properties: [
                "product_id": transaction.productID,
                "source": source
            ])
            NotificationCenter.default.post(name: .subscriptionPurchased, object: nil)

            await transaction.finish()

        case .unverified(_, let error):
            print("[PurchaseService] Unverified \(source) transaction: \(error.localizedDescription)")
            AnalyticsService.shared.track(.purchaseFailed, properties: [
                "reason": "verification_failed",
                "source": source
            ])
        }
    }

    // MARK: - App Account Token (Firebase UID → deterministic UUID)

    /// Generate a stable UUID derived from the user's Firebase UID. The same
    /// Firebase UID always produces the same UUID, so the backend can map
    /// Apple's `appAccountToken` field back to a Firebase user.
    ///
    /// Returns `nil` if no user is signed in.
    func appAccountToken() -> UUID? {
        guard let firebaseUID = Auth.auth().currentUser?.uid else { return nil }
        return Self.deterministicUUID(from: firebaseUID)
    }

    static func deterministicUUID(from input: String) -> UUID {
        let hash = SHA256.hash(data: Data(input.utf8))
        var bytes = Array(hash.prefix(16))
        // Force RFC 4122 version 4 / variant 1 bits
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

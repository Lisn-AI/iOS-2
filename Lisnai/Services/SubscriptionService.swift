import Foundation
// RevenueCat is imported but all calls are guarded behind isRevenueCatConfigured
import RevenueCat

/// Manages subscriptions via Razorpay backend sync (primary) and RevenueCat SDK (when configured)
@MainActor
class SubscriptionService: NSObject, ObservableObject {
    static let shared = SubscriptionService()

    // MARK: - Published State

    @Published var tier: SubscriptionTier = .free
    @Published var status: SubscriptionStatus = .expired
    @Published var limits: TierLimits?
    @Published var usage: UsageData?
    @Published var periodEnd: Date?
    @Published var trialEndsAt: Date?
    @Published var offerings: Offerings?
    @Published var isPurchasing = false

    // MARK: - RevenueCat Configuration Guard

    /// Whether RevenueCat SDK is configured and ready to use.
    /// Set to `true` when Apple IAP is ready. While `false`, all RevenueCat
    /// calls are skipped and backend sync is the sole source of truth.
    private var isRevenueCatConfigured: Bool {
        return false // Set to true when Apple IAP is ready
    }

    // MARK: - Computed

    var isTrialActive: Bool {
        status == .trial
    }

    var trialDaysRemaining: Int {
        guard let trialEnd = trialEndsAt else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
        return max(0, days)
    }

    var isPro: Bool {
        tier == .pro || tier == .max
    }

    var isMax: Bool {
        tier == .max
    }

    var hasCloudBackup: Bool {
        limits?.cloudBackup ?? false
    }

    var shouldShowUpgrade: Bool {
        tier == .free && status != .trial
    }

    // MARK: - Configuration

    /// Call from AppDelegate.didFinishLaunching
    func configure() {
        guard isRevenueCatConfigured else {
            print("[SubscriptionService] RevenueCat disabled — using Razorpay backend sync")
            return
        }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: "appl_YOUR_REVENUECAT_API_KEY")
        Purchases.shared.delegate = self
    }

    // MARK: - User Linking

    /// Link RevenueCat user to Firebase UID after auth
    func loginUser(firebaseUID: String) async {
        guard isRevenueCatConfigured else { return }
        do {
            let (customerInfo, _) = try await Purchases.shared.logIn(firebaseUID)
            updateFromCustomerInfo(customerInfo)
        } catch {
            print("[SubscriptionService] Login error: \(error)")
        }
    }

    /// Unlink on sign out
    func logoutUser() async {
        guard isRevenueCatConfigured else {
            tier = .free
            status = .expired
            limits = nil
            usage = nil
            return
        }
        do {
            _ = try await Purchases.shared.logOut()
            tier = .free
            status = .expired
            limits = nil
            usage = nil
        } catch {
            print("[SubscriptionService] Logout error: \(error)")
        }
    }

    // MARK: - Offerings

    func loadOfferings() async {
        guard isRevenueCatConfigured else { return }
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            print("[SubscriptionService] Failed to load offerings: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(package: Package) async throws {
        guard isRevenueCatConfigured else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await Purchases.shared.purchase(package: package)

        if !result.userCancelled {
            updateFromCustomerInfo(result.customerInfo)
        }
    }

    func restorePurchases() async throws {
        guard isRevenueCatConfigured else { return }
        let customerInfo = try await Purchases.shared.restorePurchases()
        updateFromCustomerInfo(customerInfo)
    }

    // MARK: - Backend Sync

    /// Sync subscription status and usage from backend
    func syncUsageFromBackend() async {
        let previousStatus = status
        let previousTier = tier
        do {
            let response = try await APIService.shared.getSubscriptionStatus()
            tier = response.tier
            status = response.status
            limits = response.limits
            usage = response.usage

            if let periodEndStr = response.periodEnd {
                periodEnd = ISO8601DateFormatter().date(from: periodEndStr)
            }
            if let trialEndStr = response.trialEndsAt {
                trialEndsAt = ISO8601DateFormatter().date(from: trialEndStr)
            }

            // Fire Mixpanel state events on transitions
            if previousStatus != .trial && response.status == .trial {
                AnalyticsService.shared.track(.trialStarted, properties: [
                    "tier": tier.rawValue
                ])
            }
            if previousTier != response.tier {
                AnalyticsService.shared.setUserProperty("current_tier", value: tier.rawValue)
                AnalyticsService.shared.setSuperProperty("current_tier", value: tier.rawValue)
            }
            AnalyticsService.shared.setUserProperty("subscription_status", value: status.rawValue)
        } catch {
            print("[SubscriptionService] Backend sync error: \(error)")
        }
    }

    // MARK: - Post-Payment Polling

    /// Poll backend until subscription tier upgrades (or timeout).
    /// Used after Razorpay checkout dismisses to wait for webhook processing.
    /// - Parameters:
    ///   - maxAttempts: Number of poll attempts (default 10 = ~20 seconds)
    /// - Returns: `true` if tier upgraded to pro/max within the timeout
    func pollForSubscriptionUpdate(maxAttempts: Int = 10) async -> Bool {
        let previousTier = tier
        for attempt in 1...maxAttempts {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await syncUsageFromBackend()
            if tier == .pro || tier == .max, tier != previousTier {
                print("[SubscriptionService] Subscription activated after \(attempt) poll(s)")
                return true
            }
        }
        print("[SubscriptionService] Polling timed out after \(maxAttempts) attempts")
        return false
    }

    // MARK: - Local Limit Checks

    func canTranscribe() -> LimitCheckResult {
        checkLimit(
            used: Int(usage?.transcriptionMinutes ?? 0),
            limit: Int(limits?.transcriptionMinutes ?? 30),
            resource: "transcription"
        )
    }

    func canChat() -> LimitCheckResult {
        checkLimit(
            used: usage?.chatMessages ?? 0,
            limit: limits?.chatMessages ?? 20,
            resource: "chat"
        )
    }

    func canSearch() -> LimitCheckResult {
        checkLimit(
            used: usage?.memorySearches ?? 0,
            limit: limits?.memorySearches ?? 5,
            resource: "search"
        )
    }

    func canUseAction() -> LimitCheckResult {
        checkLimit(
            used: usage?.actionsUsed ?? 0,
            limit: limits?.actionsUsed ?? 3,
            resource: "action"
        )
    }

    // MARK: - Helpers

    private func checkLimit(used: Int, limit: Int, resource: String = "unknown") -> LimitCheckResult {
        // -1 means unlimited
        if limit == -1 {
            return .allowed(used: used, limit: -1, remaining: -1)
        }
        let remaining = max(0, limit - used)
        if remaining == 0 {
            AnalyticsService.shared.track(.limitHit, properties: [
                "resource": resource,
                "used": used,
                "limit": limit,
                "current_tier": tier.rawValue
            ])
        }
        if used < limit {
            return .allowed(used: used, limit: limit, remaining: remaining)
        }
        return .denied(used: used, limit: limit)
    }

    private func updateFromCustomerInfo(_ customerInfo: CustomerInfo) {
        if customerInfo.entitlements["max"]?.isActive == true {
            tier = .max
        } else if customerInfo.entitlements["pro"]?.isActive == true {
            tier = .pro
        } else {
            tier = .free
        }
    }
}

// MARK: - PurchasesDelegate

extension SubscriptionService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            updateFromCustomerInfo(customerInfo)
            // Re-sync from backend to get latest usage
            await syncUsageFromBackend()
        }
    }
}

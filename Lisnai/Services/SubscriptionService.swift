import Foundation

/// Manages subscriptions via backend sync. StoreKit 2 will become primary once IAP wires up.
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
    @Published var isPurchasing = false
    /// Latest free-window descriptor synced from the backend. When the user
    /// is on the free tier and `isWithinWindow == false`, all gated features
    /// (chat, search, action creation) should be paywalled.
    @Published var freeWindow: FreeWindowStatus?

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

    /// True when user has cancelled but still has access until periodEnd.
    var isCancelledButActive: Bool {
        status == .cancelled && tier != .free
    }

    /// Formatted date when the subscription will expire after cancellation.
    var cancellationExpiryDisplay: String? {
        guard isCancelledButActive, let end = periodEnd else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: end)
    }

    /// True when user can upgrade from their current tier (free or pro → show upgrade).
    var shouldShowUpgrade: Bool {
        tier == .free && status != .trial
    }

    // MARK: - Configuration

    func configure() {
        print("[SubscriptionService] Using StoreKit 2 via PurchaseService")
    }

    // MARK: - User Linking

    func loginUser(firebaseUID: String) async {
        // Backend sync handles tier — no SDK login needed
    }

    func logoutUser() async {
        tier = .free
        status = .expired
        limits = nil
        usage = nil
    }

    // MARK: - Local Tier Override (from StoreKit)

    /// Apply the tier from local StoreKit entitlements immediately — don't wait
    /// for the backend. This ensures the UI reflects reality even when the
    /// backend is unreachable (network timeout, cold start, etc.).
    ///
    /// The backend sync still runs in the background to update usage/limits,
    /// but the TIER itself is driven by what Apple's StoreKit reports locally.
    func applyLocalEntitlement(tier localTier: String, productId: String?) {
        let mappedTier: SubscriptionTier
        switch localTier {
        case "pro": mappedTier = .pro
        case "max": mappedTier = .max
        default: mappedTier = .free
        }

        // Only upgrade — never downgrade from local signal alone.
        // Downgrades should come from the backend (which has the authoritative
        // cancel/expire state from Apple's webhook).
        let tierRank: [SubscriptionTier: Int] = [.free: 0, .pro: 1, .max: 2]
        guard (tierRank[mappedTier] ?? 0) >= (tierRank[tier] ?? 0) else { return }

        if tier != mappedTier {
            print("[SubscriptionService] Local entitlement override: \(tier.rawValue) → \(mappedTier.rawValue)")
            tier = mappedTier
            status = .active
            AnalyticsService.shared.setUserProperty("current_tier", value: tier.rawValue)
            AnalyticsService.shared.setSuperProperty("current_tier", value: tier.rawValue)
        }
    }

    // MARK: - Backend Sync

    /// Sync subscription status and usage from backend.
    /// The backend is authoritative for usage counters and limits, but the
    /// tier may have already been set by `applyLocalEntitlement` — so we take
    /// the HIGHER of backend tier vs current (locally-set) tier.
    func syncUsageFromBackend() async {
        let previousStatus = status
        let previousTier = tier
        do {
            let response = try await APIService.shared.getSubscriptionStatus()

            // Take the higher tier between backend and local StoreKit
            let tierRank: [SubscriptionTier: Int] = [.free: 0, .pro: 1, .max: 2]
            let backendRank = tierRank[response.tier] ?? 0
            let localRank = tierRank[tier] ?? 0

            if backendRank >= localRank {
                tier = response.tier
                status = response.status
            }
            // If local is higher (e.g. just purchased but backend hasn't processed),
            // keep the local tier but still update usage/limits from backend.

            limits = response.limits
            usage = response.usage
            freeWindow = response.freeWindow

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
            if previousTier != tier {
                AnalyticsService.shared.setUserProperty("current_tier", value: tier.rawValue)
                AnalyticsService.shared.setSuperProperty("current_tier", value: tier.rawValue)
            }
            AnalyticsService.shared.setUserProperty("subscription_status", value: status.rawValue)
        } catch {
            print("[SubscriptionService] Backend sync error: \(error)")
        }
    }

    // MARK: - Local Limit Checks

    func canTranscribe() -> LimitCheckResult {
        // Transcription gating is owned by RecordingManager — do not enforce
        // the free-window paywall here so the recording flow continues to work
        // as it did before. RecordingManager has its own end-of-session policy.
        checkLimit(
            used: Int(usage?.transcriptionMinutes ?? 0),
            limit: Int(limits?.transcriptionMinutes ?? 30),
            resource: "transcription",
            enforceFreeWindow: false
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

    // MARK: - Paywall gating helpers

    /// Outcome bucket for view-layer paywall decisions.
    enum PaywallGate: Equatable {
        case allowed
        case denied(used: Int, limit: Int)
        case freeWindowExpired(daysRemaining: Int)
    }

    /// Check whether the user can create/confirm an action right now and
    /// emit the `paywall_shown` Mixpanel event with the correct trigger
    /// source if they can't. Returns the gate result so the view can react.
    ///
    /// Pass `triggerPrefix` like `"action"`, `"chat"`, `"search"` — the
    /// Mixpanel `trigger_source` becomes `<prefix>_limit` or
    /// `<prefix>_free_window_expired`.
    func gateAction(triggerPrefix: String = "action") -> PaywallGate {
        switch canUseAction() {
        case .allowed:
            return .allowed
        case .denied(let used, let limit):
            AnalyticsService.shared.track(.paywallShown, properties: [
                "trigger_source": "\(triggerPrefix)_limit"
            ])
            return .denied(used: used, limit: limit)
        case .freeWindowExpired(let days):
            AnalyticsService.shared.track(.paywallShown, properties: [
                "trigger_source": "\(triggerPrefix)_free_window_expired",
                "days_remaining": days
            ])
            return .freeWindowExpired(daysRemaining: days)
        }
    }

    // MARK: - Helpers

    /// True when the user is on the free tier and the 10-day free window
    /// has lapsed. Paid tiers always pass this check.
    private var isFreeWindowExpired: Bool {
        guard tier == .free else { return false }
        if let window = freeWindow {
            return !window.isWithinWindow
        }
        // No freeWindow payload from backend — fall back to the legacy
        // `status == .expired` signal which the backend used to surface
        // the same condition.
        return status == .expired
    }

    private func checkLimit(
        used: Int,
        limit: Int,
        resource: String = "unknown",
        enforceFreeWindow: Bool = true
    ) -> LimitCheckResult {
        // Free-window hard block takes priority over per-resource caps —
        // the user can't unlock more by waiting for the daily reset, only
        // by subscribing.
        if enforceFreeWindow && isFreeWindowExpired {
            let days = freeWindow?.daysRemaining ?? -1
            AnalyticsService.shared.track(.limitHit, properties: [
                "resource": resource,
                "reason": "free_window_expired",
                "days_remaining": days,
                "current_tier": tier.rawValue
            ])
            return .freeWindowExpired(daysRemaining: days)
        }
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

}

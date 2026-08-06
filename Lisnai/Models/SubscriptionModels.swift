import Foundation

// MARK: - Subscription Tier

enum SubscriptionTier: String, Codable, CaseIterable {
    case free
    case pro
    case max

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max: return "Max"
        }
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus: String, Codable {
    case trial
    case active
    case expired
    case cancelled
    case graceperiod = "grace_period"
}

// MARK: - API Response Types

struct SubscriptionStatusResponse: Codable {
    let tier: SubscriptionTier
    let status: SubscriptionStatus
    let limits: TierLimits
    let usage: UsageData
    let periodEnd: String?
    let trialEndsAt: String?
    let currentPeriodEnd: String?
    /// Backend free-window descriptor — present when user is on free tier.
    /// `isWithinWindow: false` means the 10-day free period has lapsed and
    /// all gated features should hard-block until the user subscribes.
    let freeWindow: FreeWindowStatus?
}

/// Free-window descriptor returned by the backend's subscription endpoint.
/// Used to enforce the "first 10 days are free, then paywall everything" rule
/// on the client without needing a round-trip per call.
struct FreeWindowStatus: Codable {
    let isWithinWindow: Bool
    let daysRemaining: Int
    let expiresAt: String?
}

struct TierLimits: Codable {
    let transcriptionMinutes: Double
    let chatMessages: Int
    let memorySearches: Int
    let actionsUsed: Int
    let cloudBackup: Bool
}

struct UsageData: Codable {
    let transcriptionMinutes: Double
    let chatMessages: Int
    let memorySearches: Int
    let actionsUsed: Int
}

// MARK: - Limit Check

enum LimitCheckResult {
    case allowed(used: Int, limit: Int, remaining: Int)
    case denied(used: Int, limit: Int)
    /// User's 10-day free window has lapsed — hard block until they subscribe.
    /// `daysRemaining` will typically be 0 or negative; -1 indicates unknown.
    case freeWindowExpired(daysRemaining: Int)

    var isAllowed: Bool {
        if case .allowed = self { return true }
        return false
    }

    /// True when the user has hit a paywall (either a daily/monthly cap
    /// or the 10-day free window has expired). UI surfaces use this to
    /// decide whether to short-circuit and present a paywall.
    var isBlocked: Bool {
        switch self {
        case .allowed: return false
        case .denied, .freeWindowExpired: return true
        }
    }

    var used: Int {
        switch self {
        case .allowed(let used, _, _): return used
        case .denied(let used, _): return used
        case .freeWindowExpired: return 0
        }
    }

    var limit: Int {
        switch self {
        case .allowed(_, let limit, _): return limit
        case .denied(_, let limit): return limit
        case .freeWindowExpired: return 0
        }
    }
}

// MARK: - Limit Exceeded Error Response

struct LimitExceededResponse: Codable {
    let error: String
    let resource: String
    let used: Int
    let limit: Int
    let remaining: Int
    let upgradeUrl: String?
    /// Days remaining in the free window. -1 if not applicable (e.g. user
    /// is on paid tier and hit a paid-tier cap instead of the free window).
    let freeWindowDaysRemaining: Int?
}

// MARK: - App Store Transaction Verification

/// Backend response after verifying an App Store transaction JWS.
struct AppStoreVerifyResponse: Codable {
    let success: Bool
    let tier: SubscriptionTier?
    let status: SubscriptionStatus?
    let productId: String?
    let currentPeriodEnd: String?
}


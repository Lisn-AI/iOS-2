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

    var isAllowed: Bool {
        switch self {
        case .allowed: return true
        case .denied: return false
        }
    }

    var used: Int {
        switch self {
        case .allowed(let used, _, _): return used
        case .denied(let used, _): return used
        }
    }

    var limit: Int {
        switch self {
        case .allowed(_, let limit, _): return limit
        case .denied(_, let limit): return limit
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
    let upgradeUrl: String
}

// MARK: - Razorpay Subscription Creation

struct CreateSubscriptionRequest: Codable {
    let planId: String
}

struct CreateSubscriptionResponse: Codable {
    let subscriptionId: String
    let shortUrl: String
    let keyId: String
}

import Foundation

/// Reason returned from the backend's recording-permission check.
/// Mirrors `RecordingReason` in backend/src/services/subscription.ts.
enum RecordingPermissionReason: String, Codable {
    case allowed
    case allowedWithOverageWarning = "allowed_with_overage_warning"
    case allowedInOverage = "allowed_in_overage"
    case deniedOverageUsed = "denied_overage_used"
    case deniedFreeWindowExpired = "denied_free_window_expired"
    case subscribedUnlimited = "subscribed_unlimited"
}

/// Rich permission state for the record button. The backend tells us:
///  - whether to allow recording at all
///  - how much daily budget is left
///  - whether the one-time grace overage is still available today
///  - what minute mark to hard-stop the recording at
///  - how many free-window days remain (-1 if N/A)
struct RecordingPermissionResponse: Codable {
    let allowed: Bool
    let reason: RecordingPermissionReason
    let minutesUsedToday: Double
    let dailyLimitMinutes: Double
    let minutesRemainingInBudget: Double
    let overageAvailable: Bool
    let overageMaxMinutes: Double
    let hardStopAtMinutes: Double          // -1 = no hard stop
    let freeWindowDaysRemaining: Int        // -1 = subscribed (N/A)

    /// Convenience: should the iOS UI present the paywall instead of starting?
    var requiresPaywall: Bool {
        reason == .deniedFreeWindowExpired
    }

    /// Convenience: should the iOS UI show "limit reached" inline instead of paywall?
    var dailyLimitReached: Bool {
        reason == .deniedOverageUsed
    }

    /// Convenience: is the user starting in overage mode (will auto-stop soon)?
    var startsInOverage: Bool {
        reason == .allowedInOverage
    }
}

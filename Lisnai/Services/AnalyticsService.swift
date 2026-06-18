import Foundation
import Mixpanel

/// Single source of truth for product analytics (Mixpanel).
///
/// Owns:
/// - Mixpanel SDK lifecycle (init/identify/reset)
/// - Typed event taxonomy (see DESIGN.md Part 6b)
/// - User property setters (survey answers, subscription state)
///
/// NOT used for:
/// - Server-side observability (Render logs / Langfuse handle that)
/// - Crash reporting (Firebase Crashlytics if/when added)
@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()
    private var isConfigured = false

    private init() {}

    // MARK: - Lifecycle

    /// Call once at app launch (LisnaiApp init).
    /// Reads MixpanelToken from Info.plist. If missing or placeholder, becomes a no-op.
    func configure() {
        guard let token = Bundle.main.object(forInfoDictionaryKey: "MixpanelToken") as? String,
              !token.isEmpty,
              !token.contains("$(") else {
            print("[Analytics] Mixpanel token not found in Info.plist — analytics disabled")
            return
        }
        let options = MixpanelOptions(token: token, trackAutomaticEvents: false)
        Mixpanel.initialize(options: options)
        isConfigured = true
        print("[Analytics] Mixpanel configured")
    }

    /// Bind events to a specific user. Call after Firebase auth completes.
    func identify(userId: String, email: String?, name: String?) {
        guard isConfigured else { return }
        Mixpanel.mainInstance().identify(distinctId: userId)
        var profileProps: Properties = [:]
        if let email { profileProps["$email"] = email }
        if let name { profileProps["$name"] = name }
        profileProps["last_active_date"] = Date()
        if !profileProps.isEmpty {
            Mixpanel.mainInstance().people.set(properties: profileProps)
        }
    }

    /// Clear the identified user. Call from logout flow.
    func reset() {
        guard isConfigured else { return }
        Mixpanel.mainInstance().reset()
    }

    // MARK: - Event tracking

    func track(_ event: Event, properties: [String: MixpanelType]? = nil) {
        guard isConfigured else { return }
        Mixpanel.mainInstance().track(event: event.rawValue, properties: properties)
    }

    // MARK: - User properties (persistent attributes)

    /// Set a single user property — used for things like subscription tier, signup source, etc.
    func setUserProperty(_ key: String, value: MixpanelType) {
        guard isConfigured else { return }
        Mixpanel.mainInstance().people.set(properties: [key: value])
    }

    func setUserProperties(_ properties: [String: MixpanelType]) {
        guard isConfigured else { return }
        Mixpanel.mainInstance().people.set(properties: properties)
    }

    /// Increment a numeric user property (e.g. recordings_count_lifetime).
    func incrementUserProperty(_ key: String, by amount: Double = 1) {
        guard isConfigured else { return }
        Mixpanel.mainInstance().people.increment(property: key, by: amount)
    }

    // MARK: - Super properties (attached to every subsequent event)

    func setSuperProperty(_ key: String, value: MixpanelType) {
        guard isConfigured else { return }
        Mixpanel.mainInstance().registerSuperProperties([key: value])
    }
}

// MARK: - Event taxonomy
//
// Adding a new event? Update DESIGN.md Part 6b first.
// Naming convention: noun_verb_pasttense (e.g. recording_started).

extension AnalyticsService {
    enum Event: String {
        // Acquisition / Onboarding
        case appOpened = "app_opened"
        case onboardingStarted = "onboarding_started"
        case onboardingStepCompleted = "onboarding_step_completed"
        case onboardingCompleted = "onboarding_completed"
        case surveySubmitted = "survey_submitted"

        // Activation
        case recordingStarted = "recording_started"
        case recordingCompleted = "recording_completed"
        case recordingEnteredOverage = "recording_entered_overage"
        case recordingHardStopped = "recording_hard_stopped"

        // Engagement
        case insightViewed = "insight_viewed"
        case memorySearched = "memory_searched"
        case chatMessageSent = "chat_message_sent"
        case settingsOpened = "settings_opened"

        // Monetization
        case paywallShown = "paywall_shown"
        case subscriptionPurchased = "subscription_purchased"
        case subscriptionRestored = "subscription_restored"
        case purchaseFailed = "purchase_failed"
        case trialStarted = "trial_started"
        case limitHit = "limit_hit"
    }
}

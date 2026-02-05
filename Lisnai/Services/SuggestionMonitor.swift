import Foundation
import UserNotifications
import ActivityKit
import UIKit

/// Monitors for new suggestions and handles notifications + Live Activities
/// - Checks for suggestions every 5 minutes when app is in foreground
/// - Sends local notifications for new suggestions
/// - Shows Live Activity 2 minutes after notification if app is still active
@MainActor
class SuggestionMonitor: ObservableObject {
    static let shared = SuggestionMonitor()

    // MARK: - Configuration

    /// Interval between suggestion checks (5 minutes)
    private let checkInterval: TimeInterval = 5 * 60

    /// Delay before showing Live Activity after notification (2 minutes)
    private let liveActivityDelay: TimeInterval = 2 * 60

    // MARK: - State

    @Published var isMonitoring = false
    @Published var lastCheckTime: Date?
    @Published var pendingSuggestions: [ProactiveSuggestion] = []
    @Published var currentLiveActivity: Activity<TaskActivityAttributes>?

    /// IDs of suggestions that have already been notified
    private var notifiedSuggestionIds: Set<String> = []

    /// Timer for periodic checks
    private var checkTimer: Timer?

    /// Timer for Live Activity display
    private var liveActivityTimer: Timer?

    /// Suggestion waiting for Live Activity display
    private var pendingLiveActivitySuggestion: ProactiveSuggestion?

    private let api = APIService.shared
    private let notificationService = NotificationService.shared

    // MARK: - Lifecycle

    private init() {
        // Load notified IDs from UserDefaults
        if let savedIds = UserDefaults.standard.stringArray(forKey: "notifiedSuggestionIds") {
            notifiedSuggestionIds = Set(savedIds)
        }

        // Observe app state changes
        setupAppStateObservers()
    }

    // MARK: - App State Observers

    private func setupAppStateObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        print("[SuggestionMonitor] App became active, starting monitor")
        startMonitoring()
    }

    @objc private func appWillResignActive() {
        print("[SuggestionMonitor] App will resign active")
        // Keep monitoring but be aware we might get suspended
    }

    @objc private func appDidEnterBackground() {
        print("[SuggestionMonitor] App entered background, stopping timer")
        stopMonitoring()
    }

    // MARK: - Monitoring Control

    /// Start monitoring for suggestions
    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        print("[SuggestionMonitor] Starting suggestion monitoring (interval: \(checkInterval)s)")

        // Check immediately
        Task {
            await checkForNewSuggestions()
        }

        // Schedule periodic checks
        checkTimer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkForNewSuggestions()
            }
        }
    }

    /// Stop monitoring
    func stopMonitoring() {
        isMonitoring = false
        checkTimer?.invalidate()
        checkTimer = nil
        liveActivityTimer?.invalidate()
        liveActivityTimer = nil
        print("[SuggestionMonitor] Monitoring stopped")
    }

    // MARK: - Suggestion Checking

    /// Check for new suggestions from the API
    func checkForNewSuggestions() async {
        print("[SuggestionMonitor] Checking for new suggestions...")
        lastCheckTime = Date()

        do {
            let response = try await api.getSuggestions(status: "pending")
            let suggestions = response.suggestions

            print("[SuggestionMonitor] Found \(suggestions.count) pending suggestions")

            // Filter to only new suggestions
            let newSuggestions = suggestions.filter { !notifiedSuggestionIds.contains($0.id) }

            if !newSuggestions.isEmpty {
                print("[SuggestionMonitor] \(newSuggestions.count) new suggestions to notify")
                pendingSuggestions = suggestions

                // Notify for each new suggestion
                for suggestion in newSuggestions {
                    await notifySuggestion(suggestion)
                }
            } else {
                print("[SuggestionMonitor] No new suggestions")
            }

        } catch {
            print("[SuggestionMonitor] Error checking suggestions: \(error)")
        }
    }

    // MARK: - Notifications

    /// Send a local notification for a suggestion
    private func notifySuggestion(_ suggestion: ProactiveSuggestion) async {
        // Mark as notified
        notifiedSuggestionIds.insert(suggestion.id)
        saveNotifiedIds()

        // Determine category based on type
        let category = categoryForSuggestionType(suggestion.type)

        // Build notification content
        let userInfo: [String: Any] = [
            "suggestionId": suggestion.id,
            "type": suggestion.type,
            "confidence": suggestion.confidence
        ]

        do {
            try await notificationService.scheduleLocalNotification(
                title: suggestion.title,
                body: suggestion.body,
                category: category,
                userInfo: userInfo
            )

            print("[SuggestionMonitor] Notification sent for suggestion: \(suggestion.id)")

            // Schedule Live Activity after delay
            scheduleLiveActivity(for: suggestion)

        } catch {
            print("[SuggestionMonitor] Failed to send notification: \(error)")
        }
    }

    /// Get notification category for suggestion type
    private func categoryForSuggestionType(_ type: String) -> NotificationService.Category {
        switch type {
        case "call_reminder":
            return .suggestionCall
        case "follow_up":
            return .suggestionFollowup
        case "task_reminder":
            return .suggestionTask
        case "pattern_insight":
            return .suggestionInsight
        case "connection_prompt":
            return .suggestionConnection
        case "event_reminder":
            return .suggestionEvent
        default:
            return .suggestion
        }
    }

    // MARK: - Live Activity

    /// Schedule Live Activity to appear after delay
    private func scheduleLiveActivity(for suggestion: ProactiveSuggestion) {
        print("[SuggestionMonitor] Scheduling Live Activity in \(liveActivityDelay)s for: \(suggestion.title)")

        pendingLiveActivitySuggestion = suggestion

        liveActivityTimer?.invalidate()
        liveActivityTimer = Timer.scheduledTimer(withTimeInterval: liveActivityDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                // Only show if app is still in foreground
                if UIApplication.shared.applicationState == .active {
                    await self.showLiveActivity(for: suggestion)
                } else {
                    print("[SuggestionMonitor] App not active, skipping Live Activity")
                }
            }
        }
    }

    /// Show Live Activity for a suggestion
    func showLiveActivity(for suggestion: ProactiveSuggestion) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[SuggestionMonitor] Live Activities not enabled")
            return
        }

        // End any existing activity
        await endCurrentLiveActivity()

        // Create activity attributes
        let attributes = TaskActivityAttributes(
            userId: "", // Will be set from auth
            sessionId: "suggestion-\(suggestion.id)"
        )

        let contentState = TaskActivityAttributes.ContentState(
            title: suggestion.title,
            body: suggestion.body,
            priority: priorityForConfidence(suggestion.confidence),
            taskType: suggestion.type,
            personName: nil,
            deadline: nil,
            remainingCount: pendingSuggestions.count,
            actionId: suggestion.id
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: contentState, staleDate: nil),
                pushType: nil
            )

            currentLiveActivity = activity
            print("[SuggestionMonitor] Live Activity started: \(activity.id)")

            // Auto-dismiss after 30 seconds
            Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                await endCurrentLiveActivity()
            }

        } catch {
            print("[SuggestionMonitor] Failed to start Live Activity: \(error)")
        }
    }

    /// Convert confidence to priority string
    private func priorityForConfidence(_ confidence: Double) -> String {
        if confidence >= 0.9 { return "critical" }
        if confidence >= 0.8 { return "high" }
        if confidence >= 0.6 { return "medium" }
        return "low"
    }

    /// End the current Live Activity
    func endCurrentLiveActivity() async {
        guard let activity = currentLiveActivity else { return }

        await activity.end(nil, dismissalPolicy: .immediate)
        currentLiveActivity = nil
        pendingLiveActivitySuggestion = nil
        print("[SuggestionMonitor] Live Activity ended")
    }

    /// Update the Live Activity with new content
    func updateLiveActivity(title: String, body: String, remainingCount: Int) async {
        guard let activity = currentLiveActivity else { return }

        let updatedState = TaskActivityAttributes.ContentState(
            title: title,
            body: body,
            priority: "medium",
            taskType: "suggestion",
            personName: nil,
            deadline: nil,
            remainingCount: remainingCount,
            actionId: nil
        )

        await activity.update(.init(state: updatedState, staleDate: nil))
    }

    // MARK: - Persistence

    /// Save notified suggestion IDs to UserDefaults
    private func saveNotifiedIds() {
        UserDefaults.standard.set(Array(notifiedSuggestionIds), forKey: "notifiedSuggestionIds")
    }

    /// Clear notified IDs (useful for testing)
    func clearNotifiedIds() {
        notifiedSuggestionIds.removeAll()
        saveNotifiedIds()
        print("[SuggestionMonitor] Cleared notified suggestion IDs")
    }

    // MARK: - Manual Trigger

    /// Manually trigger a check (for pull-to-refresh, etc.)
    func manualCheck() async {
        await checkForNewSuggestions()
    }

    /// Force show Live Activity for testing
    func testLiveActivity() async {
        guard let testSuggestion = createTestSuggestion() else {
            print("[SuggestionMonitor] Failed to create test suggestion")
            return
        }
        await showLiveActivity(for: testSuggestion)
    }
}

// MARK: - Test Suggestion Helper

extension SuggestionMonitor {
    /// Create a test suggestion for debugging Live Activity
    private func createTestSuggestion() -> ProactiveSuggestion? {
        let json = """
        {
            "id": "test-\(UUID().uuidString)",
            "type": "follow_up",
            "title": "Test Suggestion",
            "body": "This is a test suggestion to verify Live Activity works correctly.",
            "confidence": 0.85,
            "reasoning": "Testing",
            "suggestedAction": null,
            "basedOnMemoryIds": [],
            "status": "pending",
            "createdAt": "\(ISO8601DateFormatter().string(from: Date()))"
        }
        """.data(using: .utf8)!

        return try? JSONDecoder().decode(ProactiveSuggestion.self, from: json)
    }
}

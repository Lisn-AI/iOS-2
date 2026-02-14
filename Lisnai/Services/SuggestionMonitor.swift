import Foundation
import ActivityKit
import UIKit

/// Monitors for new suggestions and syncs data for the UI
/// - Checks for suggestions every 5 minutes when app is in foreground
/// - Updates pendingSuggestions array for badge counts and Actions tab
/// - Shows Live Activity for high-confidence suggestions when app is active
/// - Backend APNs pushes are the sole push notification mechanism
@MainActor
class SuggestionMonitor: ObservableObject {
    static let shared = SuggestionMonitor()

    // MARK: - Configuration

    /// Interval between suggestion checks (5 minutes)
    private let checkInterval: TimeInterval = 5 * 60

    // MARK: - State

    @Published var isMonitoring = false
    @Published var lastCheckTime: Date?
    @Published var pendingSuggestions: [ProactiveSuggestion] = []
    @Published var currentLiveActivity: Activity<TaskActivityAttributes>?

    /// IDs of suggestions that have already been notified
    private var notifiedSuggestionIds: Set<String> = []

    /// Timer for periodic checks
    private var checkTimer: Timer?

    private let api = APIService.shared

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

            // Update published suggestions for UI (badge counts, Actions tab)
            pendingSuggestions = suggestions

            // Track new suggestions for badge updates
            let newSuggestions = suggestions.filter { !notifiedSuggestionIds.contains($0.id) }

            if !newSuggestions.isEmpty {
                print("[SuggestionMonitor] \(newSuggestions.count) new suggestions found")

                for suggestion in newSuggestions {
                    trackSuggestion(suggestion)
                }

                // Show Live Activity for the most urgent new suggestion while app is active
                if UIApplication.shared.applicationState == .active {
                    let bestSuggestion = newSuggestions
                        .sorted { $0.confidence > $1.confidence }
                        .first!
                    // Show for high-confidence (>= 0.7) suggestions
                    if bestSuggestion.confidence >= 0.7 {
                        await showLiveActivity(for: bestSuggestion)
                    }
                }
            } else {
                print("[SuggestionMonitor] No new suggestions")
            }

        } catch {
            print("[SuggestionMonitor] Error checking suggestions: \(error)")
        }
    }

    // MARK: - Tracking

    /// Track a new suggestion (data sync only — no local notifications)
    /// Backend APNs pushes handle all user-facing notifications.
    private func trackSuggestion(_ suggestion: ProactiveSuggestion) {
        notifiedSuggestionIds.insert(suggestion.id)
        saveNotifiedIds()
        print("[SuggestionMonitor] Tracked suggestion: \(suggestion.id)")
    }

    // MARK: - Live Activity

    /// Show Live Activity for a suggestion on the Dynamic Island / Lock Screen
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

            // Auto-dismiss after 60 seconds
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
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

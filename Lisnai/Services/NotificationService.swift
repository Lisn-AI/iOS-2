import Foundation
import UserNotifications
import UIKit
import SwiftData

/// Manages push notifications, notification categories, and APNs token registration
@MainActor
class NotificationService: ObservableObject {
    static let shared = NotificationService()

    @Published var isAuthorized = false
    @Published var deviceToken: String?
    @Published var apnsToken: Data?

    /// ModelContext for storing push data directly into SwiftData
    var modelContext: ModelContext?

    private let api = APIService.shared
    private let localStore = LocalStoreService.shared

    // MARK: - Notification Categories

    /// Notification category identifiers
    enum Category: String {
        case suggestion = "SUGGESTION"
        case suggestionCall = "SUGGESTION_CALL"
        case suggestionFollowup = "SUGGESTION_FOLLOWUP"
        case suggestionTask = "SUGGESTION_TASK"
        case suggestionInsight = "SUGGESTION_INSIGHT"
        case suggestionConnection = "SUGGESTION_CONNECTION"
        case suggestionEvent = "SUGGESTION_EVENT"
        case urgentSuggestion = "URGENT_SUGGESTION"
        case permissionRequest = "PERMISSION_REQUEST"
        case commitmentReminder = "COMMITMENT_REMINDER"
        case dailyBriefing = "DAILY_BRIEFING"
        case actionPending = "ACTION_PENDING"
    }

    /// Action identifiers
    enum Action: String {
        case accept = "ACCEPT_ACTION"
        case dismiss = "DISMISS_ACTION"
        case approve = "APPROVE_ACTION"
        case deny = "DENY_ACTION"
        case view = "VIEW_ACTION"
        case snooze = "SNOOZE_ACTION"
        case complete = "COMPLETE_ACTION"
    }

    // MARK: - Setup

    /// Request notification authorization and register categories
    func setup() async {
        await requestAuthorization()
        registerNotificationCategories()

        if isAuthorized {
            scheduleMorningReminder()
        }
    }

    /// Request notification authorization
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound, .criticalAlert])
            await MainActor.run {
                isAuthorized = granted
            }

            if granted {
                // Register for remote notifications on main thread
                await UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("[NotificationService] Authorization error: \(error)")
        }
    }

    /// Register notification action categories
    func registerNotificationCategories() {
        let center = UNUserNotificationCenter.current()

        // Suggestion actions
        let acceptAction = UNNotificationAction(
            identifier: Action.accept.rawValue,
            title: "Accept",
            options: [.foreground]
        )

        let dismissAction = UNNotificationAction(
            identifier: Action.dismiss.rawValue,
            title: "Dismiss",
            options: [.destructive]
        )

        let viewAction = UNNotificationAction(
            identifier: Action.view.rawValue,
            title: "View",
            options: [.foreground]
        )

        let snoozeAction = UNNotificationAction(
            identifier: Action.snooze.rawValue,
            title: "Snooze 1 Hour",
            options: []
        )

        // Permission actions
        let approveAction = UNNotificationAction(
            identifier: Action.approve.rawValue,
            title: "Approve",
            options: [.foreground, .authenticationRequired]
        )

        let denyAction = UNNotificationAction(
            identifier: Action.deny.rawValue,
            title: "Deny",
            options: [.destructive]
        )

        // Complete action for commitments
        let completeAction = UNNotificationAction(
            identifier: Action.complete.rawValue,
            title: "Mark Complete",
            options: []
        )

        // Generic suggestion category
        let suggestionCategory = UNNotificationCategory(
            identifier: Category.suggestion.rawValue,
            actions: [acceptAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "New suggestion from LisnAI",
            options: .customDismissAction
        )

        // Call reminder category
        let callCategory = UNNotificationCategory(
            identifier: Category.suggestionCall.rawValue,
            actions: [acceptAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Call reminder",
            options: .customDismissAction
        )

        // Follow-up category
        let followupCategory = UNNotificationCategory(
            identifier: Category.suggestionFollowup.rawValue,
            actions: [acceptAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Follow-up reminder",
            options: .customDismissAction
        )

        // Task reminder category
        let taskCategory = UNNotificationCategory(
            identifier: Category.suggestionTask.rawValue,
            actions: [acceptAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Task reminder",
            options: .customDismissAction
        )

        // Pattern insight category
        let insightCategory = UNNotificationCategory(
            identifier: Category.suggestionInsight.rawValue,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "New insight",
            options: .customDismissAction
        )

        // Connection prompt category
        let connectionCategory = UNNotificationCategory(
            identifier: Category.suggestionConnection.rawValue,
            actions: [acceptAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Connection suggestion",
            options: .customDismissAction
        )

        // Event reminder category
        let eventCategory = UNNotificationCategory(
            identifier: Category.suggestionEvent.rawValue,
            actions: [viewAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Event reminder",
            options: .customDismissAction
        )

        // Urgent suggestion category
        let urgentCategory = UNNotificationCategory(
            identifier: Category.urgentSuggestion.rawValue,
            actions: [acceptAction, viewAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Urgent suggestion",
            options: .customDismissAction
        )

        // Permission request category
        let permissionCategory = UNNotificationCategory(
            identifier: Category.permissionRequest.rawValue,
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Permission request",
            options: .customDismissAction
        )

        // Commitment reminder category
        let commitmentCategory = UNNotificationCategory(
            identifier: Category.commitmentReminder.rawValue,
            actions: [completeAction, snoozeAction, viewAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Commitment reminder",
            options: .customDismissAction
        )

        // Daily briefing category
        let briefingCategory = UNNotificationCategory(
            identifier: Category.dailyBriefing.rawValue,
            actions: [viewAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Your daily briefing is ready",
            options: []
        )

        // Action pending category
        let actionCategory = UNNotificationCategory(
            identifier: Category.actionPending.rawValue,
            actions: [viewAction, dismissAction],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "Action ready to execute",
            options: .customDismissAction
        )

        center.setNotificationCategories([
            suggestionCategory,
            callCategory,
            followupCategory,
            taskCategory,
            insightCategory,
            connectionCategory,
            eventCategory,
            urgentCategory,
            permissionCategory,
            commitmentCategory,
            briefingCategory,
            actionCategory
        ])

        print("[NotificationService] Registered \(12) notification categories")
    }

    // MARK: - Token Management

    /// Handle APNs token registration
    func handleDeviceTokenRegistration(_ deviceToken: Data) {
        self.apnsToken = deviceToken

        // Convert token to string for display/debugging
        let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
        let tokenString = tokenParts.joined()
        self.deviceToken = tokenString

        print("[NotificationService] APNs token: \(tokenString.prefix(20))...")

        // Register with backend
        Task {
            await registerTokenWithBackend(tokenString)
        }
    }

    /// Register device token with backend
    private func registerTokenWithBackend(_ token: String) async {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        do {
            _ = try await api.registerFCMToken(token: token, deviceId: deviceId)
            print("[NotificationService] Token registered with backend")
        } catch {
            print("[NotificationService] Failed to register token: \(error)")
        }
    }

    // MARK: - Notification Handling

    /// Handle notification action response
    func handleNotificationAction(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String
    ) async {
        print("[NotificationService] Handling action: \(actionIdentifier) for type: \(type)")

        switch actionIdentifier {
        case Action.accept.rawValue:
            await handleAcceptAction(type: type, userInfo: userInfo)

        case Action.dismiss.rawValue:
            await handleDismissAction(type: type, userInfo: userInfo)

        case Action.approve.rawValue:
            await handleApproveAction(userInfo: userInfo)

        case Action.deny.rawValue:
            await handleDenyAction(userInfo: userInfo)

        case Action.snooze.rawValue:
            await handleSnoozeAction(type: type, userInfo: userInfo)

        case Action.complete.rawValue:
            await handleCompleteAction(type: type, userInfo: userInfo)

        case Action.view.rawValue:
            handleViewAction(type: type, userInfo: userInfo)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification
            handleViewAction(type: type, userInfo: userInfo)

        default:
            break
        }
    }

    private func handleAcceptAction(type: String, userInfo: [AnyHashable: Any]) async {
        if type.starts(with: "suggestion") || type == "proactive_suggestion" {
            if let suggestionId = userInfo["suggestionId"] as? String {
                do {
                    _ = try await api.acceptSuggestion(suggestionId: suggestionId)
                    print("[NotificationService] Suggestion accepted: \(suggestionId)")
                } catch {
                    print("[NotificationService] Failed to accept suggestion: \(error)")
                }
            }
        }
    }

    private func handleDismissAction(type: String, userInfo: [AnyHashable: Any]) async {
        if type.starts(with: "suggestion") || type == "proactive_suggestion" {
            if let suggestionId = userInfo["suggestionId"] as? String {
                do {
                    _ = try await api.dismissSuggestion(suggestionId: suggestionId)
                    print("[NotificationService] Suggestion dismissed: \(suggestionId)")
                } catch {
                    print("[NotificationService] Failed to dismiss suggestion: \(error)")
                }
            }
        }
    }

    private func handleApproveAction(userInfo: [AnyHashable: Any]) async {
        if let permissionId = userInfo["permissionId"] as? String {
            do {
                _ = try await api.approvePermission(permissionId: permissionId, scope: .once)
                print("[NotificationService] Permission approved: \(permissionId)")
            } catch {
                print("[NotificationService] Failed to approve permission: \(error)")
            }
        }
    }

    private func handleDenyAction(userInfo: [AnyHashable: Any]) async {
        if let permissionId = userInfo["permissionId"] as? String {
            do {
                _ = try await api.denyPermission(permissionId: permissionId)
                print("[NotificationService] Permission denied: \(permissionId)")
            } catch {
                print("[NotificationService] Failed to deny permission: \(error)")
            }
        }
    }

    private func handleSnoozeAction(type: String, userInfo: [AnyHashable: Any]) async {
        // Schedule a local notification for 1 hour later
        let content = UNMutableNotificationContent()
        content.title = userInfo["aps.alert.title"] as? String ?? "Snoozed Reminder"
        content.body = userInfo["aps.alert.body"] as? String ?? "Your snoozed reminder"
        content.sound = .default
        content.userInfo = userInfo

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(
            identifier: "snoozed-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[NotificationService] Snoozed notification for 1 hour")
        } catch {
            print("[NotificationService] Failed to snooze: \(error)")
        }
    }

    private func handleCompleteAction(type: String, userInfo: [AnyHashable: Any]) async {
        if let commitmentId = userInfo["commitmentId"] as? String {
            do {
                _ = try await api.completeCommitment(commitmentId: commitmentId)
                print("[NotificationService] Commitment completed: \(commitmentId)")
            } catch {
                print("[NotificationService] Failed to complete commitment: \(error)")
            }
        }
    }

    private func handleViewAction(type: String, userInfo: [AnyHashable: Any]) {
        // Post appropriate notification to navigate
        switch type {
        case "daily_briefing":
            NotificationCenter.default.post(name: .openBriefing, object: nil, userInfo: userInfo)

        case "commitment_reminder":
            NotificationCenter.default.post(name: .openCommitments, object: nil, userInfo: userInfo)

        case "action_pending":
            NotificationCenter.default.post(name: .openActions, object: nil, userInfo: userInfo)

        case "permission_request":
            NotificationCenter.default.post(name: .openActions, object: nil, userInfo: userInfo)

        default:
            if type.starts(with: "suggestion") || type == "proactive_suggestion" {
                NotificationCenter.default.post(name: .openSuggestions, object: nil, userInfo: userInfo)
            }
        }
    }

    // MARK: - Push Data Processing (Local-First)

    /// Extract and store data payloads from push notifications into SwiftData
    func processIncomingDataPayload(_ userInfo: [AnyHashable: Any]) {
        guard let syncType = userInfo["syncType"] as? String else {
            // Not a data-push notification — normal notification, skip silently
            return
        }

        guard let syncDataString = userInfo["syncData"] as? String,
              let syncData = syncDataString.data(using: .utf8) else {
            print("[NotificationService] ERROR: syncType=\(syncType) but syncData is missing or invalid")
            return
        }

        guard let context = modelContext else {
            print("[NotificationService] ERROR: modelContext is nil — cannot store \(syncType) data from push!")
            return
        }

        print("[NotificationService] Processing push data: syncType=\(syncType), dataSize=\(syncData.count) bytes")

        switch syncType {
        case "commitments":
            do {
                let commitments = try JSONDecoder().decode([Commitment].self, from: syncData)
                localStore.storeCommitments(commitments, context: context)
                print("[NotificationService] Stored \(commitments.count) commitments from push")
            } catch {
                print("[NotificationService] ERROR decoding commitments: \(error)")
            }
        case "suggestions":
            do {
                let suggestions = try JSONDecoder().decode([ProactiveSuggestion].self, from: syncData)
                localStore.storeSuggestions(suggestions, context: context)
                print("[NotificationService] Stored \(suggestions.count) suggestions from push")
            } catch {
                print("[NotificationService] ERROR decoding suggestions: \(error)")
            }
        case "briefing":
            do {
                let briefing = try JSONDecoder().decode(PushBriefingPayload.self, from: syncData)
                let data = BriefingData(
                    id: nil, userId: nil,
                    date: briefing.date,
                    summary: briefing.summary,
                    keyMoments: briefing.keyMoments,
                    peopleInteracted: briefing.peopleInteracted,
                    pendingTasks: briefing.pendingTasks,
                    mood: briefing.mood,
                    insightfulObservation: briefing.insightfulObservation,
                    createdAt: nil, updatedAt: nil
                )
                let response = BriefingResponse(briefing: data)
                localStore.storeBriefing(response, context: context)
                print("[NotificationService] Stored briefing from push for \(briefing.date)")
            } catch {
                print("[NotificationService] ERROR decoding briefing: \(error)")
            }
        default:
            print("[NotificationService] Unknown syncType: \(syncType)")
        }
    }

    // MARK: - NSE Payload Processing

    /// Process payloads queued by the Notification Service Extension while the app was killed
    func processPendingExtensionPayloads() {
        let sharedDefaults = UserDefaults(suiteName: "group.com.lisnai.shared")
        guard let pending = sharedDefaults?.array(forKey: "pendingSyncPayloads") as? [[String: String]],
              !pending.isEmpty else {
            return
        }

        print("[NotificationService] Processing \(pending.count) payloads queued by NSE")

        for payload in pending {
            guard let syncType = payload["syncType"],
                  let syncData = payload["syncData"] else { continue }

            let userInfo: [AnyHashable: Any] = [
                "syncType": syncType,
                "syncData": syncData,
            ]
            processIncomingDataPayload(userInfo)
        }

        // Clear the queue
        sharedDefaults?.removeObject(forKey: "pendingSyncPayloads")
        print("[NotificationService] Cleared NSE payload queue")
    }

    // MARK: - Morning Reminder (Local Fallback)

    /// Schedule a recurring local morning notification as reliability fallback for APNs briefing
    func scheduleMorningReminder(hour: Int = 7, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()

        // Remove existing morning reminder to avoid duplicates
        center.removePendingNotificationRequests(withIdentifiers: ["morning-briefing-local"])

        let content = UNMutableNotificationContent()
        content.title = "Your day at a glance"
        content.body = "Yesterday's highlights, today's commitments, and what Lisn picked up — all in one place."
        content.sound = .default
        content.categoryIdentifier = Category.dailyBriefing.rawValue
        content.threadIdentifier = "daily-briefing"

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "morning-briefing-local",
            content: content,
            trigger: trigger
        )

        center.add(request) { error in
            if let error = error {
                print("[NotificationService] Failed to schedule morning reminder: \(error)")
            } else {
                print("[NotificationService] Morning reminder scheduled for \(hour):\(String(format: "%02d", minute))")
            }
        }
    }

    // MARK: - Local Notifications

    /// Schedule a local notification
    func scheduleLocalNotification(
        title: String,
        body: String,
        category: Category,
        userInfo: [String: Any] = [:],
        triggerDate: Date? = nil
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category.rawValue
        content.userInfo = userInfo

        var trigger: UNNotificationTrigger?
        if let date = triggerDate {
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }

    /// Clear all pending notifications
    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Update app badge
    func updateBadge(count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            print("[NotificationService] Failed to update badge: \(error)")
        }
    }
}

// MARK: - Push Briefing Payload

/// Lightweight Codable struct matching the briefing JSON embedded in push notifications
struct PushBriefingPayload: Codable {
    let date: String
    let summary: String
    let mood: String?
    let insightfulObservation: String?
    let keyMoments: [String]
    let peopleInteracted: [String]
    let pendingTasks: [String]
}

// MARK: - Extension for notification handling

extension AppDelegate {
    /// Enhanced notification action handling using NotificationService
    func handleNotificationActionEnhanced(
        type: String,
        userInfo: [AnyHashable: Any],
        actionIdentifier: String
    ) {
        Task { @MainActor in
            await NotificationService.shared.handleNotificationAction(
                type: type,
                userInfo: userInfo,
                actionIdentifier: actionIdentifier
            )
        }
    }
}

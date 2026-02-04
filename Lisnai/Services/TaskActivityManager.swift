import Foundation
import ActivityKit
import SwiftUI

/// Manages Task Recommendation Live Activities
@MainActor
class TaskActivityManager: ObservableObject {
    static let shared = TaskActivityManager()

    @Published var currentActivity: Activity<TaskActivityAttributes>?
    @Published var isActivityActive: Bool = false

    private let api = APIService.shared

    private init() {
        // Check if there's an existing activity on app launch
        checkForExistingActivity()
    }

    // MARK: - Activity Management

    /// Check for existing activities on app launch
    func checkForExistingActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[TaskActivity] Activities not enabled")
            return
        }

        // Find any existing task activities
        let existingActivities = Activity<TaskActivityAttributes>.activities
        if let existing = existingActivities.first {
            currentActivity = existing
            isActivityActive = true
            print("[TaskActivity] Found existing activity: \(existing.id)")
        }
    }

    /// Start a new task Live Activity
    func startActivity(
        userId: String,
        task: PrioritizedTask
    ) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw TaskActivityError.notEnabled
        }

        // End any existing activity first
        await endCurrentActivity()

        let attributes = TaskActivityAttributes(
            userId: userId,
            sessionId: UUID().uuidString
        )

        let initialState = TaskActivityAttributes.ContentState(
            title: task.title,
            body: task.body,
            priority: task.priority,
            taskType: task.taskType,
            personName: task.personName,
            deadline: task.deadline,
            remainingCount: task.remainingCount,
            actionId: task.actionId
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: .token // Enable push updates
            )

            currentActivity = activity
            isActivityActive = true

            print("[TaskActivity] Started activity: \(activity.id)")

            // Start monitoring for push token updates
            Task {
                for await tokenData in activity.pushTokenUpdates {
                    let tokenString = tokenData.map { String(format: "%02x", $0) }.joined()
                    print("[TaskActivity] Push token: \(tokenString)")
                    // Could send this token to backend for Live Activity updates
                }
            }
        } catch {
            print("[TaskActivity] Failed to start: \(error)")
            throw error
        }
    }

    /// Update the current activity with new task info
    func updateActivity(task: PrioritizedTask) async {
        guard let activity = currentActivity else {
            print("[TaskActivity] No active activity to update")
            return
        }

        let newState = TaskActivityAttributes.ContentState(
            title: task.title,
            body: task.body,
            priority: task.priority,
            taskType: task.taskType,
            personName: task.personName,
            deadline: task.deadline,
            remainingCount: task.remainingCount,
            actionId: task.actionId
        )

        await activity.update(using: newState)
        print("[TaskActivity] Updated activity with: \(task.title)")
    }

    /// End the current activity
    func endCurrentActivity() async {
        guard let activity = currentActivity else { return }

        await activity.end(nil, dismissalPolicy: .immediate)
        currentActivity = nil
        isActivityActive = false
        print("[TaskActivity] Ended activity")
    }

    /// End activity with final message
    func endWithMessage(_ message: String) async {
        guard let activity = currentActivity else { return }

        let finalState = TaskActivityAttributes.ContentState(
            title: "All Done!",
            body: message,
            priority: "low",
            taskType: "completed",
            personName: nil,
            deadline: nil,
            remainingCount: 0,
            actionId: nil
        )

        await activity.end(
            ActivityContent(state: finalState, staleDate: nil),
            dismissalPolicy: .default
        )
        currentActivity = nil
        isActivityActive = false
    }

    // MARK: - Fetch and Display Tasks

    /// Fetch prioritized suggestions and show top one as Live Activity
    func showTopPrioritizedTask(userId: String) async {
        do {
            // Fetch suggestions with priority
            let response = try await api.getSuggestions(status: "pending")

            // Filter for high-priority tasks
            let highPriorityTasks = response.suggestions.filter { suggestion in
                // If priority info is available, use it
                if let priorityInfo = (suggestion as? SuggestionWithPriority)?.priorityInfo {
                    return priorityInfo.priority == "critical" || priorityInfo.priority == "high"
                }
                // Otherwise use confidence as proxy
                return suggestion.confidence >= 0.7
            }

            guard let topTask = highPriorityTasks.first else {
                print("[TaskActivity] No high-priority tasks to show")
                return
            }

            // Convert to PrioritizedTask
            let task = PrioritizedTask(
                title: topTask.title,
                body: topTask.body,
                priority: "high", // Default since we filtered
                taskType: topTask.type,
                personName: extractPersonName(from: topTask),
                deadline: extractDeadline(from: topTask),
                remainingCount: highPriorityTasks.count,
                actionId: topTask.id
            )

            try await startActivity(userId: userId, task: task)
        } catch {
            print("[TaskActivity] Failed to fetch/show tasks: \(error)")
        }
    }

    /// Update Live Activity when task list changes
    func refreshActivity(userId: String) async {
        guard isActivityActive else {
            // No activity running, try to start one
            await showTopPrioritizedTask(userId: userId)
            return
        }

        do {
            let response = try await api.getSuggestions(status: "pending")

            let highPriorityTasks = response.suggestions.filter { $0.confidence >= 0.7 }

            if highPriorityTasks.isEmpty {
                // No more high-priority tasks, end activity
                await endWithMessage("No pending high-priority tasks")
                return
            }

            guard let topTask = highPriorityTasks.first else { return }

            let task = PrioritizedTask(
                title: topTask.title,
                body: topTask.body,
                priority: "high",
                taskType: topTask.type,
                personName: extractPersonName(from: topTask),
                deadline: extractDeadline(from: topTask),
                remainingCount: highPriorityTasks.count,
                actionId: topTask.id
            )

            await updateActivity(task: task)
        } catch {
            print("[TaskActivity] Failed to refresh: \(error)")
        }
    }

    // MARK: - Helpers

    private func extractPersonName(from suggestion: ProactiveSuggestion) -> String? {
        // Try to extract person from suggested action params
        if let action = suggestion.suggestedAction,
           let personValue = action.params["person"]?.stringValue {
            return personValue
        }

        // Try to extract from reasoning or body
        // This is a simplified extraction - could use NLP
        return nil
    }

    private func extractDeadline(from suggestion: ProactiveSuggestion) -> String? {
        // Try to extract from suggested action params
        if let action = suggestion.suggestedAction,
           let dueDate = action.params["dueDate"]?.stringValue {
            return formatDeadline(dueDate)
        }

        return nil
    }

    private func formatDeadline(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        let now = Date()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Today \(timeFormatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Tomorrow \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
    }
}

// MARK: - Supporting Types

struct PrioritizedTask {
    let title: String
    let body: String
    let priority: String
    let taskType: String
    let personName: String?
    let deadline: String?
    let remainingCount: Int
    let actionId: String?
}

enum TaskActivityError: Error {
    case notEnabled
    case alreadyActive
}

// Protocol for suggestions with priority info (from backend)
protocol SuggestionWithPriority {
    var priorityInfo: PriorityInfo? { get }
}

struct PriorityInfo: Codable {
    let priority: String
    let score: Int
    let reasoning: String
    let recommendedAction: String
    let deadline: String?
}

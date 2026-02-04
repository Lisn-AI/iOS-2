import Foundation
import ActivityKit

/// Attributes for the Task Recommendation Live Activity
/// Shows high-priority tasks/suggestions on the Lock Screen and Dynamic Island
struct TaskActivityAttributes: ActivityAttributes {
    /// Dynamic content that can change during the Live Activity
    public struct ContentState: Codable, Hashable {
        /// Task title
        var title: String
        /// Task description/body
        var body: String
        /// Priority level (critical, high, medium, low)
        var priority: String
        /// Task type (reminder, email, call, etc.)
        var taskType: String
        /// Associated person (if any)
        var personName: String?
        /// Due date/deadline (if any)
        var deadline: String?
        /// Number of remaining tasks
        var remainingCount: Int
        /// Action ID for handling taps
        var actionId: String?
    }

    // Static attributes (set when activity starts)
    /// User ID
    var userId: String
    /// Session identifier
    var sessionId: String
}

/// Priority levels for visual styling
extension TaskActivityAttributes.ContentState {
    var priorityColor: String {
        switch priority.lowercased() {
        case "critical": return "red"
        case "high": return "orange"
        case "medium": return "yellow"
        default: return "green"
        }
    }

    var priorityIcon: String {
        switch priority.lowercased() {
        case "critical": return "exclamationmark.triangle.fill"
        case "high": return "exclamationmark.circle.fill"
        case "medium": return "circle.fill"
        default: return "checkmark.circle"
        }
    }

    var taskIcon: String {
        switch taskType.lowercased() {
        case "reminder": return "bell.fill"
        case "email": return "envelope.fill"
        case "call": return "phone.fill"
        case "message": return "message.fill"
        case "calendar": return "calendar"
        case "commitment": return "checkmark.seal.fill"
        case "follow_up": return "arrow.turn.up.right"
        default: return "lightbulb.fill"
        }
    }
}

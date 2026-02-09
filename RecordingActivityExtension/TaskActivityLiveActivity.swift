import ActivityKit
import WidgetKit
import SwiftUI

struct TaskActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            TaskLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.state.taskIcon)
                        .font(.title)
                        .foregroundColor(priorityColor(context.state.priority))
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        if let personName = context.state.personName {
                            Text("With \(personName)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let deadline = context.state.deadline {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                Text(deadline)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack {
                        Image(systemName: context.state.priorityIcon)
                            .font(.title2)
                            .foregroundColor(priorityColor(context.state.priority))

                        if context.state.remainingCount > 1 {
                            Text("+\(context.state.remainingCount - 1)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        // Action button based on task type
                        Link(destination: actionURL(context.state)) {
                            HStack {
                                Image(systemName: actionIcon(context.state.taskType))
                                Text(actionLabel(context.state.taskType))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(priorityColor(context.state.priority))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        // Dismiss button
                        Link(destination: dismissURL(context.state)) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } compactLeading: {
                // Compact leading (left pill)
                Image(systemName: context.state.taskIcon)
                    .foregroundColor(priorityColor(context.state.priority))
            } compactTrailing: {
                // Compact trailing (right pill)
                if context.state.remainingCount > 1 {
                    Text("\(context.state.remainingCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(priorityColor(context.state.priority))
                } else {
                    Image(systemName: context.state.priorityIcon)
                        .font(.caption)
                        .foregroundColor(priorityColor(context.state.priority))
                }
            } minimal: {
                // Minimal view (when another app has priority)
                Image(systemName: context.state.taskIcon)
                    .foregroundColor(priorityColor(context.state.priority))
            }
        }
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "critical": return LisnSharedColors.error
        case "high": return LisnSharedColors.warning
        case "medium": return Color.yellow
        default: return LisnSharedColors.success
        }
    }

    private func actionIcon(_ taskType: String) -> String {
        switch taskType.lowercased() {
        case "reminder": return "bell"
        case "email": return "envelope"
        case "call": return "phone.arrow.up.right"
        case "message": return "message"
        default: return "arrow.right.circle"
        }
    }

    private func actionLabel(_ taskType: String) -> String {
        switch taskType.lowercased() {
        case "reminder": return "Create Reminder"
        case "email": return "Compose Email"
        case "call": return "Make Call"
        case "message": return "Send Message"
        default: return "View Task"
        }
    }

    private func actionURL(_ state: TaskActivityAttributes.ContentState) -> URL {
        if let actionId = state.actionId {
            return URL(string: "lisnai://task/execute/\(actionId)")!
        }
        return URL(string: "lisnai://tasks")!
    }

    private func dismissURL(_ state: TaskActivityAttributes.ContentState) -> URL {
        if let actionId = state.actionId {
            return URL(string: "lisnai://task/dismiss/\(actionId)")!
        }
        return URL(string: "lisnai://tasks/dismiss")!
    }
}

// Lock Screen / Banner View
struct TaskLockScreenView: View {
    let context: ActivityViewContext<TaskActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor(context.state.priority))
                .frame(width: 8, height: 8)

            // Task icon
            Image(systemName: context.state.taskIcon)
                .font(.title2)
                .foregroundColor(priorityColor(context.state.priority))
                .frame(width: 40)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.state.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Spacer()

                    // Remaining count badge
                    if context.state.remainingCount > 1 {
                        Text("+\(context.state.remainingCount - 1)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.3))
                            .cornerRadius(10)
                    }
                }

                Text(context.state.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack(spacing: 12) {
                    if let personName = context.state.personName {
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                                .font(.caption2)
                            Text(personName)
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }

                    if let deadline = context.state.deadline {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(deadline)
                                .font(.caption)
                        }
                        .foregroundColor(isUrgent(deadline) ? LisnSharedColors.warning : .secondary)
                    }

                    Spacer()

                    // Priority badge
                    Text(context.state.priority.capitalized)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(priorityColor(context.state.priority).opacity(0.2))
                        .foregroundColor(priorityColor(context.state.priority))
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.8))
    }

    private func priorityColor(_ priority: String) -> Color {
        switch priority.lowercased() {
        case "critical": return LisnSharedColors.error
        case "high": return LisnSharedColors.warning
        case "medium": return Color.yellow
        default: return LisnSharedColors.success
        }
    }

    private func isUrgent(_ deadline: String) -> Bool {
        // Simple check - could be enhanced
        return deadline.lowercased().contains("today") ||
               deadline.lowercased().contains("now") ||
               deadline.lowercased().contains("overdue")
    }
}

// Preview
#Preview("Lock Screen", as: .content, using: TaskActivityAttributes(userId: "test", sessionId: "session1")) {
    TaskActivityLiveActivity()
} contentStates: {
    TaskActivityAttributes.ContentState(
        title: "Call Mom",
        body: "You mentioned calling mom about the weekend plans",
        priority: "high",
        taskType: "call",
        personName: "Mom",
        deadline: "Today",
        remainingCount: 3,
        actionId: "task-123"
    )
    TaskActivityAttributes.ContentState(
        title: "Send project update",
        body: "Email the team about project status",
        priority: "medium",
        taskType: "email",
        personName: nil,
        deadline: nil,
        remainingCount: 1,
        actionId: "task-456"
    )
}

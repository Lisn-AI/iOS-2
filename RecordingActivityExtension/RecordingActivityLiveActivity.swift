import ActivityKit
import WidgetKit
import SwiftUI

struct RecordingActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            switch context.state.state {
            case .recording:
                RecordingLockScreenView(context: context)
            case .manualPause:
                ManualPauseLockScreenView(context: context)
            case .resumed:
                // Brief "mic resumed" feedback on Lock Screen
                ResumedLockScreenView(context: context)
            case .suggestion:
                SuggestionLockScreenView(context: context)
            default:
                // Paused (call) or readyToResume
                LockScreenView(context: context)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeadingIcon(for: context.state.state)
                }

                DynamicIslandExpandedRegion(.center) {
                    if context.state.state == .suggestion {
                        VStack(spacing: 4) {
                            Text(context.state.suggestionTitle ?? "Suggestion")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .lineLimit(1)

                            Text(context.state.suggestionBody ?? "")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    } else {
                        VStack(spacing: 4) {
                            Text(context.state.message)
                                .font(.headline)
                                .fontWeight(.semibold)

                            if context.state.state == .recording || context.state.state == .resumed {
                                Text(context.attributes.startDate, style: .timer)
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundColor(.secondary)
                            } else if context.state.state == .paused || context.state.state == .readyToResume {
                                Text("Paused at \(context.state.pausedAtDuration)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else if context.state.state == .manualPause {
                                Text("Paused at \(context.state.pausedAtDuration)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.state == .readyToResume {
                        if #available(iOS 17.0, *) {
                            Button(intent: ResumeRecordingIntent()) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title)
                                    .foregroundColor(LisnSharedColors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if context.state.state == .resumed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundColor(LisnSharedColors.accent)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.state == .suggestion {
                        // Suggestion: show dismiss + "Do it" buttons
                        if #available(iOS 17.0, *) {
                            HStack(spacing: 12) {
                                Button(intent: DismissSuggestionIntent()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                        Text("Dismiss")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.1))
                                    .foregroundColor(.white.opacity(0.7))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                if context.state.suggestionType == "action" {
                                    Button(intent: ExecuteSuggestionActionIntent()) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "sparkles")
                                                .font(.caption)
                                            Text("Do it")
                                                .font(.caption)
                                                .fontWeight(.medium)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(LisnSharedColors.accent)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    } else if context.state.state == .recording {
                        // Recording: show pause + discard buttons
                        if #available(iOS 17.0, *) {
                            HStack(spacing: 12) {
                                Button(intent: DiscardRecordingIntent()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                        Text("Discard")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.1))
                                    .foregroundColor(.white.opacity(0.7))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                Button(intent: PauseRecordingIntent()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pause.fill")
                                            .font(.caption)
                                        Text("Pause")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(LisnSharedColors.accent)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if context.state.state == .manualPause {
                        // Manual pause: show resume + discard buttons
                        if #available(iOS 17.0, *) {
                            HStack(spacing: 12) {
                                Button(intent: DiscardRecordingIntent()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                        Text("Discard")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(.white.opacity(0.1))
                                    .foregroundColor(.white.opacity(0.7))
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)

                                Button(intent: ResumeRecordingIntent()) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.fill")
                                            .font(.caption)
                                        Text("Resume")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(LisnSharedColors.accent)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if context.state.state == .readyToResume {
                        if #available(iOS 17.0, *) {
                            Button(intent: ResumeRecordingIntent()) {
                                HStack {
                                    Image(systemName: "play.fill")
                                    Text("Tap to Resume")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(LisnSharedColors.accent)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if context.state.state == .paused {
                        Text("Recording will resume when call ends")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if context.state.state == .resumed {
                        Text("Mic is active again")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(LisnSharedColors.accent)
                    }
                }
            } compactLeading: {
                // Compact leading (left pill)
                switch context.state.state {
                case .recording:
                    Image(systemName: "mic.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .resumed:
                    Image(systemName: "mic.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .paused:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.paused)
                case .manualPause:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .readyToResume:
                    Image(systemName: "play.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .suggestion:
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(LisnSharedColors.accent)
                }
            } compactTrailing: {
                // Compact trailing (right pill)
                switch context.state.state {
                case .recording:
                    Circle()
                        .fill(LisnSharedColors.accent)
                        .frame(width: 8, height: 8)
                case .resumed:
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(LisnSharedColors.accent)
                case .readyToResume:
                    Text("Resume")
                        .font(.caption2)
                        .foregroundColor(LisnSharedColors.accent)
                case .paused:
                    Text("Paused")
                        .font(.caption2)
                        .foregroundColor(LisnSharedColors.paused)
                case .manualPause:
                    Text("Paused")
                        .font(.caption2)
                        .foregroundColor(LisnSharedColors.accent)
                case .suggestion:
                    Text("Tip")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(LisnSharedColors.accent)
                }
            } minimal: {
                // Minimal view (when another app has priority)
                switch context.state.state {
                case .recording, .resumed:
                    Circle()
                        .fill(LisnSharedColors.accent)
                        .frame(width: 8, height: 8)
                case .paused, .readyToResume:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.paused)
                case .manualPause:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .suggestion:
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(LisnSharedColors.accent)
                }
            }
        }
    }

    @ViewBuilder
    private func expandedLeadingIcon(for state: RecordingActivityAttributes.RecordingState) -> some View {
        switch state {
        case .recording:
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        case .resumed:
            Image(systemName: "mic.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.paused)
        case .manualPause:
            Image(systemName: "pause.circle.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        case .readyToResume:
            Image(systemName: "mic.circle.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        case .suggestion:
            Image(systemName: "lightbulb.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        }
    }
}

// Lock Screen / Banner View (paused for call or readyToResume)
struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: context.state.state == .paused ? "pause.circle.fill" : "mic.circle.fill")
                .font(.largeTitle)
                .foregroundColor(context.state.state == .paused ? LisnSharedColors.paused : LisnSharedColors.accent)

            // Text content
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.message)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Paused at \(context.state.pausedAtDuration)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Resume button (only when ready to resume — fallback if auto-resume failed)
            if context.state.state == .readyToResume {
                if #available(iOS 17.0, *) {
                    Button(intent: ResumeRecordingIntent()) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Resume")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(LisnSharedColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.8))
    }
}

// Lock Screen view for manual pause (user-initiated)
struct ManualPauseLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Pause icon in accent color
            ZStack {
                Circle()
                    .fill(LisnSharedColors.accent.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "pause.circle.fill")
                    .font(.title2)
                    .foregroundColor(LisnSharedColors.accent)
            }

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text("Recording paused")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Paused at \(context.state.pausedAtDuration)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Resume + Discard buttons
            if #available(iOS 17.0, *) {
                HStack(spacing: 10) {
                    Button(intent: DiscardRecordingIntent()) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button(intent: ResumeRecordingIntent()) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundColor(LisnSharedColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(LisnSharedColors.accent)
    }
}

// Lock Screen view shown briefly after auto-resume (green confirmation)
struct ResumedLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "mic.fill")
                .font(.largeTitle)
                .foregroundColor(LisnSharedColors.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.message)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(LisnSharedColors.accent)

                Text("Recording is active")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        }
        .padding()
        .activityBackgroundTint(LisnSharedColors.accent.opacity(0.15))
    }
}

// Lock Screen / Banner View (active recording)
struct RecordingLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Mic icon with subtle glow
            ZStack {
                Circle()
                    .fill(LisnSharedColors.accent.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "mic.fill")
                    .font(.title2)
                    .foregroundColor(LisnSharedColors.accent)
            }

            // Text content
            VStack(alignment: .leading, spacing: 3) {
                Text("Lisn is recording")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                // Auto-updating timer — no state pushes needed
                Text(context.attributes.startDate, style: .timer)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()

            // Pause + Discard buttons replace the pulsing dot
            if #available(iOS 17.0, *) {
                HStack(spacing: 10) {
                    Button(intent: DiscardRecordingIntent()) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)

                    Button(intent: PauseRecordingIntent()) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title2)
                            .foregroundColor(LisnSharedColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(LisnSharedColors.accent)
    }
}

// Lock Screen view for live suggestion during recording
struct SuggestionLockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    private var isAction: Bool {
        context.state.suggestionType == "action"
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                // Suggestion icon
                ZStack {
                    Circle()
                        .fill(LisnSharedColors.accent.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isAction ? "bell.badge.fill" : "lightbulb.fill")
                        .font(.title2)
                        .foregroundColor(LisnSharedColors.accent)
                }

                // Title + body
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.suggestionTitle ?? "Suggestion")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(context.state.suggestionBody ?? "")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(2)
                }

                Spacer()

                // Dismiss button
                if #available(iOS 17.0, *) {
                    Button(intent: DismissSuggestionIntent()) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }

            // "Do it" button for action suggestions
            if isAction {
                if #available(iOS 17.0, *) {
                    Button(intent: ExecuteSuggestionActionIntent()) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                            Text("Do it")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(LisnSharedColors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.9))
        .activitySystemActionForegroundColor(LisnSharedColors.accent)
    }
}

// Preview
#Preview("Lock Screen", as: .content, using: RecordingActivityAttributes(startDate: Date())) {
    RecordingActivityLiveActivity()
} contentStates: {
    RecordingActivityAttributes.ContentState(
        state: .recording,
        pausedAtDuration: "",
        message: "Recording"
    )
    RecordingActivityAttributes.ContentState(
        state: .paused,
        pausedAtDuration: "02:34",
        message: "Recording paused for call"
    )
    RecordingActivityAttributes.ContentState(
        state: .manualPause,
        pausedAtDuration: "05:12",
        message: "Recording paused"
    )
    RecordingActivityAttributes.ContentState(
        state: .resumed,
        pausedAtDuration: "",
        message: "Mic resumed - Listening"
    )
    RecordingActivityAttributes.ContentState(
        state: .readyToResume,
        pausedAtDuration: "02:34",
        message: "Call ended"
    )
    RecordingActivityAttributes.ContentState(
        state: .suggestion,
        pausedAtDuration: "",
        message: "Recording",
        suggestionTitle: "Set a reminder?",
        suggestionBody: "You mentioned Thursday's meeting with Sarah",
        suggestionType: "action"
    )
}

import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Creative Visual Helpers

/// Glowing icon with concentric pulse rings — gives depth to leading icons
struct GlowingIcon: View {
    let systemName: String
    let color: Color
    let size: Font

    var body: some View {
        ZStack {
            // Outer glow ring
            Circle()
                .fill(color.opacity(0.08))
                .frame(width: 38, height: 38)
            // Inner glow ring
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 28, height: 28)
            // Icon
            Image(systemName: systemName)
                .font(size)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
}

/// Radiating live indicator — replaces the plain dot for active recording
struct LivePulseIndicator: View {
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
                .frame(width: 16, height: 16)
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 10, height: 10)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }
}

/// Lock screen icon badge with gradient ring
struct LockScreenIconBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            // Gradient ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.5), color.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 48, height: 48)
            // Fill
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 44, height: 44)
            // Icon
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }
}

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
                // Compact leading (left pill) — gradient-tinted icons
                switch context.state.state {
                case .recording:
                    Image(systemName: "mic.fill")
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.accent, LisnSharedColors.accent.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                case .resumed:
                    Image(systemName: "mic.fill")
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.success, LisnSharedColors.accent], startPoint: .top, endPoint: .bottom))
                case .paused:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.paused)
                case .manualPause:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .readyToResume:
                    Image(systemName: "play.fill")
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.accent, LisnSharedColors.success], startPoint: .leading, endPoint: .trailing))
                case .suggestion:
                    Image(systemName: "sparkles")
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.accent, .yellow], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            } compactTrailing: {
                // Compact trailing (right pill) — enhanced indicators
                switch context.state.state {
                case .recording:
                    LivePulseIndicator(color: LisnSharedColors.accent)
                case .resumed:
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.success, LisnSharedColors.accent], startPoint: .leading, endPoint: .trailing))
                case .readyToResume:
                    Text("Resume")
                        .font(.caption2)
                        .fontWeight(.medium)
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
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.accent, .yellow], startPoint: .leading, endPoint: .trailing))
                }
            } minimal: {
                // Minimal view (when another app has priority) — tiny but expressive
                switch context.state.state {
                case .recording, .resumed:
                    LivePulseIndicator(color: LisnSharedColors.accent)
                        .scaleEffect(0.7)
                case .paused, .readyToResume:
                    Image(systemName: "pause.fill")
                        .font(.caption2)
                        .foregroundColor(LisnSharedColors.paused)
                case .manualPause:
                    Image(systemName: "pause.fill")
                        .font(.caption2)
                        .foregroundColor(LisnSharedColors.accent)
                case .suggestion:
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(LinearGradient(colors: [LisnSharedColors.accent, .yellow], startPoint: .top, endPoint: .bottom))
                }
            }
        }
    }

    @ViewBuilder
    private func expandedLeadingIcon(for state: RecordingActivityAttributes.RecordingState) -> some View {
        switch state {
        case .recording:
            GlowingIcon(systemName: "mic.fill", color: LisnSharedColors.accent, size: .title2)
        case .resumed:
            GlowingIcon(systemName: "mic.fill", color: LisnSharedColors.success, size: .title2)
        case .paused:
            GlowingIcon(systemName: "pause.circle.fill", color: LisnSharedColors.paused, size: .title2)
        case .manualPause:
            GlowingIcon(systemName: "pause.circle.fill", color: LisnSharedColors.accent, size: .title2)
        case .readyToResume:
            GlowingIcon(systemName: "play.circle.fill", color: LisnSharedColors.accent, size: .title2)
        case .suggestion:
            GlowingIcon(systemName: "sparkles", color: LisnSharedColors.accent, size: .title2)
        }
    }
}

// Lock Screen / Banner View (paused for call or readyToResume)
struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Icon with gradient ring
            LockScreenIconBadge(
                systemName: context.state.state == .paused ? "pause.circle.fill" : "play.circle.fill",
                color: context.state.state == .paused ? LisnSharedColors.paused : LisnSharedColors.accent
            )

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
            // Pause icon with gradient ring
            LockScreenIconBadge(systemName: "pause.circle.fill", color: LisnSharedColors.accent)

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
                            .foregroundStyle(LinearGradient(colors: [LisnSharedColors.accent, LisnSharedColors.success], startPoint: .top, endPoint: .bottom))
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
            LockScreenIconBadge(systemName: "mic.fill", color: LisnSharedColors.success)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.message)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(LinearGradient(colors: [LisnSharedColors.success, LisnSharedColors.accent], startPoint: .leading, endPoint: .trailing))

                Text("Recording is active")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.title)
                .foregroundStyle(LinearGradient(colors: [LisnSharedColors.success, LisnSharedColors.accent], startPoint: .top, endPoint: .bottom))
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
            // Mic icon with gradient ring
            LockScreenIconBadge(systemName: "mic.fill", color: LisnSharedColors.accent)

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
                // Suggestion icon with gradient ring
                LockScreenIconBadge(
                    systemName: isAction ? "bolt.fill" : "sparkles",
                    color: LisnSharedColors.accent
                )

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

            // "Do it" button for action suggestions — gradient CTA
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
                        .background(
                            LinearGradient(
                                colors: [LisnSharedColors.accent, LisnSharedColors.accent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
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

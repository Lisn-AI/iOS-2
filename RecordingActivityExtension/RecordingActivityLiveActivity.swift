import ActivityKit
import WidgetKit
import SwiftUI

struct RecordingActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            switch context.state.state {
            case .recording:
                // Minimal lock screen view during recording (almost invisible)
                EmptyView()
            case .resumed:
                // Brief "mic resumed" feedback on Lock Screen
                ResumedLockScreenView(context: context)
            default:
                // Paused or readyToResume
                LockScreenView(context: context)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    expandedLeadingIcon(for: context.state.state)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.message)
                            .font(.headline)
                            .fontWeight(.semibold)

                        if context.state.state == .paused || context.state.state == .readyToResume {
                            Text("Paused at \(context.state.pausedAtDuration)")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                    if context.state.state == .readyToResume {
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
                    Circle()
                        .fill(LisnSharedColors.accent)
                        .frame(width: 8, height: 8)
                case .resumed:
                    Image(systemName: "mic.fill")
                        .foregroundColor(LisnSharedColors.accent)
                case .paused:
                    Image(systemName: "pause.fill")
                        .foregroundColor(LisnSharedColors.paused)
                case .readyToResume:
                    Image(systemName: "play.fill")
                        .foregroundColor(LisnSharedColors.accent)
                }
            } compactTrailing: {
                // Compact trailing (right pill)
                switch context.state.state {
                case .recording:
                    EmptyView()
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
        case .readyToResume:
            Image(systemName: "mic.circle.fill")
                .font(.title)
                .foregroundColor(LisnSharedColors.accent)
        }
    }
}

// Lock Screen / Banner View (paused or readyToResume)
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

// Preview
#Preview("Lock Screen", as: .content, using: RecordingActivityAttributes()) {
    RecordingActivityLiveActivity()
} contentStates: {
    RecordingActivityAttributes.ContentState(
        state: .paused,
        pausedAtDuration: "02:34",
        message: "Recording paused for call"
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
}

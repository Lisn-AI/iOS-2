import ActivityKit
import WidgetKit
import SwiftUI

struct RecordingActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Banner UI - only show when paused or ready to resume
            if context.state.state != .recording {
                LockScreenView(context: context)
            } else {
                // Minimal lock screen view during recording (almost invisible)
                EmptyView()
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI (when user long-presses)
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.state == .recording {
                        Image(systemName: "mic.fill")
                            .font(.title)
                            .foregroundColor(.green)
                    } else {
                        Image(systemName: context.state.state == .paused ? "pause.circle.fill" : "mic.circle.fill")
                            .font(.title)
                            .foregroundColor(context.state.state == .paused ? .orange : .green)
                    }
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
                                    .foregroundColor(.green)
                            }
                            .buttonStyle(.plain)
                        }
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
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if context.state.state == .paused {
                        Text("Recording will resume when call ends")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                // Compact leading (left pill)
                if context.state.state == .recording {
                    // Minimal during recording - small green dot
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: context.state.state == .paused ? "pause.fill" : "play.fill")
                        .foregroundColor(context.state.state == .paused ? .orange : .green)
                }
            } compactTrailing: {
                // Compact trailing (right pill)
                if context.state.state == .recording {
                    // Empty during recording to be minimal
                    EmptyView()
                } else if context.state.state == .readyToResume {
                    Text("Resume")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Text("Paused")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            } minimal: {
                // Minimal view (when another app has priority)
                if context.state.state == .recording {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                } else {
                    Image(systemName: "pause.fill")
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

// Lock Screen / Banner View
struct LockScreenView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: context.state.state == .paused ? "pause.circle.fill" : "mic.circle.fill")
                .font(.largeTitle)
                .foregroundColor(context.state.state == .paused ? .orange : .green)

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

            // Resume button (only when ready to resume)
            if context.state.state == .readyToResume {
                if #available(iOS 17.0, *) {
                    Button(intent: ResumeRecordingIntent()) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Resume")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.green)
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
        state: .readyToResume,
        pausedAtDuration: "02:34",
        message: "Call ended"
    )
}

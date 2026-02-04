import AppIntents
import ActivityKit

/// AppIntent that resumes recording when tapped in the Live Activity
/// This opens the app first, which allows recording to actually start
@available(iOS 17.0, *)
struct ResumeRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume Recording"
    static var description: IntentDescription? = IntentDescription("Resumes the paused recording")

    // CRITICAL: This opens the app when the intent runs
    // Without this, the intent runs in background where recording cannot start
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some OpensIntent {
        // Post notification to resume recording
        // The RecordingManager will listen for this notification
        NotificationCenter.default.post(
            name: Notification.Name("ResumeRecordingFromLiveActivity"),
            object: nil
        )

        return .result()
    }
}

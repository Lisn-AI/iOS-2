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

/// Pauses recording from the Live Activity
@available(iOS 17.0, *)
struct PauseRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Recording"
    static var description: IntentDescription? = IntentDescription("Pauses the active recording")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some OpensIntent {
        NotificationCenter.default.post(
            name: Notification.Name("PauseRecordingFromLiveActivity"),
            object: nil
        )
        return .result()
    }
}

/// Discards recording from the Live Activity — opens app for confirmation dialog
@available(iOS 17.0, *)
struct DiscardRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Discard Recording"
    static var description: IntentDescription? = IntentDescription("Discards the active recording")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some OpensIntent {
        NotificationCenter.default.post(
            name: Notification.Name("DiscardRecordingFromLiveActivity"),
            object: nil
        )
        return .result()
    }
}

/// Dismisses the live suggestion banner from the Live Activity
@available(iOS 17.0, *)
struct DismissSuggestionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Dismiss Suggestion"
    static var description: IntentDescription? = IntentDescription("Dismisses the live suggestion")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some OpensIntent {
        NotificationCenter.default.post(
            name: Notification.Name("DismissSuggestionFromLiveActivity"),
            object: nil
        )
        return .result()
    }
}

/// Executes the action from a live suggestion
@available(iOS 17.0, *)
struct ExecuteSuggestionActionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Execute Suggestion"
    static var description: IntentDescription? = IntentDescription("Executes the suggested action")

    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some OpensIntent {
        NotificationCenter.default.post(
            name: Notification.Name("ExecuteSuggestionFromLiveActivity"),
            object: nil
        )
        return .result()
    }
}

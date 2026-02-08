import Foundation
import ActivityKit

/// Attributes for the Recording Live Activity
/// This defines the static and dynamic data for the Live Activity
struct RecordingActivityAttributes: ActivityAttributes {
    /// Dynamic content that can change during the Live Activity
    public struct ContentState: Codable, Hashable {
        /// Current state of the recording
        var state: RecordingState
        /// Duration when paused (for display)
        var pausedAtDuration: String
        /// Message to display
        var message: String
    }

    /// Recording states for the Live Activity
    enum RecordingState: String, Codable, Hashable {
        case recording = "recording"          // Normal recording state
        case paused = "paused"                // Paused for phone call
        case resumed = "resumed"              // Just auto-resumed after call (brief visual prompt)
        case readyToResume = "readyToResume"  // Fallback: auto-resume failed, tap to resume
    }

    // Static attributes (don't change during the activity)
    // We don't need any for this simple use case
}

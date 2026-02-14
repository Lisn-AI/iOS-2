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
        /// Live suggestion fields (only populated when state == .suggestion)
        var suggestionTitle: String?
        var suggestionBody: String?
        var suggestionType: String?  // "action" or "context"
    }

    /// Recording states for the Live Activity
    enum RecordingState: String, Codable, Hashable {
        case recording = "recording"          // Normal recording state
        case paused = "paused"                // Paused for phone call
        case manualPause = "manualPause"      // User manually paused
        case resumed = "resumed"              // Just auto-resumed after call (brief visual prompt)
        case readyToResume = "readyToResume"  // Fallback: auto-resume failed, tap to resume
        case suggestion = "suggestion"        // Live suggestion surfaced during recording
    }

    // Static attributes (set once when the activity starts)
    /// When the recording started — used for auto-updating timer on lock screen
    var startDate: Date = Date()
}

import Foundation
import SwiftData

/// Represents a single recording session
@Model
final class Recording {
    var id: UUID = UUID()
    var date: Date
    var duration: TimeInterval
    var createdAt: Date = Date()

    /// AI-generated descriptive title for this recording
    var title: String?

    /// Relationship to transcription (deleted when recording is deleted)
    @Relationship(deleteRule: .cascade, inverse: \Transcription.recording)
    var transcription: Transcription?

    /// Relationship to summary (deleted when recording is deleted)
    @Relationship(deleteRule: .cascade, inverse: \Summary.recording)
    var summary: Summary?

    /// Relationship to AI insight (deleted when recording is deleted)
    @Relationship(deleteRule: .cascade)
    var insight: Insight?

    /// Whether this recording has been synced to cloud
    var isSynced: Bool = false

    init(date: Date, duration: TimeInterval, title: String? = nil) {
        self.date = date
        self.duration = duration
        self.title = title
    }
}

// MARK: - Computed Properties
extension Recording {
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

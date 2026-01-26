import Foundation
import SwiftData

/// Represents the transcription of a recording
@Model
final class Transcription {
    var id: UUID = UUID()
    var date: Date
    var text: String
    var createdAt: Date = Date()

    /// The recording this transcription belongs to
    var recording: Recording?

    /// Whether this has been synced to cloud
    var isSynced: Bool = false

    init(date: Date, text: String, recording: Recording? = nil) {
        self.date = date
        self.text = text
        self.recording = recording
    }
}

// MARK: - Computed Properties
extension Transcription {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Preview text (first 100 characters)
    var preview: String {
        if text.count <= 100 {
            return text
        }
        return String(text.prefix(100)) + "..."
    }

    /// Word count
    var wordCount: Int {
        text.split(separator: " ").count
    }
}

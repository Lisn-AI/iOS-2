import Foundation
import SwiftData

/// Represents an AI-generated summary of a recording
@Model
final class Summary {
    var id: UUID = UUID()
    var date: Date
    var text: String
    var createdAt: Date = Date()

    /// The recording this summary belongs to
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
extension Summary {
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

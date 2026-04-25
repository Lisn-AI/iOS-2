import Foundation
import SwiftData

/// Represents a message in the AI chat
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var content: String
    var isUser: Bool
    var timestamp: Date = Date()

    /// Tool calls made by the assistant (stored as JSON)
    var toolCallsJSON: String?

    /// JSON-encoded [String] of source memory IDs used in this response
    var sourcesJSON: String?

    /// Recording ID for per-recording chat threads. nil = main/global chat.
    var recordingId: UUID?

    init(content: String, isUser: Bool, recordingId: UUID? = nil) {
        self.content = content
        self.isUser = isUser
        self.recordingId = recordingId
    }
}

// MARK: - Computed Properties
extension ChatMessage {
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var sourceIds: [String] {
        guard let json = sourcesJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var decodedToolCalls: [InlineToolCall]? {
        guard let json = toolCallsJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([InlineToolCall].self, from: data)
    }
}

// MARK: - Tool Call Types (not persisted, used for API)
struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCall

    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

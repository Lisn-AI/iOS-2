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

    init(content: String, isUser: Bool) {
        self.content = content
        self.isUser = isUser
    }
}

// MARK: - Computed Properties
extension ChatMessage {
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
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

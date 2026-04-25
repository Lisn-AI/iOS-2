import Foundation

/// Status lifecycle for an inline tool call
enum ToolCallStatus: String, Codable {
    case preparing           // tool_call received, server executing
    case completed           // tool_result success=true
    case failed              // tool_result success=false
    case permissionRequired  // tool_result status="permission_required"
}

/// Represents a tool call made inline during a chat response
struct InlineToolCall: Codable, Identifiable {
    let id: String
    let skill: String
    let tool: String
    var params: [String: AnyCodable]
    var status: ToolCallStatus
    var resultMessage: String?
    var actionId: String?
    var pendingPermissionId: String?

    /// Convert to a PendingAction for compatibility with ActionEditSheet and ActionExecutor
    /// Uses actionId (UUID from backend) when available; generates a new UUID as fallback
    /// to avoid passing non-UUID tool call IDs (e.g. Gemini's "function-call-xxx") to the API
    func toPendingAction() -> PendingAction {
        PendingAction(
            id: actionId ?? UUID().uuidString,
            skill: skill,
            tool: tool,
            type: tool,
            params: params,
            status: status.rawValue,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// Create from SSE tool_call event — initial status is .preparing
    static func from(id: String, skill: String, tool: String, params: [String: Any]) -> InlineToolCall {
        let codableParams = params.mapValues { AnyCodable($0) }
        return InlineToolCall(
            id: id,
            skill: skill,
            tool: tool,
            params: codableParams,
            status: .preparing,
            resultMessage: nil,
            actionId: nil,
            pendingPermissionId: nil
        )
    }
}

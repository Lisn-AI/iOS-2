import Foundation
import SwiftData

/// Local suggestion storage for on-device persistence
/// Unified model: absorbs suggestions, commitments, live suggestions, and chat actions
@Model
final class LocalSuggestion {
    var id: UUID = UUID()
    var serverSuggestionId: String?
    var type: String
    var title: String
    var body: String
    var confidence: Double = 0.5
    var reasoning: String?
    var status: String = "pending"
    var isSynced: Bool = false
    var createdAt: Date = Date()
    var suggestedActionJSON: String?
    var basedOnMemoryIds: [String]?

    // Unified pipeline fields
    var category: String = "active"       // "active" | "insight"
    var source: String = "orchestrator"   // "orchestrator" | "memory_check" | "commitment" | "live" | "chat"
    var expiryRule: String?               // TTL rule name
    var person: String?                   // From commitments
    var dueDate: Date?                    // From commitments
    var urgency: String = "normal"        // "low" | "normal" | "high"
    var completedAt: Date?                // For marking done

    init(
        serverSuggestionId: String? = nil,
        type: String,
        title: String,
        body: String,
        confidence: Double = 0.5,
        reasoning: String? = nil,
        status: String = "pending",
        isSynced: Bool = false,
        suggestedActionJSON: String? = nil,
        basedOnMemoryIds: [String]? = nil,
        category: String = "active",
        source: String = "orchestrator",
        expiryRule: String? = nil,
        person: String? = nil,
        dueDate: Date? = nil,
        urgency: String = "normal"
    ) {
        self.serverSuggestionId = serverSuggestionId
        self.type = type
        self.title = title
        self.body = body
        self.confidence = confidence
        self.reasoning = reasoning
        self.status = status
        self.isSynced = isSynced
        self.suggestedActionJSON = suggestedActionJSON
        self.basedOnMemoryIds = basedOnMemoryIds
        self.category = category
        self.source = source
        self.expiryRule = expiryRule
        self.person = person
        self.dueDate = dueDate
        self.urgency = urgency
    }

    /// Check if this suggestion has expired based on its TTL rule
    var isExpired: Bool {
        guard let rule = expiryRule else { return false }
        let expiryDate: Date
        switch rule {
        case "call_reminder_4h":
            expiryDate = createdAt.addingTimeInterval(4 * 3600)
        case "task_reminder_48h":
            expiryDate = createdAt.addingTimeInterval(48 * 3600)
        case "pattern_insight_7d", "connection_prompt_7d":
            expiryDate = createdAt.addingTimeInterval(7 * 24 * 3600)
        case "event_reminder_post":
            expiryDate = (dueDate ?? createdAt).addingTimeInterval(1 * 3600)
        case "chat_action_24h", "live_suggestion_24h":
            expiryDate = createdAt.addingTimeInterval(24 * 3600)
        case "commitment_due_buffer":
            expiryDate = (dueDate ?? createdAt.addingTimeInterval(7 * 24 * 3600)).addingTimeInterval(24 * 3600)
        default:
            expiryDate = createdAt.addingTimeInterval(48 * 3600)
        }
        return Date() > expiryDate
    }

    /// Clean expired suggestions from SwiftData
    static func cleanExpired(context: ModelContext) {
        let pendingStatus = "pending"
        let predicate = #Predicate<LocalSuggestion> { $0.status == pendingStatus }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let all = try? context.fetch(descriptor) else { return }
        var cleaned = 0
        for suggestion in all where suggestion.isExpired {
            suggestion.status = "expired"
            cleaned += 1
        }
        if cleaned > 0 {
            try? context.save()
            print("[LocalSuggestion] Expired \(cleaned) suggestions")
        }
    }

    /// Convert to API ProactiveSuggestion model for views that expect the API type
    func toAPISuggestion() -> ProactiveSuggestion {
        var action: SuggestedAction? = nil
        if let json = suggestedActionJSON,
           let data = json.data(using: .utf8) {
            action = try? JSONDecoder().decode(SuggestedAction.self, from: data)
        }
        return ProactiveSuggestion(
            id: serverSuggestionId ?? id.uuidString,
            type: type,
            title: title,
            body: body,
            confidence: confidence,
            reasoning: reasoning ?? "",
            suggestedAction: action,
            basedOnMemoryIds: basedOnMemoryIds,
            status: status,
            createdAt: createdAt.ISO8601Format()
        )
    }
}

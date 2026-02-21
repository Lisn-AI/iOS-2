import Foundation
import SwiftData

/// Local suggestion storage for on-device persistence
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
        basedOnMemoryIds: [String]? = nil
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

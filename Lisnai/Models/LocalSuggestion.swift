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

    init(
        serverSuggestionId: String? = nil,
        type: String,
        title: String,
        body: String,
        confidence: Double = 0.5,
        reasoning: String? = nil,
        status: String = "pending",
        isSynced: Bool = false
    ) {
        self.serverSuggestionId = serverSuggestionId
        self.type = type
        self.title = title
        self.body = body
        self.confidence = confidence
        self.reasoning = reasoning
        self.status = status
        self.isSynced = isSynced
    }
}

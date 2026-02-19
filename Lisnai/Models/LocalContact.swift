import Foundation
import SwiftData

/// Local contact storage for on-device persistence
@Model
final class LocalContact {
    var id: UUID = UUID()
    var name: String
    var relationship: String?
    var lastInteraction: Date?
    var interactionCount: Int = 0
    var isSynced: Bool = false
    var createdAt: Date = Date()

    init(
        name: String,
        relationship: String? = nil,
        lastInteraction: Date? = nil,
        interactionCount: Int = 0,
        isSynced: Bool = false
    ) {
        self.name = name
        self.relationship = relationship
        self.lastInteraction = lastInteraction
        self.interactionCount = interactionCount
        self.isSynced = isSynced
    }
}

import Foundation
import SwiftData

/// Local commitment storage for on-device persistence
@Model
final class LocalCommitment {
    var id: UUID = UUID()
    var serverCommitmentId: String?
    var commitmentDescription: String
    var type: String
    var person: String?
    var dueDate: Date?
    var urgency: String = "normal"
    var status: String = "pending"
    var completedAt: Date?
    var isSynced: Bool = false
    var createdAt: Date = Date()

    init(
        serverCommitmentId: String? = nil,
        commitmentDescription: String,
        type: String = "task",
        person: String? = nil,
        dueDate: Date? = nil,
        urgency: String = "normal",
        status: String = "pending",
        isSynced: Bool = false
    ) {
        self.serverCommitmentId = serverCommitmentId
        self.commitmentDescription = commitmentDescription
        self.type = type
        self.person = person
        self.dueDate = dueDate
        self.urgency = urgency
        self.status = status
        self.isSynced = isSynced
    }
}

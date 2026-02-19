import Foundation
import SwiftData

/// Local briefing storage for on-device persistence
@Model
final class LocalBriefing {
    var id: UUID = UUID()
    var date: String
    var summary: String?
    var mood: String?
    var insightfulObservation: String?
    var keyMomentsData: Data?
    var peopleInteractedData: Data?
    var pendingTasksData: Data?
    var isSynced: Bool = false
    var createdAt: Date = Date()

    init(
        date: String,
        summary: String? = nil,
        mood: String? = nil,
        insightfulObservation: String? = nil,
        keyMoments: [String] = [],
        peopleInteracted: [String] = [],
        pendingTasks: [String] = [],
        isSynced: Bool = false
    ) {
        self.date = date
        self.summary = summary
        self.mood = mood
        self.insightfulObservation = insightfulObservation
        self.keyMoments = keyMoments
        self.peopleInteracted = peopleInteracted
        self.pendingTasks = pendingTasks
        self.isSynced = isSynced
    }

    // MARK: - Computed Properties

    var keyMoments: [String] {
        get {
            guard let data = keyMomentsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            keyMomentsData = try? JSONEncoder().encode(newValue)
        }
    }

    var peopleInteracted: [String] {
        get {
            guard let data = peopleInteractedData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            peopleInteractedData = try? JSONEncoder().encode(newValue)
        }
    }

    var pendingTasks: [String] {
        get {
            guard let data = pendingTasksData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            pendingTasksData = try? JSONEncoder().encode(newValue)
        }
    }
}

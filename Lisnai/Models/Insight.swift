import Foundation
import SwiftData

/// Stores a correlation between the current recording and a past memory
struct InsightCorrelation: Codable {
    let memoryDate: String
    let connection: String
}

/// AI-generated insight from post-recording analysis
@Model
final class Insight {
    var id: UUID = UUID()
    var date: Date
    var setting: String
    var settingEmoji: String?
    var mood: String?
    var thirdPersonTake: String     // Markdown
    var correlationsData: Data?     // Encoded [InsightCorrelation]
    var actionableIdeasData: Data?  // Encoded [String]

    @Relationship(inverse: \Recording.insight)
    var recording: Recording?

    init(
        date: Date,
        setting: String,
        settingEmoji: String? = nil,
        mood: String? = nil,
        thirdPersonTake: String,
        correlations: [InsightCorrelation] = [],
        actionableIdeas: [String] = []
    ) {
        self.date = date
        self.setting = setting
        self.settingEmoji = settingEmoji
        self.mood = mood
        self.thirdPersonTake = thirdPersonTake
        self.correlationsData = try? JSONEncoder().encode(correlations)
        self.actionableIdeasData = try? JSONEncoder().encode(actionableIdeas)
    }

    var correlations: [InsightCorrelation] {
        guard let data = correlationsData else { return [] }
        return (try? JSONDecoder().decode([InsightCorrelation].self, from: data)) ?? []
    }

    var actionableIdeas: [String] {
        guard let data = actionableIdeasData else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
}

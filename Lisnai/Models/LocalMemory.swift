import Foundation
import SwiftData

/// Local memory storage for on-device persistence
/// Mirrors the backend memories table with embedded vector for local search
@Model
final class LocalMemory {
    var id: UUID = UUID()
    var serverMemoryId: String?
    /// UUID of the linked Recording in SwiftData — used for navigation from search/sources
    var recordingId: UUID?
    var timestamp: Date
    var title: String?
    var rawTranscript: String
    var summary: String?
    var topicsData: Data?
    var peopleData: Data?
    var entitiesJSON: String?
    var sentiment: String?
    var importanceScore: Double = 0.5
    /// Encoded [Float] — ~6KB per 1536-dim vector
    var embeddingData: Data?
    var isSynced: Bool = false
    var createdAt: Date = Date()

    init(
        serverMemoryId: String? = nil,
        timestamp: Date = Date(),
        title: String? = nil,
        rawTranscript: String,
        summary: String? = nil,
        topics: [String] = [],
        people: [String] = [],
        sentiment: String? = nil,
        importanceScore: Double = 0.5,
        embedding: [Float]? = nil,
        isSynced: Bool = false
    ) {
        self.serverMemoryId = serverMemoryId
        self.timestamp = timestamp
        self.title = title
        self.rawTranscript = rawTranscript
        self.summary = summary
        self.topics = topics
        self.people = people
        self.sentiment = sentiment
        self.importanceScore = importanceScore
        self.embedding = embedding
        self.isSynced = isSynced
    }

    // MARK: - Computed Properties

    var topics: [String] {
        get {
            guard let data = topicsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            topicsData = try? JSONEncoder().encode(newValue)
        }
    }

    var people: [String] {
        get {
            guard let data = peopleData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            peopleData = try? JSONEncoder().encode(newValue)
        }
    }

    var embedding: [Float]? {
        get {
            guard let data = embeddingData else { return nil }
            return data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }
        set {
            guard let values = newValue else {
                embeddingData = nil
                return
            }
            embeddingData = values.withUnsafeBufferPointer { buffer in
                Data(buffer: buffer)
            }
        }
    }
}

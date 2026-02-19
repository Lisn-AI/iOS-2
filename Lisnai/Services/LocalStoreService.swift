import Foundation
import SwiftData

/// Handles saving API results to SwiftData for local persistence
class LocalStoreService {
    static let shared = LocalStoreService()

    // MARK: - Memory Storage

    /// Store a memory from chunk processing result
    func storeMemoryFromResult(
        _ result: ChunkProcessResult,
        transcript: String,
        context: ModelContext
    ) {
        let memory = LocalMemory(
            serverMemoryId: result.memoryId,
            timestamp: Date(),
            title: result.title,
            rawTranscript: transcript,
            summary: result.summary,
            isSynced: false
        )

        // Store embedding if provided (local mode)
        if let embedding = result.embedding {
            memory.embedding = embedding
        }

        context.insert(memory)
        try? context.save()
        print("[LocalStore] Memory saved — id=\(memory.serverMemoryId ?? "local"), title=\(memory.title ?? "nil"), hasEmbedding=\(memory.embeddingData != nil)")
    }

    // MARK: - Commitment Storage

    /// Save commitments fetched from API to local SwiftData
    func storeCommitments(_ commitments: [Commitment], context: ModelContext) {
        for commitment in commitments {
            // Check if already stored
            let id = commitment.id
            let predicate = #Predicate<LocalCommitment> { $0.serverCommitmentId == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = (try? context.fetch(descriptor))?.first

            if existing != nil { continue }

            let local = LocalCommitment(
                serverCommitmentId: commitment.id,
                commitmentDescription: commitment.description,
                type: commitment.type,
                person: commitment.person,
                dueDate: ISO8601DateFormatter().date(from: commitment.dueDate ?? ""),
                urgency: commitment.urgency,
                status: commitment.status,
                isSynced: true
            )
            context.insert(local)
            print("[LocalStore] Commitment saved — id=\(local.serverCommitmentId ?? "local"), type=\(local.type)")
        }
        try? context.save()
    }

    // MARK: - Suggestion Storage

    /// Save suggestions fetched from API to local SwiftData
    func storeSuggestions(_ suggestions: [ProactiveSuggestion], context: ModelContext) {
        for suggestion in suggestions {
            let id = suggestion.id
            let predicate = #Predicate<LocalSuggestion> { $0.serverSuggestionId == id }
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = (try? context.fetch(descriptor))?.first

            if existing != nil { continue }

            let local = LocalSuggestion(
                serverSuggestionId: suggestion.id,
                type: suggestion.type,
                title: suggestion.title,
                body: suggestion.body,
                confidence: suggestion.confidence,
                reasoning: suggestion.reasoning,
                status: suggestion.status,
                isSynced: true
            )
            context.insert(local)
            print("[LocalStore] Suggestion saved — id=\(local.serverSuggestionId ?? "local"), type=\(local.type), title=\(local.title)")
        }
        try? context.save()
    }

    // MARK: - Briefing Storage

    /// Save briefing to local SwiftData
    func storeBriefing(_ briefing: BriefingResponse, context: ModelContext) {
        let dateStr = briefing.date
        if dateStr.isEmpty { return }

        // Check if already stored
        let predicate = #Predicate<LocalBriefing> { $0.date == dateStr }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            // Update existing
            if let local = existing.first {
                local.summary = briefing.summary
                local.mood = briefing.mood
                local.insightfulObservation = briefing.insightfulObservation
                local.keyMoments = briefing.keyMoments
                local.peopleInteracted = briefing.peopleInteracted ?? []
                local.pendingTasks = briefing.pendingTasks ?? []
            }
        } else {
            let local = LocalBriefing(
                date: dateStr,
                summary: briefing.summary,
                mood: briefing.mood,
                insightfulObservation: briefing.insightfulObservation,
                keyMoments: briefing.keyMoments,
                peopleInteracted: briefing.peopleInteracted ?? [],
                pendingTasks: briefing.pendingTasks ?? [],
                isSynced: true
            )
            context.insert(local)
            print("[LocalStore] Briefing saved — date=\(local.date)")
        }
        try? context.save()
    }

    // MARK: - Contact Storage

    /// Update or create local contacts from people mentioned in memories
    func updateContacts(people: [String], context: ModelContext) {
        for name in people {
            let personName = name
            let predicate = #Predicate<LocalContact> { $0.name == personName }
            let descriptor = FetchDescriptor(predicate: predicate)
            let existing = (try? context.fetch(descriptor))?.first

            if let contact = existing {
                contact.interactionCount += 1
                contact.lastInteraction = Date()
            } else {
                let contact = LocalContact(
                    name: name,
                    lastInteraction: Date(),
                    interactionCount: 1
                )
                context.insert(contact)
            }
        }
        try? context.save()
    }
}

import Foundation
import SwiftData

/// Central data router that handles cloud vs local-only mode
/// All views/services call DataService instead of APIService directly
@MainActor
class DataService: ObservableObject {
    static let shared = DataService()

    @Published var isCloudMode: Bool {
        didSet {
            UserDefaults.standard.set(isCloudMode, forKey: "cloudBackupEnabled")
            print("[DataService] Mode changed to \(isCloudMode ? "CLOUD" : "LOCAL-ONLY")")
        }
    }

    private let localStore = LocalStoreService.shared
    private let localSearch = LocalSearchService.shared

    init() {
        self.isCloudMode = UserDefaults.standard.bool(forKey: "cloudBackupEnabled")
        print("[DataService] Initialized — mode=\(isCloudMode ? "CLOUD" : "LOCAL-ONLY")")
    }

    // MARK: - Chunk Processing

    /// Process a recording chunk — always calls backend, stores locally in local-only mode
    func processChunk(
        _ request: ProcessChunkRequest,
        transcript: String,
        context: ModelContext
    ) async throws -> ChunkProcessResult {
        print("[DataService] processChunk — mode=\(isCloudMode ? "CLOUD" : "LOCAL-ONLY"), session=\(request.recordingSessionId), chunk=\(request.chunkIndex)")
        let result = try await APIService.shared.processChunk(request)

        // Store locally when we get a memory back (finalized or single-chunk)
        if result.memoryId != nil {
            print("[DataService] Storing memory locally — memoryId=\(result.memoryId ?? "nil"), hasEmbedding=\(result.embedding != nil)")
            localStore.storeMemoryFromResult(result, transcript: transcript, context: context)
            // Derived data (commitments, suggestions) now arrives via push notifications
            // and is stored directly in SwiftData — no polling delay needed
        }

        return result
    }

    // MARK: - Chat

    /// Chat with AI — always searches local memories and sends as context
    func chat(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        modelContext: ModelContext? = nil
    ) async throws -> ChatResponse {
        // Always search local memories to send as context (vector search is the source of truth)
        if let ctx = modelContext {
            print("[DataService] chat — searching local memories to send as context")
            let localResults = await localSearch.searchMemories(
                query: message,
                limit: 10,
                context: ctx
            )

            let localPayloads = localResults.map { result in
                LocalMemoryPayload(
                    id: result.memory.serverMemoryId ?? result.memory.id.uuidString,
                    rawTranscript: result.memory.rawTranscript,
                    timestamp: ISO8601DateFormatter().string(from: result.memory.timestamp),
                    topics: result.memory.topics,
                    people: result.memory.people,
                    score: result.score
                )
            }

            print("[DataService] chat — sending \(localPayloads.count) local memories as context (best=\(localPayloads.first?.score ?? 0))")
            return try await APIService.shared.chatWithLocalMemories(
                message: message,
                history: history,
                context: context,
                localMemories: localPayloads
            )
        }

        print("[DataService] chat — no modelContext, calling API without local memories")
        return try await APIService.shared.chat(message: message, history: history, context: context)
    }

    /// Stream chat — always searches local memories and sends as context
    func chatStream(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        chatMode: String = "main",
        modelContext: ModelContext? = nil,
        userName: String? = nil
    ) async throws -> AsyncStream<APIService.ChatStreamEvent> {
        // Always search local memories to send as context
        if let ctx = modelContext {
            print("[DataService] chatStream — searching local memories to send as context")
            let localResults = await localSearch.searchMemories(
                query: message,
                limit: 25,
                threshold: 0.25,  // Backend does fine-grained filtering; send more raw candidates
                context: ctx
            )

            let localPayloads = localResults.map { result in
                LocalMemoryPayload(
                    id: result.memory.serverMemoryId ?? result.memory.id.uuidString,
                    rawTranscript: result.memory.rawTranscript,
                    timestamp: ISO8601DateFormatter().string(from: result.memory.timestamp),
                    topics: result.memory.topics,
                    people: result.memory.people,
                    score: result.score
                )
            }

            print("[DataService] chatStream — sending \(localPayloads.count) local memories as context (best=\(localPayloads.first?.score ?? 0))")
            return try await APIService.shared.chatStreamWithLocalMemories(
                message: message,
                history: history,
                context: context,
                chatMode: chatMode,
                localMemories: localPayloads,
                userName: userName
            )
        }

        print("[DataService] chatStream — no modelContext, calling API without local memories")
        return try await APIService.shared.chatStream(message: message, history: history, context: context, userName: userName)
    }

    // MARK: - Commitments

    /// Get commitments — SwiftData first (local-first), background API sync
    func getCommitments(status: String? = nil, context: ModelContext? = nil) async throws -> CommitmentsResponse {
        print("[DataService] getCommitments — status=\(status ?? "all")")

        // SwiftData first — primary source of truth
        if let ctx = context {
            let local = getLocalCommitments(status: status ?? "pending", context: ctx)
            if !local.isEmpty {
                print("[DataService] Returning \(local.count) commitments from SwiftData")
                // Background sync: refresh from API silently
                Task { await backgroundSyncCommitments(status: status, context: ctx) }
                return CommitmentsResponse(commitments: local.map { $0.toAPICommitment() })
            }
        }

        // SwiftData empty — fetch from API to populate, then return
        let response = try await APIService.shared.getCommitments(status: status)
        if let ctx = context {
            localStore.storeCommitments(response.commitments, context: ctx)
        }
        return response
    }

    /// Get local commitments (for when cloud data has been cleaned up)
    func getLocalCommitments(status: String = "pending", context: ModelContext) -> [LocalCommitment] {
        let predicate = #Predicate<LocalCommitment> { $0.status == status }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Suggestions

    /// Get suggestions — SwiftData first (local-first), background API sync
    func getSuggestions(status: String? = nil, context: ModelContext? = nil) async throws -> SuggestionsResponse {
        print("[DataService] getSuggestions — status=\(status ?? "all")")

        // SwiftData first — primary source of truth (now includes suggestedAction)
        if let ctx = context {
            let local = getLocalSuggestions(status: status ?? "pending", context: ctx)
            if !local.isEmpty {
                print("[DataService] Returning \(local.count) suggestions from SwiftData")
                // Background sync: refresh from API silently
                Task { await backgroundSyncSuggestions(status: status, context: ctx) }
                return SuggestionsResponse(suggestions: local.map { $0.toAPISuggestion() })
            }
        }

        // SwiftData empty — fetch from API to populate, then return
        let response = try await APIService.shared.getSuggestions(status: status)
        if let ctx = context {
            localStore.storeSuggestions(response.suggestions, context: ctx)
        }
        return response
    }

    /// Get local suggestions
    func getLocalSuggestions(status: String = "pending", context: ModelContext) -> [LocalSuggestion] {
        let predicate = #Predicate<LocalSuggestion> { $0.status == status }
        let descriptor = FetchDescriptor(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Briefings

    /// Get briefing — SwiftData first (local-first), background API sync
    func getBriefing(date: Date, context: ModelContext? = nil) async throws -> BriefingResponse {
        print("[DataService] getBriefing — date=\(date)")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let dateStr = formatter.string(from: date)

        // SwiftData first — primary source of truth
        if let ctx = context {
            if let local = getLocalBriefing(date: dateStr, context: ctx) {
                print("[DataService] Returning briefing from SwiftData for \(dateStr)")
                // Background sync: refresh from API silently
                Task { await backgroundSyncBriefing(date: date, context: ctx) }
                return BriefingResponse(briefing: BriefingData(
                    id: nil, userId: nil,
                    date: local.date,
                    summary: local.summary,
                    keyMoments: local.keyMoments,
                    peopleInteracted: local.peopleInteracted,
                    pendingTasks: local.pendingTasks,
                    mood: local.mood,
                    insightfulObservation: local.insightfulObservation,
                    createdAt: nil, updatedAt: nil
                ))
            }
        }

        // SwiftData empty — fetch from API to populate, then return
        let response = try await APIService.shared.getBriefing(date: date)
        if let ctx = context {
            localStore.storeBriefing(response, context: ctx)
        }
        return response
    }

    /// Get local briefing
    func getLocalBriefing(date: String, context: ModelContext) -> LocalBriefing? {
        let predicate = #Predicate<LocalBriefing> { $0.date == date }
        let descriptor = FetchDescriptor(predicate: predicate)
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Memory Search

    /// Search memories — local search in local-only mode, API otherwise
    func searchMemories(
        query: String,
        limit: Int = 10,
        context: ModelContext? = nil
    ) async throws -> SearchResponse {
        if !isCloudMode, let ctx = context {
            print("[DataService] searchMemories — LOCAL-ONLY: using on-device vector search, query=\"\(query.prefix(50))\"")
            let results = await localSearch.searchMemories(
                query: query,
                limit: limit,
                context: ctx
            )
            print("[DataService] Local search returned \(results.count) results")

            return SearchResponse(
                results: results.map { result in
                    SearchResult(
                        memoryId: result.memory.serverMemoryId ?? result.memory.id.uuidString,
                        transcriptSnippet: String(result.memory.rawTranscript.prefix(200)),
                        relevanceScore: Double(result.score),
                        timestamp: ISO8601DateFormatter().string(from: result.memory.timestamp),
                        topics: result.memory.topics
                    )
                },
                totalCount: results.count
            )
        }

        print("[DataService] searchMemories — CLOUD mode, query=\"\(query.prefix(50))\"")
        return try await APIService.shared.searchMemories(query: query, limit: limit)
    }

    // MARK: - Background Sync (non-blocking)

    private func backgroundSyncCommitments(status: String?, context: ModelContext) async {
        do {
            let response = try await APIService.shared.getCommitments(status: status)
            localStore.storeCommitments(response.commitments, context: context)
        } catch {
            // Silent — local data already displayed
        }
    }

    private func backgroundSyncSuggestions(status: String?, context: ModelContext) async {
        do {
            let response = try await APIService.shared.getSuggestions(status: status)
            localStore.storeSuggestions(response.suggestions, context: context)
        } catch {
            // Silent — local data already displayed
        }
    }

    private func backgroundSyncBriefing(date: Date, context: ModelContext) async {
        do {
            let response = try await APIService.shared.getBriefing(date: date)
            localStore.storeBriefing(response, context: context)
        } catch {
            // Silent — local data already displayed
        }
    }

    // MARK: - Manual Refresh

    /// Manually refresh derived data from API (commitments + suggestions)
    /// Primarily used as a fallback if push delivery is missed
    func refreshDerivedData(context: ModelContext) async {
        print("[DataService] Manual refresh of derived data from API...")
        do {
            let commitments = try await APIService.shared.getCommitments(status: "pending")
            localStore.storeCommitments(commitments.commitments, context: context)
            print("[DataService] Refreshed \(commitments.commitments.count) commitments")

            let suggestions = try await APIService.shared.getSuggestions(status: "pending")
            localStore.storeSuggestions(suggestions.suggestions, context: context)
            print("[DataService] Refreshed \(suggestions.suggestions.count) suggestions")
        } catch {
            print("[DataService] Failed to refresh derived data: \(error)")
        }
    }
}

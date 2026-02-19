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
        }
    }

    private let localStore = LocalStoreService.shared
    private let localSearch = LocalSearchService.shared

    init() {
        self.isCloudMode = UserDefaults.standard.bool(forKey: "cloudBackupEnabled")
    }

    // MARK: - Chunk Processing

    /// Process a recording chunk — always calls backend, stores locally in local-only mode
    func processChunk(
        _ request: ProcessChunkRequest,
        transcript: String,
        context: ModelContext
    ) async throws -> ChunkProcessResult {
        let result = try await APIService.shared.processChunk(request)

        // Store locally when we get a memory back (finalized or single-chunk)
        if result.memoryId != nil {
            localStore.storeMemoryFromResult(result, transcript: transcript, context: context)

            // In local-only mode, fetch derived data after a delay (Inngest processing)
            if !isCloudMode {
                Task {
                    try? await Task.sleep(nanoseconds: 12_000_000_000) // 12 seconds
                    await fetchAndStoreDerivedData(context: context)
                }
            }
        }

        return result
    }

    // MARK: - Chat

    /// Chat with AI — supplements with local memories in local-only mode
    func chat(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        modelContext: ModelContext? = nil
    ) async throws -> ChatResponse {
        if !isCloudMode, let ctx = modelContext {
            // Search local memories and send as supplement
            let localResults = await localSearch.searchMemories(
                query: message,
                limit: 5,
                context: ctx
            )

            let localPayloads = localResults.map { result in
                LocalMemoryPayload(
                    id: result.memory.serverMemoryId ?? result.memory.id.uuidString,
                    rawTranscript: result.memory.rawTranscript,
                    timestamp: ISO8601DateFormatter().string(from: result.memory.timestamp),
                    topics: result.memory.topics,
                    people: result.memory.people
                )
            }

            return try await APIService.shared.chatWithLocalMemories(
                message: message,
                history: history,
                context: context,
                localMemories: localPayloads
            )
        }

        return try await APIService.shared.chat(message: message, history: history, context: context)
    }

    /// Stream chat — supplements with local memories in local-only mode
    func chatStream(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        modelContext: ModelContext? = nil
    ) async throws -> AsyncStream<APIService.ChatStreamEvent> {
        if !isCloudMode, let ctx = modelContext {
            let localResults = await localSearch.searchMemories(
                query: message,
                limit: 5,
                context: ctx
            )

            let localPayloads = localResults.map { result in
                LocalMemoryPayload(
                    id: result.memory.serverMemoryId ?? result.memory.id.uuidString,
                    rawTranscript: result.memory.rawTranscript,
                    timestamp: ISO8601DateFormatter().string(from: result.memory.timestamp),
                    topics: result.memory.topics,
                    people: result.memory.people
                )
            }

            return try await APIService.shared.chatStreamWithLocalMemories(
                message: message,
                history: history,
                context: context,
                localMemories: localPayloads
            )
        }

        return try await APIService.shared.chatStream(message: message, history: history, context: context)
    }

    // MARK: - Commitments

    /// Get commitments — from API (always), store locally in local-only mode
    func getCommitments(status: String? = nil, context: ModelContext? = nil) async throws -> CommitmentsResponse {
        let response = try await APIService.shared.getCommitments(status: status)

        // Store locally
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

    /// Get suggestions — from API (always), store locally in local-only mode
    func getSuggestions(status: String? = nil, context: ModelContext? = nil) async throws -> SuggestionsResponse {
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

    /// Get briefing — from API, store locally
    func getBriefing(date: Date, context: ModelContext? = nil) async throws -> BriefingResponse {
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
            let results = await localSearch.searchMemories(
                query: query,
                limit: limit,
                context: ctx
            )

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

        return try await APIService.shared.searchMemories(query: query, limit: limit)
    }

    // MARK: - Derived Data Fetching

    /// After recording in local-only mode, fetch Inngest-generated data and store locally
    private func fetchAndStoreDerivedData(context: ModelContext) async {
        do {
            // Fetch commitments
            let commitments = try await APIService.shared.getCommitments(status: "pending")
            localStore.storeCommitments(commitments.commitments, context: context)

            // Fetch suggestions
            let suggestions = try await APIService.shared.getSuggestions(status: "pending")
            localStore.storeSuggestions(suggestions.suggestions, context: context)
        } catch {
            print("[DataService] Failed to fetch derived data: \(error)")
        }
    }
}

import Foundation
import FirebaseAuth

/// Centralized API Service for communicating with the LisnAI backend
/// Handles authentication, all endpoints, and error handling
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    // MARK: - Configuration

    // Render production URL
    private let baseURL = "https://api.lisnai.com"

    @Published var isConnected = true
    @Published var lastError: APIError?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Authentication

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        Auth.auth().currentUser != nil
    }

    /// Get the current user's Firebase ID token for API authentication
    private func getAuthToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            print("[APIService] ERROR: Auth.auth().currentUser is nil - user not signed in!")
            throw APIError.notAuthenticated
        }

        do {
            let token = try await user.getIDToken()
            print("[APIService] Got auth token for user \(user.uid) (\(token.prefix(20))...)")
            return token
        } catch {
            print("[APIService] Token error: \(error)")
            throw APIError.tokenError(error.localizedDescription)
        }
    }

    /// Create an authenticated URLRequest
    private func createRequest(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil
    ) async throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth token
        let token = try await getAuthToken()
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        // Add cloud sync header
        let cloudSync = UserDefaults.standard.bool(forKey: "cloudBackupEnabled")
        request.setValue(cloudSync ? "true" : "false", forHTTPHeaderField: "X-Cloud-Sync")

        if let body = body {
            request.httpBody = body
        }

        print("[APIService] \(method) \(endpoint) [cloudSync=\(cloudSync)]")
        return request
    }

    /// Execute a request and decode the response
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            print("[APIService] Response: \(httpResponse.statusCode) for \(request.url?.path ?? "?")")

            // Handle error responses
            switch httpResponse.statusCode {
            case 200...299:
                break // Success
            case 401:
                print("[APIService] 401 - Auth rejected by backend")
                throw APIError.notAuthenticated
            case 402:
                // Free window expired — user is past the 10-day free period
                // and must subscribe to continue. Backend body looks like
                // `{ error: "free_window_expired", freeWindowDaysRemaining: -1 }`.
                if let limitResponse = try? decoder.decode(LimitExceededResponse.self, from: data) {
                    let days = limitResponse.freeWindowDaysRemaining ?? -1
                    throw APIError.freeWindowExpired(daysRemaining: days)
                }
                throw APIError.freeWindowExpired(daysRemaining: -1)
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.notFound
            case 429:
                // Usage limit exceeded — daily/monthly cap reached.
                if let limitResponse = try? decoder.decode(LimitExceededResponse.self, from: data) {
                    throw APIError.limitExceeded(
                        resource: limitResponse.resource,
                        used: limitResponse.used,
                        limit: limitResponse.limit,
                        freeWindowDaysRemaining: limitResponse.freeWindowDaysRemaining ?? -1
                    )
                }
                throw APIError.httpError(429, "Rate limit exceeded")
            case 500...599:
                let errorBody = String(data: data, encoding: .utf8) ?? "Server error"
                print("[APIService] Server error: \(errorBody)")
                throw APIError.serverError(httpResponse.statusCode, errorBody)
            default:
                let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.httpError(httpResponse.statusCode, errorBody)
            }

            isConnected = true
            return try decoder.decode(T.self, from: data)

        } catch let error as APIError {
            lastError = error
            throw error
        } catch let error as DecodingError {
            lastError = .decodingError(error.localizedDescription)
            throw APIError.decodingError(error.localizedDescription)
        } catch {
            isConnected = false
            lastError = .networkError(error.localizedDescription)
            throw APIError.networkError(error.localizedDescription)
        }
    }

    // MARK: - Health Check

    func checkHealth() async throws -> HealthResponse {
        let request = try await createRequest(endpoint: "/health", method: "GET")
        return try await execute(request)
    }

    // MARK: - Transcript Processing

    /// Process a transcript through the AI pipeline
    /// Returns memory ID, intent classification, and optional action result
    func processTranscript(_ transcript: String, sessionId: String? = nil) async throws -> ProcessResult {
        let body = ProcessTranscriptRequest(
            transcript: transcript,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            sessionId: sessionId
        )

        var request = try await createRequest(
            endpoint: "/api/transcripts/process",
            method: "POST",
            body: try encoder.encode(body)
        )
        request.timeoutInterval = 180

        return try await execute(request)
    }

    // MARK: - Chunk Processing (multi-chunk recordings)

    /// Process a single chunk of a multi-chunk recording
    /// Handles single-chunk (backward compatible), multi-chunk, and finalization.
    /// Uses a longer timeout (180s) because the backend pipeline runs entity
    /// extraction, summarization, intent classification, and optionally chat —
    /// which can take 60-90s on cold starts or complex recordings.
    func processChunk(_ request: ProcessChunkRequest) async throws -> ChunkProcessResult {
        var apiRequest = try await createRequest(
            endpoint: "/api/transcripts/chunk",
            method: "POST",
            body: try encoder.encode(request)
        )
        apiRequest.timeoutInterval = 180
        return try await execute(apiRequest)
    }

    // MARK: - Chat

    /// Send a message to the RAG-enhanced chat
    func chat(message: String, history: [ChatHistoryItem] = [], context: String? = nil, userName: String? = nil) async throws -> ChatResponse {
        let body = ChatRequest(message: message, history: history, context: context, userName: userName)

        let request = try await createRequest(
            endpoint: "/api/chat",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    /// Payload from a tool_result SSE event
    struct ToolResultPayload: @unchecked Sendable {
        let success: Bool
        let status: String       // "completed", "permission_required", "failed", "error"
        let message: String
        let actionId: String?
        let pendingPermissionId: String?
        let data: [String: Any]? // Enriched params from backend for ActionEditSheet prefilling
    }

    /// SSE event types from the streaming chat endpoint
    enum ChatStreamEvent: Sendable {
        case sources([String])
        case delta(String)
        case toolCall(id: String, skill: String, tool: String, params: [String: Any])
        case toolResult(id: String, skill: String, tool: String, result: ToolResultPayload)
        case stepFinish(finishReason: String)
        case done
        case error(String)
    }

    /// Stream a chat response via SSE, returns an AsyncStream of events
    func chatStream(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        userName: String? = nil
    ) async throws -> AsyncStream<ChatStreamEvent> {
        let body = ChatRequest(message: message, history: history, context: context, userName: userName)
        var request = try await createRequest(
            endpoint: "/api/chat/stream",
            method: "POST",
            body: try encoder.encode(body)
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, "Stream failed with status \(httpResponse.statusCode)")
        }

        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))

                        guard let data = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "sources":
                            if let sources = event["sources"] as? [String] {
                                continuation.yield(.sources(sources))
                            }
                        case "delta":
                            if let text = event["text"] as? String {
                                continuation.yield(.delta(text))
                            }
                        case "tool_call":
                            let id = event["id"] as? String ?? UUID().uuidString
                            let skill = event["skill"] as? String ?? ""
                            let toolName = event["tool"] as? String ?? ""
                            let params = event["params"] as? [String: Any] ?? [:]
                            continuation.yield(.toolCall(id: id, skill: skill, tool: toolName, params: params))
                        case "tool_result":
                            let id = event["id"] as? String ?? UUID().uuidString
                            let skill = event["skill"] as? String ?? ""
                            let toolName = event["tool"] as? String ?? ""
                            let resultDict = event["result"] as? [String: Any] ?? [:]
                            let payload = ToolResultPayload(
                                success: resultDict["success"] as? Bool ?? false,
                                status: resultDict["status"] as? String ?? "error",
                                message: resultDict["message"] as? String ?? "",
                                actionId: resultDict["actionId"] as? String,
                                pendingPermissionId: resultDict["pendingPermissionId"] as? String,
                                data: resultDict["data"] as? [String: Any]
                            )
                            continuation.yield(.toolResult(id: id, skill: skill, tool: toolName, result: payload))
                        case "step_finish":
                            let reason = event["finishReason"] as? String ?? ""
                            continuation.yield(.stepFinish(finishReason: reason))
                        case "done":
                            continuation.yield(.done)
                        case "error":
                            let errorMsg = event["error"] as? String ?? "Unknown stream error"
                            continuation.yield(.error(errorMsg))
                        default:
                            break
                        }
                    }
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Memories

    /// Get memories with optional filters
    func getMemories(
        dateFrom: Date? = nil,
        dateTo: Date? = nil,
        topic: String? = nil,
        limit: Int = 50
    ) async throws -> MemoriesResponse {
        var queryItems: [String] = ["limit=\(limit)"]

        if let dateFrom = dateFrom {
            queryItems.append("dateFrom=\(ISO8601DateFormatter().string(from: dateFrom))")
        }
        if let dateTo = dateTo {
            queryItems.append("dateTo=\(ISO8601DateFormatter().string(from: dateTo))")
        }
        if let topic = topic {
            queryItems.append("topic=\(topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic)")
        }

        let query = queryItems.isEmpty ? "" : "?\(queryItems.joined(separator: "&"))"
        let request = try await createRequest(endpoint: "/api/memories\(query)")

        return try await execute(request)
    }

    /// Search memories semantically
    func searchMemories(query: String, limit: Int = 10) async throws -> SearchResponse {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let request = try await createRequest(
            endpoint: "/api/memories/search?query=\(encodedQuery)&limit=\(limit)"
        )

        return try await execute(request)
    }

    /// Get a single memory by ID
    func getMemory(id: String) async throws -> Memory {
        let request = try await createRequest(endpoint: "/api/memories/\(id)")
        let wrapper: MemoryWrapper = try await execute(request)
        return wrapper.memory
    }

    // MARK: - Actions

    /// Get pending actions that need to be executed on iOS
    func getPendingActions() async throws -> PendingActionsResponse {
        let request = try await createRequest(endpoint: "/api/actions/pending")
        return try await execute(request)
    }

    /// Mark an action as completed
    func completeAction(actionId: String, result: ActionCompletionResult? = nil) async throws -> ActionCompletionResponse {
        let body = ActionCompletionRequest(
            status: result?.status ?? "completed",
            result: result?.result,
            error: result?.error
        )

        let request = try await createRequest(
            endpoint: "/api/actions/\(actionId)/complete",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    // MARK: - User / Survey

    /// Submit onboarding survey responses.
    /// Backend stores them in users.survey_responses (JSONB) for growth analytics.
    func submitSurvey(_ payload: [String: Any]) async throws {
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let request = try await createRequest(
            endpoint: "/api/users/me/survey",
            method: "POST",
            body: bodyData
        )
        // Fire-and-forget — we don't need to decode the response
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIError.httpError(http.statusCode, "Survey submit failed")
        }
    }

    // MARK: - API Keys (Gateway)

    /// Generate a new API key for MCP gateway access
    func generateApiKey(name: String) async throws -> ApiKeyResponse {
        let body = ["name": name]
        let request = try await createRequest(
            endpoint: "/api/keys/generate",
            method: "POST",
            body: try encoder.encode(body)
        )
        return try await execute(request)
    }

    /// List active API keys
    func getApiKeys() async throws -> ApiKeyListResponse {
        let request = try await createRequest(endpoint: "/api/keys")
        return try await execute(request)
    }

    /// Revoke an API key
    func revokeApiKey(keyId: String) async throws -> ApiKeyRevokeResponse {
        let request = try await createRequest(
            endpoint: "/api/keys/\(keyId)",
            method: "DELETE"
        )
        return try await execute(request)
    }

    // MARK: - Permissions

    /// Get all permission rules
    func getPermissionRules() async throws -> PermissionRulesResponse {
        let request = try await createRequest(endpoint: "/api/permissions")
        return try await execute(request)
    }

    /// Get pending permission requests
    func getPendingPermissions() async throws -> PendingPermissionsResponse {
        let request = try await createRequest(endpoint: "/api/permissions/pending")
        return try await execute(request)
    }

    /// Approve a pending permission
    func approvePermission(
        permissionId: String,
        scope: PermissionScope = .once,
        createRule: Bool = false
    ) async throws -> PermissionResolutionResponse {
        let body = PermissionApprovalRequest(
            scope: scope.rawValue,
            createRule: createRule
        )

        let request = try await createRequest(
            endpoint: "/api/permissions/pending/\(permissionId)/approve",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    /// Deny a pending permission
    func denyPermission(permissionId: String, note: String? = nil) async throws -> PermissionResolutionResponse {
        let body = PermissionDenialRequest(note: note)

        let request = try await createRequest(
            endpoint: "/api/permissions/pending/\(permissionId)/deny",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    /// Delete a permission rule
    func deletePermissionRule(ruleId: String) async throws -> EmptyResponse {
        let request = try await createRequest(
            endpoint: "/api/permissions/\(ruleId)",
            method: "DELETE"
        )
        return try await execute(request)
    }

    // MARK: - Notifications

    /// Register FCM token for push notifications
    func registerFCMToken(token: String, deviceId: String) async throws -> EmptyResponse {
        let body = FCMRegistrationRequest(
            token: token,
            deviceId: deviceId,
            platform: "ios"
        )

        let request = try await createRequest(
            endpoint: "/api/notifications/register",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    /// Register APNs token for direct push notifications (bypasses FCM)
    func registerAPNsToken(token: String, deviceId: String) async throws -> EmptyResponse {
        let body = APNsRegistrationRequest(
            token: token,
            deviceId: deviceId,
            platform: "ios",
            environment: isDebugBuild ? "sandbox" : "production"
        )

        let request = try await createRequest(
            endpoint: "/api/notifications/apns/register",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    /// Update notification preferences
    func updateNotificationPreferences(_ preferences: NotificationPreferencesRequest) async throws -> EmptyResponse {
        let request = try await createRequest(
            endpoint: "/api/notifications/preferences",
            method: "PUT",
            body: try encoder.encode(preferences)
        )

        return try await execute(request)
    }

    /// Get notification preferences
    func getNotificationPreferences() async throws -> NotificationPreferencesResponse {
        let request = try await createRequest(endpoint: "/api/notifications/preferences")
        return try await execute(request)
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: - Commitments

    /// Get commitments with optional status filter
    func getCommitments(status: String? = nil) async throws -> CommitmentsResponse {
        let query = status != nil ? "?status=\(status!)" : ""
        let request = try await createRequest(endpoint: "/api/commitments\(query)")
        return try await execute(request)
    }

    /// Mark a commitment as completed
    func completeCommitment(commitmentId: String) async throws -> EmptyResponse {
        let request = try await createRequest(
            endpoint: "/api/commitments/\(commitmentId)/complete",
            method: "POST"
        )
        return try await execute(request)
    }

    // MARK: - Briefings

    /// Get daily briefing for a date
    func getBriefing(date: Date) async throws -> BriefingResponse {
        let dateString = ISO8601DateFormatter().string(from: date).prefix(10)
        let request = try await createRequest(endpoint: "/api/briefings/\(dateString)")
        return try await execute(request)
    }

    /// Trigger manual briefing generation for a specific date
    func triggerBriefing(date: Date? = nil) async throws -> BriefingResponse {
        var bodyData: Data? = nil
        if let date = date {
            let dateString = ISO8601DateFormatter().string(from: date).prefix(10).description
            bodyData = try? JSONEncoder().encode(["date": dateString])
        }
        let request = try await createRequest(
            endpoint: "/api/briefings/trigger",
            method: "POST",
            body: bodyData
        )
        return try await execute(request)
    }

    // MARK: - User Profile

    /// Get current user info
    func getCurrentUser() async throws -> UserResponse {
        let request = try await createRequest(endpoint: "/api/me")
        return try await execute(request)
    }

    // MARK: - Proactive Suggestions

    /// Get proactive suggestions
    func getSuggestions(status: String? = nil) async throws -> SuggestionsResponse {
        let query = status != nil ? "?status=\(status!)" : ""
        let request = try await createRequest(endpoint: "/api/suggestions\(query)")
        return try await execute(request)
    }

    /// Accept a suggestion
    func acceptSuggestion(suggestionId: String) async throws -> SuggestionAcceptResponse {
        let request = try await createRequest(
            endpoint: "/api/suggestions/\(suggestionId)/accept",
            method: "POST"
        )
        return try await execute(request)
    }

    /// Dismiss a suggestion
    func dismissSuggestion(suggestionId: String) async throws -> EmptyResponse {
        let request = try await createRequest(
            endpoint: "/api/suggestions/\(suggestionId)/dismiss",
            method: "POST"
        )
        return try await execute(request)
    }

    /// Trigger manual suggestion generation
    func triggerSuggestions() async throws -> EmptyResponse {
        let request = try await createRequest(
            endpoint: "/api/suggestions/trigger",
            method: "POST"
        )
        return try await execute(request)
    }

    // MARK: - Recording Insights

    /// Get paginated list of recording insights
    func getInsights(limit: Int = 20, offset: Int = 0) async throws -> RecordingInsightListResponse {
        let request = try await createRequest(
            endpoint: "/api/transcripts/insights?limit=\(limit)&offset=\(offset)"
        )
        return try await execute(request)
    }

    /// Get a single insight by ID
    func getInsight(id: String) async throws -> RecordingInsightDetailResponse {
        let request = try await createRequest(
            endpoint: "/api/transcripts/insights/\(id)"
        )
        return try await execute(request)
    }

    // MARK: - Subscription

    /// Get subscription status and usage from backend
    func getSubscriptionStatus() async throws -> SubscriptionStatusResponse {
        let request = try await createRequest(endpoint: "/api/subscription")
        return try await execute(request)
    }

    /// Check rich recording permission state before the user taps record.
    /// Returns whether recording is allowed, daily budget, overage availability,
    /// and the hard-stop minute mark.
    func getRecordingPermission() async throws -> RecordingPermissionResponse {
        let request = try await createRequest(endpoint: "/api/recording/permission")
        return try await execute(request)
    }

    /// Send an App Store transaction JWS to the backend for verification and
    /// immediate tier upgrade. Backend validates the signature, decodes the
    /// product ID, and upserts the subscription.
    @discardableResult
    func verifyAppStoreTransaction(jws: String) async throws -> AppStoreVerifyResponse {
        struct Body: Encodable { let signedTransactionJWS: String }
        let body = try encoder.encode(Body(signedTransactionJWS: jws))
        let request = try await createRequest(
            endpoint: "/api/subscription/verify-apple-transaction",
            method: "POST",
            body: body
        )
        return try await execute(request)
    }

    // MARK: - Account Deletion

    func deleteAccount() async throws {
        let request = try await createRequest(
            endpoint: "/api/account",
            method: "DELETE"
        )
        let _: EmptyResponse = try await execute(request)
    }

    // MARK: - Embedding Proxy

    /// Generate an embedding vector for local search
    func generateEmbedding(text: String) async throws -> [Float] {
        let body = EmbedRequest(text: text)
        let request = try await createRequest(
            endpoint: "/api/embed",
            method: "POST",
            body: try encoder.encode(body)
        )
        let response: EmbedResponse = try await execute(request)
        return response.embedding
    }

    // MARK: - Chat with Local Memories

    /// Send a chat message with supplementary local memories
    func chatWithLocalMemories(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        chatMode: String = "main",
        localMemories: [LocalMemoryPayload] = [],
        userName: String? = nil
    ) async throws -> ChatResponse {
        let body = ChatRequestWithLocal(
            message: message,
            history: history,
            context: context,
            chatMode: chatMode,
            userName: userName,
            localMemories: localMemories.isEmpty ? nil : localMemories
        )

        let request = try await createRequest(
            endpoint: "/api/chat",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    /// Stream chat with local memories supplement
    func chatStreamWithLocalMemories(
        message: String,
        history: [ChatHistoryItem] = [],
        context: String? = nil,
        chatMode: String = "main",
        localMemories: [LocalMemoryPayload] = [],
        userName: String? = nil
    ) async throws -> AsyncStream<ChatStreamEvent> {
        let body = ChatRequestWithLocal(
            message: message,
            history: history,
            context: context,
            chatMode: chatMode,
            userName: userName,
            localMemories: localMemories.isEmpty ? nil : localMemories
        )

        var request = try await createRequest(
            endpoint: "/api/chat/stream",
            method: "POST",
            body: try encoder.encode(body)
        )
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw APIError.serverError(httpResponse.statusCode, "Stream failed with status \(httpResponse.statusCode)")
        }

        return AsyncStream { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))

                        guard let data = jsonStr.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }

                        switch type {
                        case "sources":
                            if let sources = event["sources"] as? [String] {
                                continuation.yield(.sources(sources))
                            }
                        case "delta":
                            if let text = event["text"] as? String {
                                continuation.yield(.delta(text))
                            }
                        case "tool_call":
                            let id = event["id"] as? String ?? UUID().uuidString
                            let skill = event["skill"] as? String ?? ""
                            let toolName = event["tool"] as? String ?? ""
                            let params = event["params"] as? [String: Any] ?? [:]
                            continuation.yield(.toolCall(id: id, skill: skill, tool: toolName, params: params))
                        case "tool_result":
                            let id = event["id"] as? String ?? UUID().uuidString
                            let skill = event["skill"] as? String ?? ""
                            let toolName = event["tool"] as? String ?? ""
                            let resultDict = event["result"] as? [String: Any] ?? [:]
                            let payload = ToolResultPayload(
                                success: resultDict["success"] as? Bool ?? false,
                                status: resultDict["status"] as? String ?? "error",
                                message: resultDict["message"] as? String ?? "",
                                actionId: resultDict["actionId"] as? String,
                                pendingPermissionId: resultDict["pendingPermissionId"] as? String,
                                data: resultDict["data"] as? [String: Any]
                            )
                            continuation.yield(.toolResult(id: id, skill: skill, tool: toolName, result: payload))
                        case "step_finish":
                            let reason = event["finishReason"] as? String ?? ""
                            continuation.yield(.stepFinish(finishReason: reason))
                        case "done":
                            continuation.yield(.done)
                        case "error":
                            let errorMsg = event["error"] as? String ?? "Unknown stream error"
                            continuation.yield(.error(errorMsg))
                        default:
                            break
                        }
                    }
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

// MARK: - Request Types

struct ProcessTranscriptRequest: Codable {
    let transcript: String
    let timestamp: String
    let sessionId: String?
}

struct LiveSuggestion: Codable {
    let type: String           // "action" or "context"
    let title: String
    let body: String
    let actionSkill: String?
    let actionParams: [String: AnyCodable]?
    let dismissable: Bool
    let expiresIn: Int         // seconds (default 120)
}

// MARK: - Recording Insight

struct RecordingInsightResponse: Codable {
    let setting: String
    let mood: String?
    let thirdPersonTake: String
    let correlations: [InsightCorrelation]?
    let actionableIdeas: [String]?
    let settingEmoji: String?

    struct InsightCorrelation: Codable {
        let memoryDate: String
        let connection: String
    }
}

struct RecordingInsightListResponse: Codable {
    let insights: [RecordingInsightDetail]
}

struct RecordingInsightDetail: Codable, Identifiable {
    let id: String
    let userId: String?
    let recordingSessionId: String?
    let setting: String
    let settingEmoji: String?
    let mood: String?
    let thirdPersonTake: String
    let correlations: [RecordingInsightResponse.InsightCorrelation]?
    let actionableIdeas: [String]?
    let createdAt: String?
}

struct RecordingInsightDetailResponse: Codable {
    let insight: RecordingInsightDetail
}

struct ProcessChunkRequest: Codable {
    let recordingSessionId: String
    let chunkIndex: Int
    let transcript: String
    let isFinal: Bool
    let timestamp: String?
    let chunkStartTime: Double?
    let chunkEndTime: Double?
    let contextMemories: [LocalMemoryPayload]?
}

struct ChunkProcessResult: Codable {
    let recordingSessionId: String
    let chunkIndex: Int
    let memoryId: String?
    let sessionId: String?
    let title: String?
    let summary: String?
    let icon: String?
    let rollingSummary: String?
    let status: String // "processed", "finalized", "single"
    let liveSuggestion: LiveSuggestion?
    let insight: RecordingInsightResponse?
    let embedding: [Float]?
    // For single-chunk backward compatibility
    let chatResponse: String?

    enum CodingKeys: String, CodingKey {
        case recordingSessionId, chunkIndex, memoryId, sessionId
        case title, summary, icon, rollingSummary, status, liveSuggestion, insight, embedding, chatResponse
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordingSessionId = try container.decode(String.self, forKey: .recordingSessionId)
        chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
        memoryId = try container.decodeIfPresent(String.self, forKey: .memoryId)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        rollingSummary = try container.decodeIfPresent(String.self, forKey: .rollingSummary)
        status = try container.decode(String.self, forKey: .status)
        liveSuggestion = try container.decodeIfPresent(LiveSuggestion.self, forKey: .liveSuggestion)
        insight = try container.decodeIfPresent(RecordingInsightResponse.self, forKey: .insight)
        embedding = try container.decodeIfPresent([Float].self, forKey: .embedding)
        chatResponse = try container.decodeIfPresent(String.self, forKey: .chatResponse)
    }
}

struct ChatRequest: Codable {
    let message: String
    let history: [ChatHistoryItem]
    let context: String?
    let userName: String?
}

struct ChatRequestWithLocal: Codable {
    let message: String
    let history: [ChatHistoryItem]
    let context: String?
    let chatMode: String?      // "main" or "conversation"
    let userName: String?
    let localMemories: [LocalMemoryPayload]?
}

struct LocalMemoryPayload: Codable {
    let id: String
    let rawTranscript: String
    let timestamp: String
    let topics: [String]?
    let people: [String]?
    let score: Float?
}

struct EmbedRequest: Codable {
    let text: String
}

struct EmbedResponse: Codable {
    let embedding: [Float]
}

struct ChatHistoryItem: Codable {
    let role: String
    let content: String
}

struct ActionCompletionRequest: Codable {
    let status: String
    let result: String?
    let error: String?
}

struct ActionCompletionResult {
    let status: String
    let result: String?
    let error: String?
}

struct PermissionApprovalRequest: Codable {
    let scope: String
    let createRule: Bool
}

struct PermissionDenialRequest: Codable {
    let note: String?
}

struct FCMRegistrationRequest: Codable {
    let token: String
    let deviceId: String
    let platform: String
}

struct APNsRegistrationRequest: Codable {
    let token: String
    let deviceId: String
    let platform: String
    let environment: String // "sandbox" or "production"
}

struct NotificationPreferencesRequest: Codable {
    let enabled: Bool?
    let quietHoursStart: Int?
    let quietHoursEnd: Int?
    let maxPerDay: Int?
    let minIntervalMinutes: Int?
    let dailyBriefingEnabled: Bool?
    let suggestionsEnabled: Bool?
    let commitmentRemindersEnabled: Bool?
}

struct NotificationPreferencesResponse: Codable {
    let preferences: NotificationPreferences
}

struct NotificationPreferences: Codable {
    let enabled: Bool
    let quietHoursStart: Int
    let quietHoursEnd: Int
    let maxPerDay: Int
    let minIntervalMinutes: Int
    let dailyBriefingEnabled: Bool?
    let suggestionsEnabled: Bool?
    let commitmentRemindersEnabled: Bool?
}

// MARK: - Response Types

struct HealthResponse: Codable {
    let status: String
    let checks: HealthChecks?
    let timestamp: String?
}

struct HealthChecks: Codable {
    let server: Bool?
    let litellm: Bool?
    let qdrant: Bool?
}

struct ProcessResult: Codable {
    let memoryId: String
    let sessionId: String
    let title: String?
    let summary: String?
    let icon: String?
    let intent: IntentResult
    let actionResult: ActionResult?
    let chatResponse: String?
}

struct IntentResult: Codable {
    let intent: String
    let subIntent: String?
    let confidence: Double
    let urgency: String?
    let requiresConfirmation: Bool?
}

struct ActionResult: Codable {
    let executed: Bool
    let toolName: String?
    let toolResult: ToolResult?
    let error: String?
    let permissionRequired: Bool
    let pendingPermissionId: String?
    let permissionMessage: String?
}

struct ToolResult: Codable {
    let success: Bool
    let message: String
    let actionId: String?
    let iosDeepLink: String?
}

struct ChatResponse: Codable {
    let response: String
    let sources: [String]?
}

struct MemoriesResponse: Codable {
    let memories: [Memory]
    let total: Int?
    let limit: Int?
    let offset: Int?
}

struct MemoryWrapper: Codable {
    let memory: Memory
}

struct Memory: Codable {
    let id: String
    let userId: String?
    let timestamp: String
    let rawTranscript: String?
    let transcript: String?
    let topics: [String]?
    let importanceScore: Double?
    let sessionId: String?

    /// Returns the transcript text regardless of which field the backend uses
    var transcriptText: String {
        rawTranscript ?? transcript ?? ""
    }
}

struct SearchResponse: Codable {
    let results: [SearchResult]
    let totalCount: Int?
}

struct SearchResult: Codable {
    let memoryId: String
    let transcriptSnippet: String
    let relevanceScore: Double
    let timestamp: String?
    let topics: [String]?
}

struct PendingActionsResponse: Codable {
    let actions: [PendingAction]
}

struct PendingAction: Codable, Identifiable {
    let id: String
    let skill: String?
    let tool: String?
    let type: String?
    let params: [String: AnyCodable]?
    let status: String
    let createdAt: String?

    /// Display name for the action type
    var displayType: String {
        if let skill = skill, let tool = tool {
            return "\(skill):\(tool)"
        }
        return type ?? skill ?? tool ?? "unknown"
    }
}

struct PermissionRulesResponse: Codable {
    let rules: [PermissionRule]
}

struct PermissionRule: Codable, Identifiable {
    let id: String
    let pattern: String
    let matchMode: String
    let scope: String
    let description: String?
    let enabled: Bool?
    let createdAt: String?
    let userId: String?
    let createdBy: String?
}

struct PendingPermissionsResponse: Codable {
    let pending: [PendingPermission]
}

struct PendingPermission: Codable, Identifiable {
    let id: String
    let skill: String
    let tool: String
    let params: [String: AnyCodable]?
    let displayTitle: String
    let displayDescription: String
    let displayRisk: String?
    let expiresAt: String
    let status: String
    let createdAt: String
    // Additional fields that backend might return
    let userId: String?
    let sessionId: String?
    let transcript: String?
    let grantedScope: String?
}

struct PermissionResolutionResponse: Codable {
    let success: Bool
    let message: String?
    let pendingPermission: PendingPermission?
    let createdRule: PermissionRule?
}

struct ActionCompletionResponse: Codable {
    let status: String
}

struct CommitmentsResponse: Codable {
    let commitments: [Commitment]
}

struct Commitment: Codable, Identifiable {
    let id: String
    let description: String
    let type: String
    let person: String?
    let dueDate: String?
    let urgency: String
    let status: String
    let createdAt: String
}

struct BriefingResponse: Codable {
    let briefing: BriefingData?

    // Direct properties for backwards compatibility
    var date: String { briefing?.date ?? "" }
    var summary: String { briefing?.summary ?? "" }
    var keyMoments: [String] { briefing?.keyMoments ?? [] }
    var peopleInteracted: [String]? { briefing?.peopleInteracted }
    var pendingTasks: [String]? { briefing?.pendingTasks }
    var mood: String? { briefing?.mood }
    var insightfulObservation: String? { briefing?.insightfulObservation }
}

struct BriefingData: Codable {
    let id: String?
    let userId: String?
    let date: String
    let summary: String?
    let keyMoments: [String]?
    let peopleInteracted: [String]?
    let pendingTasks: [String]?
    let mood: String?
    let insightfulObservation: String?
    let createdAt: String?
    let updatedAt: String?
}

struct UserResponse: Codable {
    let uid: String
    let email: String?
    let emailVerified: Bool
}

struct SuggestionsResponse: Codable {
    let suggestions: [ProactiveSuggestion]
}

struct ProactiveSuggestion: Codable, Identifiable {
    let id: String
    let type: String
    let title: String
    let body: String
    let confidence: Double
    let reasoning: String
    let suggestedAction: SuggestedAction?
    let basedOnMemoryIds: [String]?
    let status: String
    let createdAt: String
}

struct SuggestedAction: Codable {
    let skill: String
    let tool: String
    let params: [String: AnyCodable]
}

struct SuggestionAcceptResponse: Codable {
    let success: Bool
    let suggestedAction: SuggestedAction?
}

struct EmptyResponse: Codable {}

// MARK: - API Keys (Gateway)

struct ApiKeyResponse: Codable {
    let id: String
    let name: String
    let key: String  // Raw key — only returned on generation
    let keyPrefix: String
    let createdAt: String
}

struct ApiKeyListItem: Codable, Identifiable {
    let id: String
    let name: String
    let keyPrefix: String
    let lastUsedAt: String?
    let createdAt: String
}

struct ApiKeyListResponse: Codable {
    let keys: [ApiKeyListItem]
}

struct ApiKeyRevokeResponse: Codable {
    let revoked: Bool
    let id: String
}

// MARK: - Permission Scope

enum PermissionScope: String, Codable, CaseIterable {
    case once = "once"
    case session = "session"
    case always = "always"

    var displayName: String {
        switch self {
        case .once: return "Just this once"
        case .session: return "For this session"
        case .always: return "Always allow"
        }
    }
}

// MARK: - API Errors

enum APIError: LocalizedError {
    case notAuthenticated
    case tokenError(String)
    case invalidURL
    case invalidResponse
    case forbidden
    case notFound
    case limitExceeded(resource: String, used: Int, limit: Int, freeWindowDaysRemaining: Int)
    /// Thrown when the backend returns HTTP 402 with `error: "free_window_expired"`.
    /// The caller should present `PaywallView` modally and refresh subscription state.
    case freeWindowExpired(daysRemaining: Int)
    case serverError(Int, String)
    case httpError(Int, String)
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Please sign in to continue"
        case .tokenError(let message):
            return "Authentication error: \(message)"
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .forbidden:
            return "You don't have permission to perform this action"
        case .notFound:
            return "Resource not found"
        case .limitExceeded(let resource, let used, let limit, _):
            return "You've used \(used)/\(limit) \(resource). Upgrade to continue."
        case .freeWindowExpired:
            return "Your 10-day free window has ended. Subscribe to keep using Lisn."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .httpError(let code, let message):
            return "Request failed (\(code)): \(message)"
        case .decodingError(let message):
            return "Failed to parse response: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - AnyCodable Helper

/// Helper type for handling dynamic JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var doubleValue: Double? { value as? Double }
    var boolValue: Bool? { value as? Bool }
}

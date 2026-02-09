import Foundation
import FirebaseAuth

/// Centralized API Service for communicating with the LisnAI backend
/// Handles authentication, all endpoints, and error handling
@MainActor
class APIService: ObservableObject {
    static let shared = APIService()

    // MARK: - Configuration

    // Render production URL
    private let baseURL = "https://backend-test-8pbt.onrender.com"

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
            throw APIError.notAuthenticated
        }

        do {
            let token = try await user.getIDToken()
            return token
        } catch {
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

        if let body = body {
            request.httpBody = body
        }

        return request
    }

    /// Execute a request and decode the response
    private func execute<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Handle error responses
            switch httpResponse.statusCode {
            case 200...299:
                break // Success
            case 401:
                throw APIError.notAuthenticated
            case 403:
                throw APIError.forbidden
            case 404:
                throw APIError.notFound
            case 500...599:
                let errorBody = String(data: data, encoding: .utf8) ?? "Server error"
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

        let request = try await createRequest(
            endpoint: "/api/transcripts/process",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
    }

    // MARK: - Chat

    /// Send a message to the RAG-enhanced chat
    func chat(message: String, history: [ChatHistoryItem] = []) async throws -> ChatResponse {
        let body = ChatRequest(message: message, history: history)

        let request = try await createRequest(
            endpoint: "/api/chat",
            method: "POST",
            body: try encoder.encode(body)
        )

        return try await execute(request)
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
        return try await execute(request)
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

    /// Trigger manual briefing generation
    func triggerBriefing() async throws -> EmptyResponse {
        let request = try await createRequest(
            endpoint: "/api/briefings/trigger",
            method: "POST"
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
}

// MARK: - Request Types

struct ProcessTranscriptRequest: Codable {
    let transcript: String
    let timestamp: String
    let sessionId: String?
}

struct ChatRequest: Codable {
    let message: String
    let history: [ChatHistoryItem]
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
}

struct Memory: Codable {
    let id: String
    let userId: String
    let timestamp: String
    let rawTranscript: String
    let topics: [String]?
    let importanceScore: Double?
    let sessionId: String?
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
    let type: String
    let params: [String: AnyCodable]
    let status: String
    let createdAt: String
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

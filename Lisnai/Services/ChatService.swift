import Foundation
import SwiftData

/// Service for AI chat with tool calling
/// Tools execute locally (query SwiftData), LLM calls go through backend
@MainActor
class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let modelContext: ModelContext

    // Backend URL - change for production
    #if DEBUG
    private let baseURL = "http://192.168.1.10:3000"  // Your Mac's local IP
    #else
    private let baseURL = "https://backend-ylzv.onrender.com"
    #endif

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    func sendMessage(_ content: String) async {
        // Add user message
        let userMessage = ChatMessage(content: content, isUser: true)
        messages.append(userMessage)
        modelContext.insert(userMessage)

        isLoading = true
        error = nil

        do {
            let response = try await chat(userMessage: content)

            // Add assistant message
            let assistantMessage = ChatMessage(content: response, isUser: false)
            messages.append(assistantMessage)
            modelContext.insert(assistantMessage)

            try modelContext.save()
        } catch {
            self.error = error.localizedDescription
            print("Chat error: \(error)")
        }

        isLoading = false
    }

    func clearHistory() {
        messages.removeAll()
    }

    func loadHistory() {
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        do {
            messages = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to load chat history: \(error)")
        }
    }

    // MARK: - Chat with Tool Calling

    private func chat(userMessage: String) async throws -> String {
        // Build conversation history for context
        var conversationHistory: [[String: String]] = []
        for message in messages.suffix(10) {  // Last 10 messages for context
            conversationHistory.append([
                "role": message.isUser ? "user" : "assistant",
                "content": message.content
            ])
        }

        // First, ask backend if tools are needed
        let toolRequest = ChatRequest(
            message: userMessage,
            conversationHistory: conversationHistory,
            toolResults: nil,
            pendingToolCalls: nil
        )

        var response = try await callBackend(request: toolRequest)

        // Handle tool calls in a loop
        while let toolCalls = response.toolCalls, !toolCalls.isEmpty {
            // Execute tools locally
            var toolResults: [ToolResult] = []
            for toolCall in toolCalls {
                let result = await executeToolLocally(toolCall)
                toolResults.append(ToolResult(
                    toolCallId: toolCall.id,
                    result: result
                ))
            }

            // Send tool results back to backend (include the tool calls that triggered them)
            let followUpRequest = ChatRequest(
                message: userMessage,
                conversationHistory: conversationHistory,
                toolResults: toolResults,
                pendingToolCalls: toolCalls  // Include the original tool calls
            )

            response = try await callBackend(request: followUpRequest)
        }

        return response.content ?? "I couldn't generate a response."
    }

    // MARK: - Backend Communication

    private func callBackend(request: ChatRequest) async throws -> ChatResponse {
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw ChatError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // TODO: Add auth token when Firebase Auth is implemented
        // urlRequest.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")

        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, httpResponse) = try await URLSession.shared.data(for: urlRequest)

        guard let response = httpResponse as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        guard response.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ChatError.apiError(statusCode: response.statusCode, message: errorBody)
        }

        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    // MARK: - Local Tool Execution

    private func executeToolLocally(_ toolCall: ToolCallResponse) async -> String {
        let name = toolCall.name

        switch name {
        case "get_summary":
            guard let dateString = toolCall.arguments["date"] else {
                return "Error: Missing date parameter"
            }
            return await getSummary(dateString: dateString)

        case "get_transcription":
            guard let dateString = toolCall.arguments["date"] else {
                return "Error: Missing date parameter"
            }
            return await getTranscription(dateString: dateString)

        case "list_recordings":
            guard let startDate = toolCall.arguments["start_date"],
                  let endDate = toolCall.arguments["end_date"] else {
                return "Error: Missing date parameters"
            }
            return await listRecordings(startDate: startDate, endDate: endDate)

        case "search_transcriptions":
            guard let query = toolCall.arguments["query"] else {
                return "Error: Missing query parameter"
            }
            return await searchTranscriptions(query: query)

        default:
            return "Error: Unknown tool '\(name)'"
        }
    }

    // MARK: - Tool Implementations (Query Local SwiftData)

    private func getSummary(dateString: String) async -> String {
        guard let date = parseDate(dateString) else {
            return "Could not parse date: \(dateString)"
        }

        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<Summary> { summary in
            summary.date >= startOfDay && summary.date < endOfDay
        }

        let descriptor = FetchDescriptor<Summary>(predicate: predicate)

        do {
            let summaries = try modelContext.fetch(descriptor)
            if summaries.isEmpty {
                return "No recordings found for \(dateString)"
            }
            return summaries.map { $0.text }.joined(separator: "\n\n")
        } catch {
            return "Error fetching summaries: \(error.localizedDescription)"
        }
    }

    private func getTranscription(dateString: String) async -> String {
        guard let date = parseDate(dateString) else {
            return "Could not parse date: \(dateString)"
        }

        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = #Predicate<Transcription> { transcription in
            transcription.date >= startOfDay && transcription.date < endOfDay
        }

        let descriptor = FetchDescriptor<Transcription>(predicate: predicate)

        do {
            let transcriptions = try modelContext.fetch(descriptor)
            if transcriptions.isEmpty {
                return "No transcriptions found for \(dateString)"
            }
            return transcriptions.map { $0.text }.joined(separator: "\n\n---\n\n")
        } catch {
            return "Error fetching transcriptions: \(error.localizedDescription)"
        }
    }

    private func listRecordings(startDate: String, endDate: String) async -> String {
        guard let start = parseDate(startDate),
              let end = parseDate(endDate) else {
            return "Could not parse dates"
        }

        let startOfStart = Calendar.current.startOfDay(for: start)
        let endOfEnd = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: end))!

        let predicate = #Predicate<Recording> { recording in
            recording.date >= startOfStart && recording.date < endOfEnd
        }

        let descriptor = FetchDescriptor<Recording>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        do {
            let recordings = try modelContext.fetch(descriptor)
            if recordings.isEmpty {
                return "No recordings found between \(startDate) and \(endDate)"
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .medium

            var result = "Found \(recordings.count) recording(s):\n"
            for recording in recordings {
                result += "- \(formatter.string(from: recording.date)): \(recording.formattedDuration)\n"
            }
            return result
        } catch {
            return "Error fetching recordings: \(error.localizedDescription)"
        }
    }

    private func searchTranscriptions(query: String) async -> String {
        let lowercaseQuery = query.lowercased()

        let descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        do {
            let transcriptions = try modelContext.fetch(descriptor)
            let matches = transcriptions.filter {
                $0.text.lowercased().contains(lowercaseQuery)
            }

            if matches.isEmpty {
                return "No transcriptions found containing '\(query)'"
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .medium

            var result = "Found \(matches.count) match(es) for '\(query)':\n\n"
            for match in matches.prefix(5) {
                result += "[\(formatter.string(from: match.date))]:\n"
                if let range = match.text.lowercased().range(of: lowercaseQuery) {
                    let startIndex = match.text.index(range.lowerBound, offsetBy: -50, limitedBy: match.text.startIndex) ?? match.text.startIndex
                    let endIndex = match.text.index(range.upperBound, offsetBy: 50, limitedBy: match.text.endIndex) ?? match.text.endIndex
                    result += "...\(match.text[startIndex..<endIndex])...\n\n"
                }
            }
            return result
        } catch {
            return "Error searching transcriptions: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
}

// MARK: - Request/Response Types

struct ChatRequest: Codable {
    let message: String
    let conversationHistory: [[String: String]]
    let toolResults: [ToolResult]?
    let pendingToolCalls: [ToolCallResponse]?  // The tool calls that triggered these results
}

struct ChatResponse: Codable {
    let content: String?
    let toolCalls: [ToolCallResponse]?
}

struct ToolCallResponse: Codable {
    let id: String
    let name: String
    let arguments: [String: String]
}

struct ToolResult: Codable {
    let toolCallId: String
    let result: String
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }
}

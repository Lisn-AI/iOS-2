import Foundation
import SwiftData
import FirebaseAuth

/// Service for AI chat using the main backend's RAG-enhanced chat
/// All processing happens server-side - memories are searched and context is injected automatically
@MainActor
class ChatService: ObservableObject {
    /// User's first name extracted from Firebase Auth displayName
    var userFirstName: String? {
        guard let displayName = Auth.auth().currentUser?.displayName else { return nil }
        let firstName = displayName.components(separatedBy: " ").first
        return firstName?.isEmpty == true ? nil : firstName
    }

    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var lastSources: [String] = []

    /// The text currently being streamed in from the backend
    @Published var streamingText: String = ""
    /// Whether we're actively receiving stream chunks
    @Published var isStreaming: Bool = false

    private let modelContext: ModelContext
    private let dataService = DataService.shared

    /// Recording ID for per-recording chat scoping. nil = main/global chat.
    var recordingId: UUID?

    init(modelContext: ModelContext, recordingId: UUID? = nil) {
        self.modelContext = modelContext
        self.recordingId = recordingId
    }

    // MARK: - Public Methods

    /// Send a message and stream the response from the AI
    func sendMessage(_ content: String) async {
        await sendMessageWithContext(content, context: nil)
    }

    /// Send a message with optional recording context and stream the response
    func sendMessageWithContext(_ content: String, context: String?, chatMode: String = "main") async {
        // Add user message
        let userMessage = ChatMessage(content: content, isUser: true, recordingId: recordingId)
        messages.append(userMessage)
        modelContext.insert(userMessage)
        try? modelContext.save()  // Persist user message before streaming

        isLoading = true
        isStreaming = false
        streamingText = ""
        error = nil
        lastSources = []

        // Timeout: if stuck in thinking state for 45s with no stream data, show error
        let timeoutTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: 45_000_000_000) // 45 seconds
            if self.isLoading && !self.isStreaming {
                self.error = "Response timed out. Please try again."
                self.isLoading = false
                self.isStreaming = false
                // Remove empty placeholder assistant message if present
                if let last = self.messages.last, !last.isUser, last.content.isEmpty {
                    self.messages.removeLast()
                }
            }
        }

        do {
            // Send full history — backend handles compaction (summarizes older messages, keeps recent 6)
            // For assistant messages that performed tool actions, append a summary so the LLM
            // knows it already acted (prevents re-triggering on follow-up messages)
            let history = messages.map { message in
                var content = message.content
                if !message.isUser, let toolCalls = message.decodedToolCalls, !toolCalls.isEmpty {
                    let toolSummary = toolCalls.compactMap { tc -> String? in
                        guard tc.status == .completed || tc.status == .failed else { return nil }
                        let statusStr = tc.status == .completed ? "completed" : "failed"
                        if let resultMsg = tc.resultMessage {
                            return "[Action \(statusStr): \(tc.tool) — \(resultMsg)]"
                        }
                        return "[Action \(statusStr): \(tc.tool)]"
                    }.joined(separator: " ")
                    if !toolSummary.isEmpty {
                        content = content.isEmpty ? toolSummary : "\(content)\n\(toolSummary)"
                    }
                }
                return ChatHistoryItem(role: message.isUser ? "user" : "assistant", content: content)
            }

            print("[ChatService] Sending streaming chat request...")

            // Create a placeholder assistant message for the streaming response
            let assistantMessage = ChatMessage(content: "", isUser: false, recordingId: recordingId)
            messages.append(assistantMessage)

            var fullText = ""

            let stream = try await dataService.chatStream(
                message: content,
                history: Array(history),
                context: context,
                chatMode: chatMode,
                modelContext: modelContext,
                userName: userFirstName
            )

            for await event in stream {
                switch event {
                case .sources(let sources):
                    lastSources = sources
                    if let data = try? JSONEncoder().encode(sources),
                       let json = String(data: data, encoding: .utf8) {
                        assistantMessage.sourcesJSON = json
                    }
                    print("[ChatService] Sources: \(sources)")

                case .toolCall(let id, let skill, let tool, let params):
                    // Tool call is progress — stop showing thinking indicator
                    if isLoading {
                        isLoading = false
                        timeoutTask.cancel()
                    }
                    let toolCall = InlineToolCall.from(id: id, skill: skill, tool: tool, params: params)
                    var existing = assistantMessage.decodedToolCalls ?? []
                    existing.append(toolCall)
                    if let data = try? JSONEncoder().encode(existing),
                       let json = String(data: data, encoding: .utf8) {
                        assistantMessage.toolCallsJSON = json
                    }
                    print("[ChatService] Tool call: \(skill):\(tool)")

                case .toolResult(let id, let skill, let tool, let result):
                    var existing = assistantMessage.decodedToolCalls ?? []
                    if let idx = existing.firstIndex(where: { $0.id == id }) {
                        existing[idx].resultMessage = result.message
                        existing[idx].actionId = result.actionId
                        existing[idx].pendingPermissionId = result.pendingPermissionId

                        // Merge enriched data from backend into params for ActionEditSheet prefilling
                        if let enrichedData = result.data {
                            for (key, value) in enrichedData {
                                existing[idx].params[key] = AnyCodable(value)
                            }
                        }

                        if result.status == "permission_required" {
                            existing[idx].status = .permissionRequired
                        } else if result.success {
                            existing[idx].status = .completed
                        } else {
                            existing[idx].status = .failed
                        }
                        if let data = try? JSONEncoder().encode(existing),
                           let json = String(data: data, encoding: .utf8) {
                            assistantMessage.toolCallsJSON = json
                        }
                    }
                    print("[ChatService] Tool result: \(skill):\(tool) → \(result.status)")

                case .stepFinish(let finishReason):
                    print("[ChatService] Step finished: \(finishReason)")

                case .delta(let chunk):
                    if !isStreaming {
                        isStreaming = true
                        isLoading = false
                        timeoutTask.cancel() // Got data, cancel timeout
                    }
                    fullText += chunk
                    streamingText = fullText
                    // Update the last message in-place
                    assistantMessage.content = fullText

                case .done:
                    timeoutTask.cancel()
                    isStreaming = false
                    isLoading = false
                    streamingText = ""
                    // Persist the complete message
                    assistantMessage.content = fullText
                    modelContext.insert(assistantMessage)
                    try? modelContext.save()
                    print("[ChatService] Stream complete (\(fullText.count) chars)")

                    // Sync usage counters so local limits stay accurate
                    await SubscriptionService.shared.syncUsageFromBackend()

                case .error(let errorMsg):
                    self.error = errorMsg
                    isStreaming = false
                    isLoading = false
                    // Remove the empty placeholder if we got an error before any text
                    if assistantMessage.content.isEmpty {
                        messages.removeLast()
                    }
                    print("[ChatService] Stream ERROR: \(errorMsg)")
                }
            }

            // If stream finished without a .done event
            timeoutTask.cancel()
            if isStreaming || isLoading {
                isStreaming = false
                streamingText = ""
                isLoading = false
                if !fullText.isEmpty {
                    assistantMessage.content = fullText
                    modelContext.insert(assistantMessage)
                    try? modelContext.save()
                } else if assistantMessage.content.isEmpty {
                    // Remove empty placeholder if no text was ever received
                    messages.removeLast()
                }
            }

        } catch let apiError as APIError {
            timeoutTask.cancel()
            self.error = apiError.localizedDescription
            isStreaming = false
            isLoading = false
            if let last = messages.last, !last.isUser, last.content.isEmpty {
                messages.removeLast()
            }
            print("[ChatService] API ERROR: \(apiError)")
        } catch {
            timeoutTask.cancel()
            self.error = error.localizedDescription
            isStreaming = false
            isLoading = false
            if let last = messages.last, !last.isUser, last.content.isEmpty {
                messages.removeLast()
            }
            print("[ChatService] ERROR: \(error)")
        }
    }

    /// Process a transcript and optionally get a response
    func processTranscript(_ transcript: String, sessionId: String? = nil) async -> ProcessResult? {
        isLoading = true
        error = nil

        do {
            let result = try await APIService.shared.processTranscript(transcript, sessionId: sessionId)

            if let chatResponse = result.chatResponse, !chatResponse.isEmpty {
                let assistantMessage = ChatMessage(content: chatResponse, isUser: false)
                messages.append(assistantMessage)
                modelContext.insert(assistantMessage)
                try modelContext.save()
            }

            isLoading = false
            return result

        } catch let apiError as APIError {
            self.error = apiError.localizedDescription
            print("[ChatService] Process transcript API ERROR: \(apiError)")
        } catch {
            self.error = error.localizedDescription
            print("[ChatService] Process transcript ERROR: \(error)")
        }

        isLoading = false
        return nil
    }

    /// Clear chat history (both in-memory and persisted) — scoped to recordingId
    func clearHistory() {
        do {
            // Fetch only messages matching current scope
            let rid = recordingId
            let predicate: Predicate<ChatMessage>
            if let rid {
                predicate = #Predicate<ChatMessage> { $0.recordingId == rid }
            } else {
                predicate = #Predicate<ChatMessage> { $0.recordingId == nil }
            }
            let descriptor = FetchDescriptor<ChatMessage>(predicate: predicate)
            let toDelete = try modelContext.fetch(descriptor)
            for msg in toDelete {
                modelContext.delete(msg)
            }
            try modelContext.save()
        } catch {
            print("[ChatService] Failed to delete persisted chat history: \(error)")
        }
        messages.removeAll()
        lastSources = []
        streamingText = ""
        isStreaming = false
        self.error = nil
    }

    /// Load chat history from local storage — scoped to recordingId
    func loadHistory() {
        let rid = recordingId
        let predicate: Predicate<ChatMessage>
        if let rid {
            predicate = #Predicate<ChatMessage> { $0.recordingId == rid }
        } else {
            predicate = #Predicate<ChatMessage> { $0.recordingId == nil }
        }
        var descriptor = FetchDescriptor<ChatMessage>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\.timestamp, order: .forward)]

        do {
            messages = try modelContext.fetch(descriptor)
        } catch {
            print("Failed to load chat history: \(error)")
        }
    }

    /// Delete all chat messages
    func deleteAllMessages() {
        do {
            try modelContext.delete(model: ChatMessage.self)
            messages.removeAll()
            lastSources = []
            try modelContext.save()
        } catch {
            print("Failed to delete chat history: \(error)")
        }
    }
}

import Foundation
import SwiftData
import FirebaseAuth

/// Service for AI chat using the main backend's RAG-enhanced chat
/// All processing happens server-side - memories are searched and context is injected automatically
@MainActor
class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var lastSources: [String] = []

    /// The text currently being streamed in from the backend
    @Published var streamingText: String = ""
    /// Whether we're actively receiving stream chunks
    @Published var isStreaming: Bool = false

    private let modelContext: ModelContext
    private let api = APIService.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Send a message and stream the response from the AI
    func sendMessage(_ content: String) async {
        // Add user message
        let userMessage = ChatMessage(content: content, isUser: true)
        messages.append(userMessage)
        modelContext.insert(userMessage)

        isLoading = true
        isStreaming = false
        streamingText = ""
        error = nil
        lastSources = []

        do {
            // Build conversation history from recent messages (limit to 6)
            let history = messages.suffix(6).map { message in
                ChatHistoryItem(
                    role: message.isUser ? "user" : "assistant",
                    content: message.content
                )
            }

            print("[ChatService] Sending streaming chat request...")

            // Create a placeholder assistant message for the streaming response
            let assistantMessage = ChatMessage(content: "", isUser: false)
            messages.append(assistantMessage)

            var fullText = ""

            let stream = try await api.chatStream(
                message: content,
                history: Array(history)
            )

            for await event in stream {
                switch event {
                case .sources(let sources):
                    lastSources = sources
                    print("[ChatService] Sources: \(sources)")

                case .delta(let chunk):
                    if !isStreaming {
                        isStreaming = true
                        isLoading = false
                    }
                    fullText += chunk
                    streamingText = fullText
                    // Update the last message in-place
                    assistantMessage.content = fullText

                case .done:
                    isStreaming = false
                    streamingText = ""
                    // Persist the complete message
                    assistantMessage.content = fullText
                    modelContext.insert(assistantMessage)
                    try? modelContext.save()
                    print("[ChatService] Stream complete (\(fullText.count) chars)")

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
            if isStreaming {
                isStreaming = false
                streamingText = ""
                isLoading = false
                if !fullText.isEmpty {
                    assistantMessage.content = fullText
                    modelContext.insert(assistantMessage)
                    try? modelContext.save()
                }
            }

        } catch let apiError as APIError {
            self.error = apiError.localizedDescription
            isStreaming = false
            isLoading = false
            if let last = messages.last, !last.isUser, last.content.isEmpty {
                messages.removeLast()
            }
            print("[ChatService] API ERROR: \(apiError)")
        } catch {
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
            let result = try await api.processTranscript(transcript, sessionId: sessionId)

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

    /// Clear chat history (both in-memory and persisted)
    func clearHistory() {
        do {
            try modelContext.delete(model: ChatMessage.self)
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

    /// Load chat history from local storage
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

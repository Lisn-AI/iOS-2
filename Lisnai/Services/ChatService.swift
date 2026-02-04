import Foundation
import SwiftData

/// Service for AI chat using the main backend's RAG-enhanced chat
/// All processing happens server-side - memories are searched and context is injected automatically
@MainActor
class ChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var lastSources: [String] = []  // Memory IDs used for last response

    private let modelContext: ModelContext
    private let api = APIService.shared

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Send a message and get a response from the AI
    func sendMessage(_ content: String) async {
        // Add user message
        let userMessage = ChatMessage(content: content, isUser: true)
        messages.append(userMessage)
        modelContext.insert(userMessage)

        isLoading = true
        error = nil
        lastSources = []

        do {
            // Build conversation history from recent messages
            let history = messages.suffix(10).map { message in
                ChatHistoryItem(
                    role: message.isUser ? "user" : "assistant",
                    content: message.content
                )
            }

            // Call main backend's RAG-enhanced chat
            let response = try await api.chat(message: content, history: Array(history))

            // Store sources for UI display
            lastSources = response.sources ?? []

            // Add assistant message
            let assistantMessage = ChatMessage(content: response.response, isUser: false)
            messages.append(assistantMessage)
            modelContext.insert(assistantMessage)

            try modelContext.save()
        } catch let apiError as APIError {
            self.error = apiError.localizedDescription
            print("Chat error: \(apiError)")
        } catch {
            self.error = error.localizedDescription
            print("Chat error: \(error)")
        }

        isLoading = false
    }

    /// Process a transcript and optionally get a response
    /// This is called after voice recording to send the transcript to the backend
    func processTranscript(_ transcript: String, sessionId: String? = nil) async -> ProcessResult? {
        isLoading = true
        error = nil

        do {
            let result = try await api.processTranscript(transcript, sessionId: sessionId)

            // If there's a chat response, add it to messages
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
            print("Process transcript error: \(apiError)")
        } catch {
            self.error = error.localizedDescription
            print("Process transcript error: \(error)")
        }

        isLoading = false
        return nil
    }

    /// Clear chat history
    func clearHistory() {
        messages.removeAll()
        lastSources = []
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

// MARK: - ChatMessage Model (SwiftData)
// Note: This should match the existing model in Models/ChatMessage.swift
// Keeping here for reference only - use the model from Models folder

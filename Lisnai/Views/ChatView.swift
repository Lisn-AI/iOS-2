import SwiftUI
import SwiftData

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var chatService: ChatService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    init(modelContext: ModelContext) {
        _chatService = StateObject(wrappedValue: ChatService(modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        if chatService.messages.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(chatService.messages, id: \.id) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                            }
                        }

                        if chatService.isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal)
                            .id("loading")
                        }
                    }
                    .padding()
                }
                .onChange(of: chatService.messages.count) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: chatService.isLoading) { _, isLoading in
                    if isLoading {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }

            // Error display
            if let error = chatService.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Dismiss") {
                        chatService.error = nil
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }

            // Input bar
            inputBar
        }
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(action: {
                        chatService.clearHistory()
                    }) {
                        Label("Clear Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            chatService.loadHistory()
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 60)

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 50))
                .foregroundColor(.secondary.opacity(0.5))

            Text("Ask about your recordings")
                .font(.title3)
                .fontWeight(.semibold)

            Text("I can help you recall what happened on specific dates, search through your memories, and more.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                suggestionButton("What happened last week?")
                suggestionButton("Search for meetings about the project")
                suggestionButton("What did I do yesterday?")
            }
            .padding(.top, 16)

            Spacer()
        }
    }

    private func suggestionButton(_ text: String) -> some View {
        Button {
            inputText = text
            sendMessage()
        } label: {
            HStack {
                Text(text)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Ask about your recordings...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(20)
                .focused($isInputFocused)
                .lineLimit(1...5)
                .onSubmit {
                    sendMessage()
                }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.isEmpty ? .gray : .blue)
            }
            .disabled(inputText.isEmpty || chatService.isLoading)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""
        isInputFocused = false

        Task {
            await chatService.sendMessage(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            if chatService.isLoading {
                proxy.scrollTo("loading", anchor: .bottom)
            } else if let lastMessage = chatService.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(message.isUser ? Color.blue : Color(.systemGray5))
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(20)

                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
            }

            if !message.isUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animationOffset = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .offset(y: animationOffset == index ? -4 : 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGray5))
        .cornerRadius(20)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever()) {
                animationOffset = (animationOffset + 1) % 3
            }
        }
    }
}

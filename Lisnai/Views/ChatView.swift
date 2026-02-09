import SwiftUI
import SwiftData
import UIKit

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var chatService: ChatService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Namespace private var bottomID

    init(modelContext: ModelContext) {
        _chatService = StateObject(wrappedValue: ChatService(modelContext: modelContext))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            messagesScrollView

            // Error display
            if let error = chatService.error {
                errorBanner(error)
            }

            // Input bar
            inputBar
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive, action: {
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
        .onTapGesture {
            isInputFocused = false
        }
    }

    // MARK: - Messages ScrollView

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    if chatService.messages.isEmpty && !chatService.isLoading {
                        emptyStateView
                            .padding(.top, 40)
                    } else {
                        // Group messages by date
                        ForEach(groupedMessages, id: \.date) { group in
                            // Date header
                            DateHeader(date: group.date)
                                .padding(.top, 16)
                                .padding(.bottom, 8)

                            // Messages for this date
                            ForEach(group.messages, id: \.id) { message in
                                MessageBubble(message: message)
                                    .id(message.id)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                        }

                        // Typing indicator
                        if chatService.isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .id("typing")
                        }

                        // Bottom anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: chatService.messages.count) { oldCount, newCount in
                if newCount > oldCount {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: chatService.isLoading) { _, isLoading in
                if isLoading {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onAppear {
                // Scroll to bottom on appear
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
    }

    // MARK: - Grouped Messages

    private struct MessageGroup: Identifiable {
        let date: Date
        let messages: [ChatMessage]
        var id: Date { date }
    }

    private var groupedMessages: [MessageGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: chatService.messages) { message in
            calendar.startOfDay(for: message.timestamp)
        }
        return grouped.map { MessageGroup(date: $0.key, messages: $0.value.sorted { $0.timestamp < $1.timestamp }) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Ask About Your Memories")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("I can search through your conversations, recall specific moments, and help you remember important details.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Suggestion chips
            VStack(spacing: 10) {
                Text("Try asking:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                FlowLayout(spacing: 8) {
                    SuggestionChip(text: "What happened yesterday?") {
                        sendSuggestion("What happened yesterday?")
                    }
                    SuggestionChip(text: "Search for meetings") {
                        sendSuggestion("Search for meetings")
                    }
                    SuggestionChip(text: "Summarize last week") {
                        sendSuggestion("Summarize what happened last week")
                    }
                    SuggestionChip(text: "Find conversations about work") {
                        sendSuggestion("Find conversations about work")
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.top, 8)
        }
        .padding(.vertical, 40)
    }

    private func sendSuggestion(_ text: String) {
        inputText = text
        sendMessage()
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            Button {
                withAnimation {
                    chatService.error = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.orange.opacity(0.15))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                // Text field
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .focused($isInputFocused)
                        .lineLimit(1...6)
                        .padding(.vertical, 10)
                        .padding(.leading, 16)

                    // Send button inside the field
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(
                                inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isLoading
                                ? Color.gray.opacity(0.5)
                                : Color.blue
                            )
                    }
                    .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isLoading)
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                }
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 22))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.2)) {
            inputText = ""
        }

        Task {
            await chatService.sendMessage(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let anchor: UnitPoint = .bottom
        let id = chatService.isLoading ? "typing" : "bottom"

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: anchor)
            }
        } else {
            proxy.scrollTo(id, anchor: anchor)
        }
    }
}

// MARK: - Date Header

struct DateHeader: View {
    let date: Date

    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    var body: some View {
        Text(dateText)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemGray5).opacity(0.8))
            .clipShape(Capsule())
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 50)
            } else {
                // AI Avatar
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        message.isUser
                        ? LinearGradient(colors: [.blue, .blue.opacity(0.9)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(.systemGray5), Color(.systemGray5)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                    .clipShape(ChatBubbleShape(isUser: message.isUser))

                // Timestamp
                Text(message.formattedTime)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }

            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Bubble Shape

struct ChatBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let tailSize: CGFloat = 6

        var path = Path()

        if isUser {
            // User bubble - tail on right
            path.addRoundedRect(
                in: CGRect(x: 0, y: 0, width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // Small tail
            path.move(to: CGPoint(x: rect.width - tailSize, y: rect.height - 20))
            path.addQuadCurve(
                to: CGPoint(x: rect.width, y: rect.height - 8),
                control: CGPoint(x: rect.width - tailSize + 4, y: rect.height - 12)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.width - tailSize, y: rect.height - 4),
                control: CGPoint(x: rect.width - 2, y: rect.height - 4)
            )
        } else {
            // AI bubble - tail on left
            path.addRoundedRect(
                in: CGRect(x: tailSize, y: 0, width: rect.width - tailSize, height: rect.height),
                cornerSize: CGSize(width: radius, height: radius)
            )
            // Small tail
            path.move(to: CGPoint(x: tailSize, y: rect.height - 20))
            path.addQuadCurve(
                to: CGPoint(x: 0, y: rect.height - 8),
                control: CGPoint(x: tailSize - 4, y: rect.height - 12)
            )
            path.addQuadCurve(
                to: CGPoint(x: tailSize, y: rect.height - 4),
                control: CGPoint(x: 2, y: rect.height - 4)
            )
        }

        return path
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(scale(for: index))
                    .opacity(opacity(for: index))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemGray5))
        .clipShape(ChatBubbleShape(isUser: false))
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }

    private func scale(for index: Int) -> CGFloat {
        let offset = CGFloat(index) / 3.0
        let adjustedPhase = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.6 + 0.4 * sin(adjustedPhase * .pi * 2)
    }

    private func opacity(for index: Int) -> CGFloat {
        let offset = CGFloat(index) / 3.0
        let adjustedPhase = (phase + offset).truncatingRemainder(dividingBy: 1.0)
        return 0.4 + 0.6 * sin(adjustedPhase * .pi * 2)
    }
}

// MARK: - Suggestion Chip

struct SuggestionChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(Color.blue.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        Text("Chat Preview")
    }
}

import SwiftUI
import SwiftData
import MarkdownUI

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
            messagesScrollView

            if let error = chatService.error {
                errorBanner(error)
            }

            inputBar
                .padding(.bottom, isInputFocused ? 0 : 68)
        }
        .background(LisnColors.bgPrimary)
        .safeAreaInset(edge: .top) {
            HStack {
                Text("Chat")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(LisnColors.textPrimary)
                Spacer()
                Menu {
                    Button(role: .destructive, action: {
                        chatService.clearHistory()
                    }) {
                        Label("Clear Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(LisnColors.textSecondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, LisnSpacing.sm)
            .padding(.bottom, LisnSpacing.xs)
            .background(.regularMaterial)
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
                LazyVStack(spacing: LisnSpacing.xxxs) {
                    if chatService.messages.isEmpty && !chatService.isLoading && !chatService.isStreaming {
                        emptyStateView
                            .padding(.top, LisnSpacing.xxxl)
                    } else {
                        ForEach(groupedMessages, id: \.date) { group in
                            DateHeader(date: group.date)
                                .padding(.top, LisnSpacing.md)
                                .padding(.bottom, LisnSpacing.xs)

                            ForEach(group.messages, id: \.id) { message in
                                MessageBubble(
                                    message: message,
                                    isStreaming: !message.isUser && message.id == chatService.messages.last?.id && chatService.isStreaming
                                )
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }
                        }

                        // Typing indicator (before stream starts)
                        if chatService.isLoading && !chatService.isStreaming {
                            HStack {
                                TypingIndicator()
                                Spacer()
                            }
                            .padding(.horizontal, LisnSpacing.md)
                            .padding(.top, LisnSpacing.xs)
                            .id("typing")
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                }
                .padding(.vertical, LisnSpacing.xs)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: chatService.messages.count) { oldCount, newCount in
                if newCount > oldCount {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onChange(of: chatService.streamingText) { _, _ in
                // Auto-scroll as streaming text arrives
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: chatService.isLoading) { _, isLoading in
                if isLoading {
                    scrollToBottom(proxy: proxy, animated: true)
                }
            }
            .onAppear {
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
        VStack(spacing: LisnSpacing.lg) {
            ZStack {
                Circle()
                    .fill(LisnColors.bgSecondary)
                    .frame(width: 80, height: 80)

                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 32))
                    .foregroundColor(LisnColors.accent)
            }

            VStack(spacing: LisnSpacing.xs) {
                Text("Ask About Your Memories")
                    .font(LisnFont.titleLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Text("I can search through your conversations, recall specific moments, and help you remember important details.")
                    .font(LisnFont.bodyMedium())
                    .foregroundColor(LisnColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LisnSpacing.xxl)
            }

            VStack(spacing: 10) {
                Text("Try asking:")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                FlowLayout(spacing: LisnSpacing.xs) {
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
                .padding(.horizontal, LisnSpacing.xl)
            }
            .padding(.top, LisnSpacing.xs)
        }
        .padding(.vertical, LisnSpacing.xxxl)
    }

    private func sendSuggestion(_ text: String) {
        inputText = text
        sendMessage()
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: LisnSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(LisnColors.warning)

            Text(error)
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textPrimary)

            Spacer()

            Button {
                withAnimation {
                    chatService.error = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(LisnColors.textSecondary)
            }
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, LisnSpacing.sm)
        .background(LisnColors.warning.opacity(0.15))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: LisnSpacing.sm) {
            HStack(alignment: .bottom, spacing: LisnSpacing.xs) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .font(LisnFont.bodyLarge())
                    .textFieldStyle(.plain)
                    .focused($isInputFocused)
                    .lineLimit(1...6)
                    .padding(.vertical, 10)
                    .padding(.leading, LisnSpacing.md)

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 20))
                        .foregroundColor(
                            inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isLoading || chatService.isStreaming
                            ? Color.gray.opacity(0.5)
                            : LisnColors.accent
                        )
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chatService.isLoading || chatService.isStreaming)
                .padding(.trailing, 10)
                .padding(.bottom, 10)
            }
            .background(LisnColors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(
                color: LisnShadow.md.color,
                radius: LisnShadow.md.radius,
                x: LisnShadow.md.x,
                y: LisnShadow.md.y
            )
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, LisnSpacing.sm)
        .background(LisnColors.bgPrimary)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        LisnHaptics.light()

        withAnimation(.easeOut(duration: 0.2)) {
            inputText = ""
        }

        Task {
            await chatService.sendMessage(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let id = chatService.isLoading && !chatService.isStreaming ? "typing" : "bottom"

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
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
            .font(LisnFont.caption())
            .foregroundColor(LisnColors.textTertiary)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming: Bool = false

    private var bubbleShape: UnevenRoundedRectangle {
        if message.isUser {
            UnevenRoundedRectangle(
                topLeadingRadius: 20,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 4,
                topTrailingRadius: 20
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 20,
                bottomTrailingRadius: 20,
                topTrailingRadius: 20
            )
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: LisnSpacing.xs) {
            if message.isUser {
                Spacer(minLength: 50)
            } else {
                // AI Avatar
                Circle()
                    .fill(LisnColors.bgElevated)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(LisnColors.accent)
                    )
                    .shadow(
                        color: LisnShadow.sm.color,
                        radius: LisnShadow.sm.radius,
                        x: LisnShadow.sm.x,
                        y: LisnShadow.sm.y
                    )
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: LisnSpacing.xxs) {
                // Message content
                Group {
                    if message.isUser {
                        // User messages: plain text
                        Text(message.content)
                            .font(LisnFont.bodyLarge())
                    } else {
                        // AI messages: render markdown
                        Markdown(message.content)
                            .markdownTheme(.lisnAI)
                            .markdownCodeSyntaxHighlighter(.plain)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(message.isUser ? LisnColors.accent : LisnColors.bgElevated)
                .foregroundColor(message.isUser ? .white : LisnColors.textPrimary)
                .clipShape(bubbleShape)
                .shadow(
                    color: LisnShadow.sm.color,
                    radius: LisnShadow.sm.radius,
                    x: LisnShadow.sm.x,
                    y: LisnShadow.sm.y
                )

                // Timestamp + streaming indicator
                HStack(spacing: 4) {
                    if isStreaming {
                        StreamingCursor()
                    }
                    Text(message.formattedTime)
                        .font(LisnFont.labelSmall())
                        .foregroundColor(LisnColors.textTertiary)
                }
                .padding(.horizontal, LisnSpacing.xxs)
            }

            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
        .padding(.horizontal, LisnSpacing.sm)
        .padding(.vertical, LisnSpacing.xxs)
    }
}

// MARK: - Streaming Cursor

struct StreamingCursor: View {
    @State private var visible = true

    var body: some View {
        Circle()
            .fill(LisnColors.accent)
            .frame(width: 6, height: 6)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

// MARK: - MarkdownUI Theme

extension MarkdownUI.Theme {
    /// Custom theme matching Lisn's design system
    static let lisnAI = Theme()
        .text {
            ForegroundColor(LisnColors.textPrimary)
            FontSize(15)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(13)
            ForegroundColor(LisnColors.accent)
            BackgroundColor(LisnColors.bgSecondary)
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(13)
                        ForegroundColor(LisnColors.textPrimary)
                    }
            }
            .padding(12)
            .background(LisnColors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(LisnColors.accent.opacity(0.5))
                    .frame(width: 3)
                configuration.label
                    .markdownTextStyle { ForegroundColor(LisnColors.textSecondary) }
                    .padding(.leading, 10)
            }
        }
        .listItem { configuration in
            configuration.label
                .markdownTextStyle {
                    FontSize(15)
                    ForegroundColor(LisnColors.textPrimary)
                }
        }
        .heading1 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(20)
                    ForegroundColor(LisnColors.textPrimary)
                }
                .padding(.bottom, 4)
        }
        .heading2 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(17)
                    ForegroundColor(LisnColors.textPrimary)
                }
                .padding(.bottom, 2)
        }
        .heading3 { configuration in
            configuration.label
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(15)
                    ForegroundColor(LisnColors.textPrimary)
                }
        }
        .link {
            ForegroundColor(LisnColors.accent)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
        }
}

// MARK: - Plain Syntax Highlighter (no-op)

struct PlainCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    func highlightCode(_ code: String, language: String?) -> Text {
        Text(code)
    }
}

extension CodeSyntaxHighlighter where Self == PlainCodeSyntaxHighlighter {
    static var plain: PlainCodeSyntaxHighlighter { PlainCodeSyntaxHighlighter() }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(LisnColors.textTertiary)
                    .frame(width: 8, height: 8)
                    .scaleEffect(scale(for: index))
                    .opacity(opacity(for: index))
            }
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, 14)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(
            color: LisnShadow.sm.color,
            radius: LisnShadow.sm.radius,
            x: LisnShadow.sm.x,
            y: LisnShadow.sm.y
        )
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
                .font(LisnFont.bodyMedium())
                .padding(.horizontal, 14)
                .padding(.vertical, LisnSpacing.xs)
                .background(LisnColors.bgSecondary)
                .foregroundColor(LisnColors.textPrimary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        Text("Chat Preview")
    }
}

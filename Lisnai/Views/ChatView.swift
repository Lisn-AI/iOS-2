import SwiftUI
import SwiftData
import MarkdownUI

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var subscriptionService: SubscriptionService
    @EnvironmentObject var authService: AuthService
    @StateObject private var chatService: ChatService
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var shouldAutoScroll = true
    @State private var showPaywall = false
    @State private var showLimitCard = false

    /// User's first name for the personalized header
    private var userFirstName: String? {
        guard let displayName = authService.user?.displayName else { return nil }
        let first = displayName.components(separatedBy: " ").first
        return first?.isEmpty == true ? nil : first
    }

    init(modelContext: ModelContext) {
        _chatService = StateObject(wrappedValue: ChatService(modelContext: modelContext))
    }

    var body: some View {
        ZStack {
            // Inline upgrade card when limit hit
            if showLimitCard {
                VStack {
                    Spacer()
                    let check = subscriptionService.canChat()
                    UpgradePromptCard(
                        resourceName: "chats",
                        used: check.used,
                        limit: check.limit
                    ) {
                        showLimitCard = false
                        showPaywall = true
                    }
                    .padding(.horizontal, LisnSpacing.md)
                    .padding(.bottom, 80)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(10)
            }

            messagesScrollView

            // TOP fade — independent offset to bridge header gap
            VStack(spacing: 0) {
                LisnColors.bgPrimary
                    .frame(height: 4)  // solid bridge
                LinearGradient(
                    colors: [LisnColors.bgPrimary, LisnColors.bgPrimary.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)  // fade length
                Spacer(minLength: 0)
            }
            .offset(y: -58)  // pull UP to meet header
            .allowsHitTesting(false)

            // BOTTOM fade — soft transition into input bar / pill area
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [LisnColors.bgPrimary.opacity(0), LisnColors.bgPrimary],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
            }
            .allowsHitTesting(false)

            // Input bar — on top of everything, properly clearing the pill tab bar
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    if let error = chatService.error {
                        errorBanner(error)
                    }

                    inputBar
                        .padding(.bottom, isInputFocused ? 0 : 80)
                }
            }
        }
        .background(LisnColors.bgPrimary)
        .safeAreaInset(edge: .top) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    if let name = userFirstName {
                        Text("Hi, \(name)")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(LisnColors.textSecondary)
                    }
                    Text("Chat")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(LisnColors.textPrimary)
                }
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
            .background(
                VStack(spacing: 0) {
                    // Solid white header area
                    Color.white
                    // Soft fade at the bottom edge — no hard line
                    LinearGradient(
                        colors: [Color.white, Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }
                .ignoresSafeArea(edges: .top)
            )
        }
        .onAppear {
            chatService.loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .chatWithContext)) { notification in
            guard let title = notification.userInfo?["title"] as? String,
                  let summary = notification.userInfo?["summary"] as? String else { return }
            let message = "I want to ask about '\(title)'. What are the key takeaways from this conversation?"
            Task {
                await chatService.sendMessageWithContext(message, context: summary)
            }
        }
        .onTapGesture {
            isInputFocused = false
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionService)
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
                            }
                        }

                        // Thinking indicator (before stream starts)
                        if chatService.isLoading && !chatService.isStreaming {
                            ThinkingIndicator()
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
            .contentMargins(.bottom, 220, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            // Single consolidated scroll handler — prevents multiple animated
            // scroll requests from fighting each other and causing flicker.
            .onChange(of: chatService.messages.count) { _, _ in
                guard shouldAutoScroll else { return }
                if chatService.isStreaming {
                    // During streaming: snap instantly — no animation prevents jitter
                    proxy.scrollTo("bottom", anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatService.isLoading) { _, isLoading in
                guard isLoading, shouldAutoScroll else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("bottom", anchor: .bottom)
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

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !chatService.isLoading && !chatService.isStreaming
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask anything...", text: $inputText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundColor(LisnColors.textPrimary)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .lineLimit(1...6)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(canSend ? LisnColors.textPrimary : LisnColors.textTertiary.opacity(0.3))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .modifier(LiquidGlassInputBarModifier())
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        // Paywall disabled — will enforce via Apple IAP later
        // let limitCheck = subscriptionService.canChat()
        // if !limitCheck.isAllowed {
        //     showLimitCard = true
        //     return
        // }

        LisnHaptics.light()
        isInputFocused = false

        withAnimation(.easeOut(duration: 0.2)) {
            inputText = ""
        }

        Task {
            await chatService.sendMessage(text)
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
    @State private var citationSourceIds: [String] = []
    @State private var showCitationSheet = false

    var body: some View {
        // Hide empty AI placeholder messages (shown during thinking before streaming starts)
        // But show if tool calls exist — the action snippet should be visible during "Preparing..."
        if !message.isUser && message.content.isEmpty && !isStreaming && (message.decodedToolCalls ?? []).isEmpty {
            EmptyView()
        } else if message.isUser {
            // User message — soft rounded rectangle
            HStack {
                Spacer(minLength: 60)
                VStack(alignment: .trailing, spacing: LisnSpacing.xxs) {
                    Text(message.content)
                        .font(.system(size: 17))
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .foregroundColor(LisnColors.textPrimary)
                        .background(LisnColors.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 20))

                    Text(message.formattedTime)
                        .font(LisnFont.labelSmall())
                        .foregroundColor(LisnColors.textTertiary)
                        .padding(.horizontal, LisnSpacing.xxs)
                }
            }
            .padding(.horizontal, LisnSpacing.sm)
            .padding(.vertical, LisnSpacing.xxs)
        } else {
            // AI message — free-flowing, no bubble
            HStack(alignment: .top, spacing: LisnSpacing.xs) {
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

                VStack(alignment: .leading, spacing: LisnSpacing.xxs) {
                    // Message content — no bubble background
                    Group {
                        if isStreaming {
                            Text(message.content)
                                .font(.system(size: 17))
                                .foregroundColor(LisnColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Markdown(message.content)
                                .markdownTheme(.lisnAI)
                                .markdownCodeSyntaxHighlighter(.plain)
                                .fixedSize(horizontal: false, vertical: true)
                                .environment(\.openURL, OpenURLAction { url in
                                    if url.scheme == "lisn", url.host == "cite",
                                       let citeStr = url.pathComponents.dropFirst().first,
                                       let citeNum = Int(citeStr),
                                       citeNum >= 1, citeNum <= message.sourceIds.count {
                                        citationSourceIds = [message.sourceIds[citeNum - 1]]
                                        showCitationSheet = true
                                        return .handled
                                    }
                                    return .systemAction
                                })
                        }
                    }
                    .textSelection(.enabled)
                    .padding(.top, 4)

                    // Timestamp + streaming indicator
                    HStack(spacing: 4) {
                        if isStreaming {
                            StreamingCursor()
                        }
                        Text(message.formattedTime)
                            .font(LisnFont.labelSmall())
                            .foregroundColor(LisnColors.textTertiary)
                    }

                    // Tool call action snippets — collapse completed ones when >2
                    if let toolCalls = message.decodedToolCalls, !toolCalls.isEmpty {
                        ToolCallsSection(toolCalls: toolCalls) { toolCallId, newStatus in
                            // Persist status change to SwiftData so it survives app restart
                            var updated = message.decodedToolCalls ?? []
                            if let idx = updated.firstIndex(where: { $0.id == toolCallId }) {
                                updated[idx].status = newStatus
                                if let data = try? JSONEncoder().encode(updated),
                                   let json = String(data: data, encoding: .utf8) {
                                    message.toolCallsJSON = json
                                }
                            }
                        }
                    }

                    // Response action bar — appears with animation after streaming completes
                    if !isStreaming && !message.content.isEmpty {
                        ResponseActionBar(content: message.content, sourceIds: message.sourceIds)
                            .padding(.top, 2)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .topLeading)).combined(with: .offset(y: 6)))
                            .animation(.easeOut(duration: 0.35), value: isStreaming)
                    }
                }
            }
            .padding(.horizontal, LisnSpacing.sm)
            .padding(.vertical, LisnSpacing.xxs)
            .sheet(isPresented: $showCitationSheet) {
                SourcesListSheet(sourceIds: citationSourceIds)
            }
        }
    }
}

// MARK: - Response Action Bar

struct ResponseActionBar: View {
    let content: String
    var sourceIds: [String] = []
    @State private var copied = false
    @State private var thumbsUp = false
    @State private var thumbsDown = false
    @State private var showSourcesSheet = false

    var body: some View {
        HStack(spacing: 14) {
            if !sourceIds.isEmpty {
                Button { showSourcesSheet = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .medium))
                        Text("\(sourceIds.count) sources")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(LisnColors.accent)
                }
                .sheet(isPresented: $showSourcesSheet) {
                    SourcesListSheet(sourceIds: sourceIds)
                }
            }

            Button {
                UIPasteboard.general.string = content
                copied = true
                LisnHaptics.light()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(copied ? LisnColors.success : LisnColors.textSecondary)
            }

            Button {
                thumbsUp.toggle()
                if thumbsUp { thumbsDown = false }
                LisnHaptics.light()
            } label: {
                Image(systemName: thumbsUp ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(thumbsUp ? LisnColors.accent : LisnColors.textSecondary)
            }

            Button {
                thumbsDown.toggle()
                if thumbsDown { thumbsUp = false }
                LisnHaptics.light()
            } label: {
                Image(systemName: thumbsDown ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(thumbsDown ? LisnColors.warning : LisnColors.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(LisnColors.bgElevated)
        .clipShape(Capsule())
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 1)
    }
}

// MARK: - Tool Calls Section (collapsible summary for completed actions)

struct ToolCallsSection: View {
    let toolCalls: [InlineToolCall]
    var onStatusChange: ((String, ToolCallStatus) -> Void)?
    @State private var expanded = false
    @State private var executingAll = false

    private var completedCalls: [InlineToolCall] {
        toolCalls.filter { $0.status == .completed }
    }

    private var activeCalls: [InlineToolCall] {
        toolCalls.filter { $0.status != .completed }
    }

    private var reviewableCalls: [InlineToolCall] {
        toolCalls.filter { $0.status == .permissionRequired }
    }

    /// Show collapsed summary when there are 3+ completed tool calls
    private var shouldCollapse: Bool {
        completedCalls.count >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
            // Always show active (non-completed) tool calls
            ForEach(activeCalls) { toolCall in
                ActionSnippetView(toolCall: toolCall, onStatusChange: onStatusChange)
            }

            // Batch Execute All / Skip All for 2+ reviewable actions
            if reviewableCalls.count >= 2 {
                HStack(spacing: LisnSpacing.sm) {
                    Button {
                        executingAll = true
                        Task {
                            for tc in reviewableCalls {
                                let action = tc.toPendingAction()
                                let result = await ActionExecutor.shared.executeAction(action)
                                if result.success {
                                    onStatusChange?(tc.id, .completed)
                                } else {
                                    onStatusChange?(tc.id, .failed)
                                }
                            }
                            executingAll = false
                            LisnHaptics.success()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if executingAll {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 13))
                            }
                            Text("Execute All")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(LisnColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    }
                    .disabled(executingAll)
                    .buttonStyle(.plain)

                    Button {
                        for tc in reviewableCalls {
                            onStatusChange?(tc.id, .completed)
                        }
                    } label: {
                        Text("Skip All")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(LisnColors.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(LisnColors.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, LisnSpacing.xxs)
            }

            if shouldCollapse && !expanded {
                // Collapsed summary chip
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        expanded = true
                    }
                    LisnHaptics.light()
                } label: {
                    HStack(spacing: LisnSpacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(LisnColors.success)

                        Text("\(completedCalls.count) actions completed")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(LisnColors.textSecondary)

                        Spacer()

                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(LisnColors.textTertiary)
                    }
                    .padding(.horizontal, LisnSpacing.sm)
                    .padding(.vertical, LisnSpacing.xs)
                    .background(LisnColors.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                            .stroke(LisnColors.success.opacity(0.2), lineWidth: 0.5)
                    )
                }
                .padding(.top, LisnSpacing.xxs)
            } else {
                // Show all completed tool calls (expanded or fewer than 3)
                ForEach(completedCalls) { toolCall in
                    ActionSnippetView(toolCall: toolCall, onStatusChange: onStatusChange)
                }

                // Collapse button when expanded
                if shouldCollapse && expanded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expanded = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 11, weight: .medium))
                            Text("Collapse")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(LisnColors.textTertiary)
                        .padding(.top, LisnSpacing.xxxs)
                    }
                }
            }
        }
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
    /// Premium markdown theme — gold accents, highlighted inline code,
    /// proper list formatting, and clean heading hierarchy.
    static let lisnAI = Theme()
        .text {
            ForegroundColor(LisnColors.textPrimary)
            FontSize(16)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(Color(red: 0.92, green: 0.58, blue: 0.36))
            BackgroundColor(Color.white.opacity(0.08))
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        ForegroundColor(LisnColors.textPrimary)
                    }
                    .padding(14)
            }
            .background(LisnColors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .markdownMargin(top: 4, bottom: 16)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LisnColors.accent.opacity(0.5))
                    .relativeFrame(width: .em(0.2))
                configuration.label
                    .markdownTextStyle { ForegroundColor(LisnColors.textSecondary) }
                    .relativePadding(.horizontal, length: .em(1))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .list { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.2))
        }
        .heading1 { configuration in
            configuration.label
                .relativePadding(.bottom, length: .em(0.3))
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 24, bottom: 16)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.75))
                    ForegroundColor(LisnColors.textPrimary)
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 20, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.35))
                    ForegroundColor(LisnColors.textPrimary)
                }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.15))
                    ForegroundColor(LisnColors.accent)
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.125))
                .markdownMargin(top: 16, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    ForegroundColor(LisnColors.textSecondary)
                }
        }
        .link {
            ForegroundColor(LisnColors.accent)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.25))
                .markdownMargin(top: 0, bottom: 16)
        }
        .thematicBreak {
            Divider()
                .overlay(LisnColors.textTertiary.opacity(0.3))
                .markdownMargin(top: 20, bottom: 20)
        }

    /// Premium content theme for recording summaries, insights, and detail pages.
    /// Warmer colors, wider line spacing, subtle highlight for inline code,
    /// and section-card-friendly heading styles.
    static let lisnContent = Theme()
        .text {
            ForegroundColor(Color(red: 0.18, green: 0.20, blue: 0.21)) // Soft dark #2D3436
            FontSize(16)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .code {
            // Subtle highlight instead of code — same font family, semibold, warm cream bg
            FontWeight(.semibold)
            FontSize(.em(0.95))
            ForegroundColor(Color(red: 0.18, green: 0.20, blue: 0.21))
            BackgroundColor(Color(red: 1.0, green: 0.95, blue: 0.88).opacity(0.7)) // Warm cream #FFF2E0
        }
        .codeBlock { configuration in
            ScrollView(.horizontal, showsIndicators: false) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .relativeLineSpacing(.em(0.225))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                        ForegroundColor(Color(red: 0.18, green: 0.20, blue: 0.21))
                    }
                    .padding(14)
            }
            .background(Color(red: 0.98, green: 0.96, blue: 0.93)) // Warm off-white
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .markdownMargin(top: 4, bottom: 16)
        }
        .blockquote { configuration in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LisnColors.accent.opacity(0.4))
                    .relativeFrame(width: .em(0.2))
                configuration.label
                    .markdownTextStyle {
                        ForegroundColor(Color(red: 0.30, green: 0.33, blue: 0.35))
                    }
                    .relativePadding(.horizontal, length: .em(1))
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .list { configuration in
            configuration.label
                .markdownMargin(top: 4, bottom: 8)
        }
        .listItem { configuration in
            configuration.label
                .markdownMargin(top: .em(0.3))
        }
        .heading1 { configuration in
            configuration.label
                .relativePadding(.bottom, length: .em(0.3))
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 24, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.65))
                    ForegroundColor(Color(red: 0.12, green: 0.13, blue: 0.14))
                }
        }
        .heading2 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 20, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.35))
                    ForegroundColor(Color(red: 0.12, green: 0.13, blue: 0.14))
                }
        }
        .heading3 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 18, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.bold)
                    FontSize(.em(1.15))
                    ForegroundColor(LisnColors.accent)
                }
        }
        .heading4 { configuration in
            configuration.label
                .relativeLineSpacing(.em(0.15))
                .markdownMargin(top: 14, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.05))
                    ForegroundColor(Color(red: 0.30, green: 0.33, blue: 0.35))
                }
        }
        .link {
            ForegroundColor(LisnColors.accent)
        }
        .paragraph { configuration in
            configuration.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.35)) // Wider line spacing for readability
                .markdownMargin(top: 0, bottom: 14)
        }
        .thematicBreak {
            Divider()
                .overlay(Color(red: 0.85, green: 0.82, blue: 0.78).opacity(0.5))
                .markdownMargin(top: 16, bottom: 16)
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

// MARK: - Thinking Indicator

struct ThinkingIndicator: View {
    private static let phrases = [
        "On it...",
        "Searching memories...",
        "Analyzing context...",
        "Composing response..."
    ]

    private static let gradientColors: [Color] = [
        .red, .orange, Color(.systemYellow), .teal, .blue, .purple, .red
    ]

    @State private var phraseIndex = 0
    @State private var gradientOffset: CGFloat = 0

    private let timer = Timer.publish(every: 2.5, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: LisnSpacing.xs) {
            // AI Avatar — same as MessageBubble AI avatar
            Circle()
                .fill(LisnColors.bgElevated)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(LisnColors.accent)
                )

            Text(Self.phrases[phraseIndex])
                .font(.system(size: 15, weight: .semibold))
                .overlay(
                    LinearGradient(
                        colors: Self.gradientColors,
                        startPoint: UnitPoint(x: gradientOffset, y: 0.5),
                        endPoint: UnitPoint(x: gradientOffset + 0.5, y: 0.5)
                    )
                    .mask(
                        Text(Self.phrases[phraseIndex])
                            .font(.system(size: 15, weight: .semibold))
                    )
                )

            Spacer()
        }
        .padding(.horizontal, LisnSpacing.sm)
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                gradientOffset = 1.0
            }
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                phraseIndex = (phraseIndex + 1) % Self.phrases.count
            }
        }
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

// MARK: - Liquid Glass Modifiers

/// Input bar pill: native Liquid Glass on iOS 26+, manual glass hack fallback
private struct LiquidGlassInputBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        } else {
            content
                .background(Color.white.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .background(.ultraThinMaterial)
        }
    }
}

#Preview {
    NavigationStack {
        Text("Chat Preview")
    }
}

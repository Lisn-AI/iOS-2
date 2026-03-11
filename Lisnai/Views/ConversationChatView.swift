import SwiftUI
import SwiftData
import MarkdownUI

/// Ephemeral per-conversation chat sheet
/// Messages are not persisted — dismissed sheet clears history
struct ConversationChatView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [EphemeralMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var isStreaming = false
    @State private var streamingText = ""
    @State private var error: String?
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                messagesScrollView

                // Bottom fade — above scroll, below input bar
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

                // Input bar — on top of everything
                VStack {
                    Spacer()
                    VStack(spacing: 0) {
                        if let error = error {
                            errorBanner(error)
                        }

                        inputBar
                    }
                }
            }
            .background(LisnColors.bgPrimary)
            .navigationTitle(recording.title ?? "Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onTapGesture { isInputFocused = false }
    }

    // MARK: - Messages

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: LisnSpacing.xxxs) {
                    if messages.isEmpty && !isLoading {
                        conversationContextBanner
                            .padding(.top, LisnSpacing.md)
                    }

                    ForEach(messages) { message in
                        EphemeralMessageBubble(
                            message: message,
                            isStreaming: !message.isUser && message.id == messages.last?.id && isStreaming
                        )
                        .id(message.id)
                    }

                    if isLoading && !isStreaming {
                        ThinkingIndicator()
                            .padding(.top, LisnSpacing.xs)
                            .id("typing")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, LisnSpacing.xs)
            }
            .contentMargins(.bottom, 140, for: .scrollContent)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: isLoading) { _, loading in
                if loading {
                    withAnimation(.easeOut(duration: 0.3)) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var conversationContextBanner: some View {
        VStack(spacing: LisnSpacing.sm) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28))
                .foregroundColor(LisnColors.accent)

            Text("About this conversation")
                .font(LisnFont.labelLarge())
                .foregroundColor(LisnColors.textPrimary)

            Text("Ask anything about this recording")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
                .multilineTextAlignment(.center)

            if let summary = recording.summary {
                Markdown(summary.text)
                    .markdownTheme(.lisnAI)
                    .markdownCodeSyntaxHighlighter(.plain)
                    .padding(.horizontal, LisnSpacing.md)
            }
        }
        .padding(.vertical, LisnSpacing.xl)
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
                withAnimation { self.error = nil }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(LisnColors.textSecondary)
            }
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, LisnSpacing.sm)
        .background(LisnColors.warning.opacity(0.15))
    }

    // MARK: - Input Bar

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isLoading && !isStreaming
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about this conversation...", text: $inputText, axis: .vertical)
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
        .modifier(ConversationLiquidGlassInputBarModifier())
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, 10)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        LisnHaptics.light()
        inputText = ""
        isInputFocused = false

        // Add user message
        messages.append(EphemeralMessage(content: text, isUser: true))

        isLoading = true
        isStreaming = false
        streamingText = ""
        error = nil

        Task {
            await streamResponse(for: text)
        }
    }

    private func streamResponse(for message: String) async {
        // Timeout: if stuck thinking for 45s with no stream data, show error
        let timeoutTask = Task { @MainActor in
            try await Task.sleep(nanoseconds: 45_000_000_000)
            if self.isLoading && !self.isStreaming {
                self.error = "Response timed out. Please try again."
                self.isLoading = false
                self.isStreaming = false
                if let last = self.messages.last, !last.isUser, last.content.isEmpty {
                    self.messages.removeLast()
                }
            }
        }

        do {
            // Build history from ephemeral messages
            let history = messages.suffix(6).map { msg in
                ChatHistoryItem(
                    role: msg.isUser ? "user" : "assistant",
                    content: msg.content
                )
            }

            // The recording summary is always injected as context
            let context = recording.summary?.text

            let stream = try await DataService.shared.chatStream(
                message: message,
                history: Array(history),
                context: context,
                modelContext: modelContext
            )

            // Create placeholder assistant message
            var assistantMessage = EphemeralMessage(content: "", isUser: false)
            messages.append(assistantMessage)
            let assistantIndex = messages.count - 1

            var fullText = ""

            for await event in stream {
                switch event {
                case .sources(let sources):
                    if let data = try? JSONEncoder().encode(sources),
                       let json = String(data: data, encoding: .utf8) {
                        messages[assistantIndex].sourcesJSON = json
                    }

                case .toolCall(let id, let skill, let tool, let params):
                    // Tool call is progress — stop showing thinking indicator
                    if isLoading {
                        isLoading = false
                        timeoutTask.cancel()
                    }
                    let toolCall = InlineToolCall.from(id: id, skill: skill, tool: tool, params: params)
                    var existing = messages[assistantIndex].decodedToolCalls ?? []
                    existing.append(toolCall)
                    if let data = try? JSONEncoder().encode(existing),
                       let json = String(data: data, encoding: .utf8) {
                        messages[assistantIndex].toolCallsJSON = json
                    }

                case .toolResult(let id, _, _, let result):
                    var existing = messages[assistantIndex].decodedToolCalls ?? []
                    if let idx = existing.firstIndex(where: { $0.id == id }) {
                        existing[idx].resultMessage = result.message
                        existing[idx].actionId = result.actionId
                        existing[idx].pendingPermissionId = result.pendingPermissionId
                        if result.status == "permission_required" {
                            existing[idx].status = .permissionRequired
                        } else if result.success {
                            existing[idx].status = .completed
                        } else {
                            existing[idx].status = .failed
                        }
                        if let data = try? JSONEncoder().encode(existing),
                           let json = String(data: data, encoding: .utf8) {
                            messages[assistantIndex].toolCallsJSON = json
                        }
                    }

                case .stepFinish:
                    break // logging only

                case .delta(let chunk):
                    if !isStreaming {
                        isStreaming = true
                        isLoading = false
                        timeoutTask.cancel()
                    }
                    fullText += chunk
                    streamingText = fullText
                    messages[assistantIndex].content = fullText

                case .done:
                    timeoutTask.cancel()
                    isStreaming = false
                    isLoading = false
                    streamingText = ""
                    messages[assistantIndex].content = fullText

                case .error(let errorMsg):
                    timeoutTask.cancel()
                    self.error = errorMsg
                    isStreaming = false
                    isLoading = false
                    if messages[assistantIndex].content.isEmpty {
                        messages.removeLast()
                    }
                }
            }

            // Handle stream ending without .done
            timeoutTask.cancel()
            if isStreaming || isLoading {
                isStreaming = false
                streamingText = ""
                isLoading = false
                if fullText.isEmpty && messages[assistantIndex].content.isEmpty {
                    messages.removeLast()
                }
            }

        } catch {
            timeoutTask.cancel()
            self.error = error.localizedDescription
            isStreaming = false
            isLoading = false
        }
    }
}

// MARK: - Ephemeral Message

struct EphemeralMessage: Identifiable {
    let id = UUID()
    var content: String
    let isUser: Bool
    let timestamp = Date()
    var sourcesJSON: String?
    var toolCallsJSON: String?

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    var sourceIds: [String] {
        guard let json = sourcesJSON, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var decodedToolCalls: [InlineToolCall]? {
        guard let json = toolCallsJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([InlineToolCall].self, from: data)
    }
}

// MARK: - Liquid Glass Modifier

private struct ConversationLiquidGlassInputBarModifier: ViewModifier {
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

// MARK: - Ephemeral Message Bubble

/// Reuses the same visual style as MessageBubble but works with EphemeralMessage
struct EphemeralMessageBubble: View {
    let message: EphemeralMessage
    var isStreaming: Bool = false
    @State private var citationSourceIds: [String] = []
    @State private var showCitationSheet = false

    var body: some View {
        // Hide empty AI placeholder messages (shown during thinking before streaming starts)
        // But show if tool calls exist — the action snippet should be visible during "Preparing..."
        if !message.isUser && message.content.isEmpty && !isStreaming && (message.decodedToolCalls ?? []).isEmpty {
            EmptyView()
        } else if message.isUser {
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
            HStack(alignment: .top, spacing: LisnSpacing.xs) {
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

                    // Tool call action snippets
                    if let toolCalls = message.decodedToolCalls, !toolCalls.isEmpty {
                        ForEach(toolCalls) { toolCall in
                            ActionSnippetView(toolCall: toolCall)
                        }
                    }

                    HStack(spacing: 4) {
                        if isStreaming {
                            StreamingCursor()
                        }
                        Text(message.formattedTime)
                            .font(LisnFont.labelSmall())
                            .foregroundColor(LisnColors.textTertiary)
                    }

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

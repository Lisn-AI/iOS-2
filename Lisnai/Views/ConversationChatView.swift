import SwiftUI
import SwiftData
import MarkdownUI

/// Per-recording chat — messages are persisted via ChatService with recordingId scoping
struct ConversationChatView: View {
    let recording: Recording
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var chatService: ChatService?
    @State private var inputText = ""
    @State private var showClearConfirm = false
    @FocusState private var isInputFocused: Bool

    /// Build rich context from recording's transcript + summary + insights
    private var recordingContext: String {
        var parts: [String] = []

        if let summary = recording.summary?.text {
            parts.append("## Summary\n\(summary)")
        }

        if let transcript = recording.transcription?.text {
            parts.append("## Full Transcript\n\(transcript)")
        }

        if let insight = recording.insight {
            var insightText = "## Insight\n"
            insightText += "Setting: \(insight.setting)\n"
            if let mood = insight.mood { insightText += "Mood: \(mood)\n" }
            insightText += insight.thirdPersonTake
            let ideas = insight.actionableIdeas
            if !ideas.isEmpty {
                insightText += "\n\nActionable Ideas:\n" + ideas.map { "- \($0)" }.joined(separator: "\n")
            }
            parts.append(insightText)
        }

        return parts.isEmpty ? "No recording data available." : parts.joined(separator: "\n\n---\n\n")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let service = chatService {
                    messagesScrollView(service: service)
                }

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
                        if let error = chatService?.error {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            showClearConfirm = true
                        } label: {
                            Label("Clear Chat", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }
            }
            .confirmationDialog("Clear Chat", isPresented: $showClearConfirm) {
                Button("Clear All Messages", role: .destructive) {
                    chatService?.clearHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all messages in this recording's chat.")
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if chatService == nil {
                chatService = ChatService(modelContext: modelContext, recordingId: recording.id)
            }
            chatService?.loadHistory()
        }
        .onTapGesture { isInputFocused = false }
    }

    // MARK: - Messages

    private func messagesScrollView(service: ChatService) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: LisnSpacing.xxxs) {
                    if service.messages.isEmpty && !service.isLoading {
                        conversationContextBanner
                            .padding(.top, LisnSpacing.md)
                    }

                    ForEach(service.messages) { message in
                        MessageBubble(
                            message: message,
                            isStreaming: !message.isUser && message.id == service.messages.last?.id && service.isStreaming
                        )
                        .id(message.id)
                    }

                    if service.isLoading && !service.isStreaming {
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
            .onChange(of: service.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: service.isLoading) { _, loading in
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
                withAnimation { chatService?.error = nil }
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
        && !(chatService?.isLoading ?? false) && !(chatService?.isStreaming ?? false)
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

        Task {
            await chatService?.sendMessageWithContext(text, context: recordingContext, chatMode: "conversation")
        }
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

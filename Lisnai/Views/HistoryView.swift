import SwiftUI
import SwiftData
import MarkdownUI

/// View showing recording history organized by date
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.date, order: .reverse) private var recordings: [Recording]

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    VStack {
                        Spacer()
                        LisnEmptyState(
                            icon: "clock.badge.questionmark",
                            title: "No recordings yet",
                            subtitle: "Start recording your day and your memories will appear here."
                        )
                        Spacer()
                    }
                } else {
                    recordingsList
                }
            }
            .safeAreaInset(edge: .top) {
                Text("History")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(LisnColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, LisnSpacing.sm)
                    .padding(.bottom, LisnSpacing.xs)
                    .background(LisnColors.bgPrimary)
            }
            .toolbar(.hidden, for: .navigationBar)
            .contentMargins(.bottom, 68, for: .scrollContent)
        }
        .background(LisnColors.bgPrimary)
    }

    // MARK: - Subviews

    private var recordingsList: some View {
        List {
            ForEach(groupedRecordings, id: \.key) { date, dayRecordings in
                Section {
                    ForEach(dayRecordings, id: \.id) { recording in
                        NavigationLink {
                            RecordingDetailView(recording: recording)
                        } label: {
                            RecordingRow(recording: recording)
                        }
                        .listRowBackground(LisnColors.bgPrimary)
                    }
                    .onDelete { indexSet in
                        deleteRecordings(at: indexSet, from: dayRecordings)
                    }
                } header: {
                    Text(formatSectionDate(date))
                        .lisnSectionHeader()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LisnColors.bgPrimary)
    }

    // MARK: - Grouped Data

    private var groupedRecordings: [(key: Date, value: [Recording])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: recordings) { recording in
            calendar.startOfDay(for: recording.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    // MARK: - Helpers

    private func formatSectionDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
    }

    private func deleteRecordings(at offsets: IndexSet, from dayRecordings: [Recording]) {
        for index in offsets {
            let recording = dayRecordings[index]
            modelContext.delete(recording)
        }
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording

    var body: some View {
        HStack(spacing: LisnSpacing.md) {
            // Animated icon based on recording category
            RecordingIconView(recording: recording, size: 44)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                // Title or time
                Text(recording.title ?? formatTime(recording.date))
                    .font(LisnFont.bodyMedium())
                    .fontWeight(.semibold)
                    .foregroundColor(LisnColors.textPrimary)
                    .lineLimit(1)

                // Time + duration subtitle
                HStack(spacing: LisnSpacing.xs) {
                    Text(formatTime(recording.date))
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)

                    if recording.duration > 0 {
                        Text("·")
                            .foregroundColor(LisnColors.textTertiary)
                        Text(recording.formattedDuration)
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textTertiary)
                    }
                }

                // Summary preview
                if let summary = recording.summary {
                    Text(summary.text)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, LisnSpacing.xxs)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Recording Detail View

struct RecordingDetailView: View {
    let recording: Recording
    @State private var selectedTab = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("Summary").tag(0)
                    if recording.insight != nil {
                        Text("Insight").tag(2)
                    }
                    Text("Transcription").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                // Metadata
                HStack {
                    Label(recording.formattedDate, systemImage: "calendar")
                    Spacer()
                    if recording.duration > 0 {
                        Label(recording.formattedDuration, systemImage: "clock")
                    }
                }
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
                .padding(.horizontal)

                Divider()
                    .padding(.horizontal)
                    .padding(.vertical, LisnSpacing.sm)

                // Content based on tab
                Group {
                    if selectedTab == 0 {
                        summaryContent
                    } else if selectedTab == 2 {
                        insightContent
                    } else {
                        transcriptionContent
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, LisnSpacing.md)
            }
        }
        .contentMargins(.bottom, recording.summary != nil ? 140 : 76, for: .scrollContent)
        .overlay(alignment: .bottom) {
            if recording.summary != nil {
                ConversationChatBar(recording: recording)
                    .padding(.bottom, 76) // Clear the floating pill tab bar + calendar button
            }
        }
        .navigationTitle(recording.title ?? "Recording")
        .navigationBarTitleDisplayMode(.inline)
        .background(LisnColors.bgPrimary)
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summary = recording.summary {
            Markdown(summary.text.lisnNormalizedMarkdown)
                .markdownTheme(.lisnContent)
        } else {
            Text("No summary available")
                .font(LisnFont.bodyLarge())
                .foregroundColor(LisnColors.textSecondary)
                .italic()
        }
    }

    @ViewBuilder
    private var insightContent: some View {
        if let insight = recording.insight {
            InsightDetailView(insight: insight)
        } else {
            Text("No insight available")
                .font(LisnFont.bodyLarge())
                .foregroundColor(LisnColors.textSecondary)
                .italic()
        }
    }

    @ViewBuilder
    private var transcriptionContent: some View {
        if let transcription = recording.transcription {
            FormattedTranscriptionView(text: transcription.text)
                .textSelection(.enabled)
        } else {
            Text("No transcription available")
                .font(LisnFont.bodyLarge())
                .foregroundColor(LisnColors.textSecondary)
                .italic()
        }
    }
}

// MARK: - Conversation Chat Bar

struct ConversationChatBar: View {
    let recording: Recording
    @State private var showChat = false

    var body: some View {
        Button { showChat = true } label: {
            HStack(spacing: 12) {
                Text("Ask about this conversation...")
                    .font(.system(size: 16))
                    .foregroundColor(LisnColors.textTertiary.opacity(0.5))

                Spacer()

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(LisnColors.textTertiary.opacity(0.3))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .modifier(ConversationChatBarGlassModifier())
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, 10)
        .sheet(isPresented: $showChat) {
            ConversationChatView(recording: recording)
        }
    }
}

private struct ConversationChatBarGlassModifier: ViewModifier {
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


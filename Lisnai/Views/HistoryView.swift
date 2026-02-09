import SwiftUI
import SwiftData

/// View showing recording history organized by date
struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Recording.date, order: .reverse) private var recordings: [Recording]

    var body: some View {
        NavigationStack {
            Group {
                if recordings.isEmpty {
                    emptyStateView
                } else {
                    recordingsList
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.5))

            Text("No recordings yet")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Start recording your day and your memories will appear here.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

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
                    }
                    .onDelete { indexSet in
                        deleteRecordings(at: indexSet, from: dayRecordings)
                    }
                } header: {
                    Text(formatSectionDate(date))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .listStyle(.insetGrouped)
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
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 44, height: 44)

                Image(systemName: "waveform")
                    .foregroundColor(.blue)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(formatTime(recording.date))
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Label(recording.formattedDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if recording.summary != nil {
                        Label("Summary", systemImage: "doc.text")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            Spacer()

            // Sync indicator
            if recording.isSynced {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
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

    var body: some View {
        VStack(spacing: 0) {
            // Tab picker
            Picker("View", selection: $selectedTab) {
                Text("Summary").tag(0)
                Text("Transcription").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Metadata
                    HStack {
                        Label(recording.formattedDate, systemImage: "calendar")
                        Spacer()
                        Label(recording.formattedDuration, systemImage: "clock")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    Divider()

                    // Content based on tab
                    if selectedTab == 0 {
                        summaryContent
                    } else {
                        transcriptionContent
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var summaryContent: some View {
        if let summary = recording.summary {
            Text(summary.text)
                .font(.body)
        } else {
            Text("No summary available")
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
        }
    }

    @ViewBuilder
    private var transcriptionContent: some View {
        if let transcription = recording.transcription {
            Text(transcription.text)
                .font(.body)
                .textSelection(.enabled)
        } else {
            Text("No transcription available")
                .font(.body)
                .foregroundColor(.secondary)
                .italic()
        }
    }
}

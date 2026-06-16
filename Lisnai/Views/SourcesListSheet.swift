import SwiftUI
import SwiftData

/// Bottom sheet listing source recordings/memories used in a chat response
struct SourcesListSheet: View {
    let sourceIds: [String]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var items: [(memory: LocalMemory, recording: Recording?)] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: LisnSpacing.md) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 40))
                            .foregroundColor(LisnColors.textTertiary)
                        Text("No matching local memories found")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                        Text("Sources: \(sourceIds.joined(separator: ", "))")
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List(items, id: \.memory.id) { item in
                        if let recording = item.recording {
                            NavigationLink(destination: RecordingDetailView(recording: recording)) {
                                SourceRow(memory: item.memory, recordingTitle: recording.title)
                            }
                            .listRowBackground(LisnColors.bgPrimary)
                        } else {
                            SourceRow(memory: item.memory)
                                .listRowBackground(LisnColors.bgPrimary)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(LisnColors.bgPrimary)
            .navigationTitle("Sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { loadMemories() }
    }

    private func loadMemories() {
        let descriptor = FetchDescriptor<LocalMemory>()
        guard let allMemories = try? modelContext.fetch(descriptor) else { return }

        let matched = allMemories.filter { memory in
            let serverId = memory.serverMemoryId ?? ""
            let localId = memory.id.uuidString
            return sourceIds.contains(serverId) || sourceIds.contains(localId)
        }

        items = matched.map { memory in
            let recording = linkedRecording(for: memory)
            return (memory: memory, recording: recording)
        }
    }

    private func linkedRecording(for memory: LocalMemory) -> Recording? {
        // Direct link via recordingId (set for memories created after this fix)
        if let recordingId = memory.recordingId {
            let descriptor = FetchDescriptor<Recording>(
                predicate: #Predicate { $0.id == recordingId }
            )
            if let recording = try? modelContext.fetch(descriptor).first {
                return recording
            }
        }

        // Fallback: match by timestamp proximity (for legacy memories)
        let ts = memory.timestamp
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: ts)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let recordings = try? modelContext.fetch(descriptor) else { return nil }
        return recordings.min(by: {
            abs($0.date.timeIntervalSince(ts)) < abs($1.date.timeIntervalSince(ts))
        })
    }
}

// MARK: - Source Row

private struct SourceRow: View {
    let memory: LocalMemory
    var recordingTitle: String? = nil

    private var displayTitle: String {
        recordingTitle ?? memory.title ?? "Recording"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LisnColors.accent)

                Text(displayTitle)
                    .font(LisnFont.bodyMedium())
                    .fontWeight(.semibold)
                    .foregroundColor(LisnColors.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text(formatDate(memory.timestamp))
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textTertiary)
            }

            if let summary = memory.summary {
                Text(summary)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(3)
            }

            if !memory.topics.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(memory.topics.prefix(4), id: \.self) { topic in
                        Text(topic)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(LisnColors.bgSecondary)
                            .foregroundColor(LisnColors.textSecondary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, LisnSpacing.xxs)
    }

    private func formatDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

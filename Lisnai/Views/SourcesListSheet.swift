import SwiftUI
import SwiftData

/// Bottom sheet listing source recordings/memories used in a chat response
struct SourcesListSheet: View {
    let sourceIds: [String]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var memories: [LocalMemory] = []

    var body: some View {
        NavigationStack {
            Group {
                if memories.isEmpty {
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
                    List(memories, id: \.id) { memory in
                        SourceRow(memory: memory)
                            .listRowBackground(LisnColors.bgPrimary)
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

        memories = allMemories.filter { memory in
            let serverId = memory.serverMemoryId ?? ""
            let localId = memory.id.uuidString
            return sourceIds.contains(serverId) || sourceIds.contains(localId)
        }
    }
}

// MARK: - Source Row

private struct SourceRow: View {
    let memory: LocalMemory

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LisnColors.accent)

                Text(memory.title ?? "Recording")
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

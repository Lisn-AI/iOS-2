import SwiftUI

/// View for displaying daily briefings - summaries of the user's day
struct BriefingsView: View {
    @StateObject private var viewModel = BriefingsViewModel()
    @State private var selectedDate = Date()
    @State private var showDatePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LisnSpacing.lg) {
                    // Date selector
                    dateSelector

                    if viewModel.isLoading {
                        loadingView
                    } else if let briefing = viewModel.briefing {
                        briefingContent(briefing)
                    } else {
                        emptyStateView
                    }
                }
                .padding()
            }
            .background(LisnColors.bgPrimary)
            .navigationTitle("Daily Briefing")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.triggerBriefing() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.loadBriefing(for: selectedDate)
            }
            .onChange(of: selectedDate) { _, newDate in
                Task { await viewModel.loadBriefing(for: newDate) }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Date Selector

    private var dateSelector: some View {
        GlassCard {
            HStack {
                Button(action: {
                    selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
                }) {
                    Image(systemName: "chevron.left")
                        .font(LisnFont.titleLarge())
                        .foregroundColor(LisnColors.accent)
                }

                Spacer()

                Button(action: { showDatePicker = true }) {
                    VStack(spacing: 2) {
                        Text(formattedDate(selectedDate))
                            .font(LisnFont.titleMedium())
                            .fontWeight(.semibold)

                        if Calendar.current.isDateInToday(selectedDate) {
                            Text("Today")
                                .font(LisnFont.caption())
                                .foregroundColor(LisnColors.accent)
                        } else if Calendar.current.isDateInYesterday(selectedDate) {
                            Text("Yesterday")
                                .font(LisnFont.caption())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                    }
                }
                .foregroundColor(LisnColors.textPrimary)
                .sheet(isPresented: $showDatePicker) {
                    DatePickerSheet(selectedDate: $selectedDate)
                }

                Spacer()

                Button(action: {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
                    if tomorrow <= Date() {
                        selectedDate = tomorrow
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(LisnFont.titleLarge())
                        .foregroundColor(canGoForward ? LisnColors.accent : .gray)
                }
                .disabled(!canGoForward)
            }
        }
    }

    private var canGoForward: Bool {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        return tomorrow <= Date()
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: date)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: LisnSpacing.md) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Generating briefing...")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        LisnEmptyState(
            icon: "sun.haze",
            title: "No Briefing Available",
            subtitle: "Start recording conversations to generate daily briefings",
            actionTitle: "Generate Briefing",
            action: { Task { await viewModel.triggerBriefing() } }
        )
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: BriefingResponse) -> some View {
        VStack(spacing: LisnSpacing.lg) {
            // Summary Card
            summaryCard(briefing)

            // Key Moments
            if !briefing.keyMoments.isEmpty {
                keyMomentsCard(briefing.keyMoments)
            }

            // People Interacted
            if let people = briefing.peopleInteracted, !people.isEmpty {
                peopleCard(people)
            }

            // Pending Tasks
            if let tasks = briefing.pendingTasks, !tasks.isEmpty {
                tasksCard(tasks)
            }

            // Insight
            if let insight = briefing.insightfulObservation {
                insightCard(insight)
            }
        }
    }

    private func summaryCard(_ briefing: BriefingResponse) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                HStack {
                    Image(systemName: moodIcon(briefing.mood))
                        .font(LisnFont.titleLarge())
                        .foregroundColor(moodColor(briefing.mood))

                    Text("Summary")
                        .font(LisnFont.titleSmall())

                    Spacer()

                    if let mood = briefing.mood {
                        Text(mood.capitalized)
                            .font(LisnFont.caption())
                            .padding(.horizontal, LisnSpacing.xs)
                            .padding(.vertical, 4)
                            .background(moodColor(briefing.mood).opacity(0.2))
                            .cornerRadius(LisnRadius.sm)
                    }
                }

                Text(briefing.summary)
                    .font(LisnFont.bodyLarge())
                    .foregroundColor(LisnColors.textSecondary)
            }
        }
    }

    private func keyMomentsCard(_ moments: [String]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                HStack {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                    Text("Key Moments")
                        .font(LisnFont.titleSmall())
                }

                VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                    ForEach(moments.indices, id: \.self) { index in
                        HStack(alignment: .top, spacing: LisnSpacing.xs) {
                            Text("\(index + 1)")
                                .font(LisnFont.captionBold())
                                .foregroundColor(.white)
                                .frame(width: 20, height: 20)
                                .background(LisnColors.accent)
                                .clipShape(Circle())

                            Text(moments[index])
                                .font(LisnFont.bodyMedium())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func peopleCard(_ people: [String]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(LisnColors.accent)
                    Text("People You Interacted With")
                        .font(LisnFont.titleSmall())
                }

                FlowLayout(spacing: LisnSpacing.xs) {
                    ForEach(people, id: \.self) { person in
                        LisnChip(text: person, icon: "person.fill", color: LisnColors.accent)
                    }
                }
            }
        }
    }

    private func tasksCard(_ tasks: [String]) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                HStack {
                    Image(systemName: "checklist")
                        .foregroundColor(LisnColors.warning)
                    Text("Pending Tasks")
                        .font(LisnFont.titleSmall())
                }

                VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                    ForEach(tasks, id: \.self) { task in
                        HStack(alignment: .top, spacing: LisnSpacing.xs) {
                            Image(systemName: "circle")
                                .font(LisnFont.caption())
                                .foregroundColor(LisnColors.warning)

                            Text(task)
                                .font(LisnFont.bodyMedium())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func insightCard(_ insight: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.yellow)
                    Text("Insight")
                        .font(LisnFont.titleSmall())
                }

                Text(insight)
                    .font(LisnFont.bodyLarge())
                    .italic()
                    .foregroundColor(LisnColors.textSecondary)
            }
        }
        .background(LisnColors.accent.opacity(0.08))
        .cornerRadius(LisnRadius.md)
    }

    private func moodIcon(_ mood: String?) -> String {
        switch mood?.lowercased() {
        case "happy", "positive", "joyful": return "face.smiling.fill"
        case "sad", "negative", "down": return "face.dashed"
        case "stressed", "anxious": return "exclamationmark.triangle.fill"
        case "productive", "focused": return "bolt.fill"
        case "calm", "relaxed": return "leaf.fill"
        default: return "face.smiling"
        }
    }

    private func moodColor(_ mood: String?) -> Color {
        switch mood?.lowercased() {
        case "happy", "positive", "joyful": return LisnColors.success
        case "sad", "negative", "down": return LisnColors.info
        case "stressed", "anxious": return LisnColors.error
        case "productive", "focused": return LisnColors.warning
        case "calm", "relaxed": return .teal
        default: return LisnColors.textSecondary
        }
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - View Model

@MainActor
class BriefingsViewModel: ObservableObject {
    @Published var briefing: BriefingResponse?
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let api = APIService.shared

    func loadBriefing(for date: Date) async {
        isLoading = true

        do {
            briefing = try await api.getBriefing(date: date)
        } catch {
            // If 404, no briefing exists for this date
            if case APIError.notFound = error {
                briefing = nil
            } else {
                errorMessage = error.localizedDescription
                showError = true
            }
        }

        isLoading = false
    }

    func triggerBriefing() async {
        isLoading = true

        do {
            _ = try await api.triggerBriefing()
            // Reload the briefing after triggering
            await loadBriefing(for: Date())
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

#Preview {
    BriefingsView()
}

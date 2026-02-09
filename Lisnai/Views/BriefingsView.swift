import SwiftUI

/// View for displaying daily briefings - summaries of the user's day
struct BriefingsView: View {
    @StateObject private var viewModel = BriefingsViewModel()
    @State private var selectedDate = Date()
    @State private var showDatePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
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
        HStack {
            Button(action: {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            }) {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundColor(.blue)
            }

            Spacer()

            Button(action: { showDatePicker = true }) {
                VStack(spacing: 2) {
                    Text(formattedDate(selectedDate))
                        .font(.title3)
                        .fontWeight(.semibold)

                    if Calendar.current.isDateInToday(selectedDate) {
                        Text("Today")
                            .font(.caption)
                            .foregroundColor(.blue)
                    } else if Calendar.current.isDateInYesterday(selectedDate) {
                        Text("Yesterday")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .foregroundColor(.primary)
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
                    .font(.title2)
                    .foregroundColor(canGoForward ? .blue : .gray)
            }
            .disabled(!canGoForward)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
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
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Generating briefing...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sun.haze")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            Text("No Briefing Available")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Start recording conversations to generate daily briefings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(action: { Task { await viewModel.triggerBriefing() } }) {
                Label("Generate Briefing", systemImage: "sparkles")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.top)
        }
        .padding()
    }

    // MARK: - Briefing Content

    @ViewBuilder
    private func briefingContent(_ briefing: BriefingResponse) -> some View {
        VStack(spacing: 20) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: moodIcon(briefing.mood))
                    .font(.title2)
                    .foregroundColor(moodColor(briefing.mood))

                Text("Summary")
                    .font(.headline)

                Spacer()

                if let mood = briefing.mood {
                    Text(mood.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(moodColor(briefing.mood).opacity(0.2))
                        .cornerRadius(8)
                }
            }

            Text(briefing.summary)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func keyMomentsCard(_ moments: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text("Key Moments")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(moments.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 20, height: 20)
                            .background(Color.blue)
                            .clipShape(Circle())

                        Text(moments[index])
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func peopleCard(_ people: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .foregroundColor(.blue)
                Text("People You Interacted With")
                    .font(.headline)
            }

            FlowLayout(spacing: 8) {
                ForEach(people, id: \.self) { person in
                    Label(person, systemImage: "person.fill")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(16)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func tasksCard(_ tasks: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checklist")
                    .foregroundColor(.orange)
                Text("Pending Tasks")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(tasks, id: \.self) { task in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle")
                            .font(.caption)
                            .foregroundColor(.orange)

                        Text(task)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func insightCard(_ insight: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.yellow)
                Text("Insight")
                    .font(.headline)
            }

            Text(insight)
                .font(.body)
                .italic()
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.yellow.opacity(0.1), Color.orange.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(12)
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
        case "happy", "positive", "joyful": return .green
        case "sad", "negative", "down": return .blue
        case "stressed", "anxious": return .red
        case "productive", "focused": return .orange
        case "calm", "relaxed": return .teal
        default: return .secondary
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

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)

        for (index, subview) in subviews.enumerated() {
            let point = CGPoint(
                x: bounds.minX + result.positions[index].x,
                y: bounds.minY + result.positions[index].y
            )
            subview.place(at: point, anchor: .topLeading, proposal: .unspecified)
        }
    }

    private struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxRowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += maxRowHeight + spacing
                    maxRowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                maxRowHeight = max(maxRowHeight, size.height)
                x += size.width + spacing
            }

            height = y + maxRowHeight
        }
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

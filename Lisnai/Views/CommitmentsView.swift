import SwiftUI

/// View for displaying and managing user commitments detected from conversations
struct CommitmentsView: View {
    @StateObject private var viewModel = CommitmentsViewModel()
    @State private var selectedFilter: CommitmentFilter = .all
    @State private var selectedCommitment: Commitment?
    @State private var showDetailSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.commitments.isEmpty {
                    ProgressView("Loading commitments...")
                } else if viewModel.commitments.isEmpty {
                    emptyStateView
                } else {
                    commitmentsList
                }
            }
            .navigationTitle("Commitments")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(CommitmentFilter.allCases, id: \.self) { filter in
                            Button(action: { selectedFilter = filter }) {
                                HStack {
                                    Text(filter.displayName)
                                    if selectedFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadData()
            }
            .sheet(isPresented: $showDetailSheet) {
                if let commitment = selectedCommitment {
                    CommitmentDetailSheet(
                        commitment: commitment,
                        onComplete: {
                            Task {
                                await viewModel.completeCommitment(commitment)
                                showDetailSheet = false
                                selectedCommitment = nil
                            }
                        }
                    )
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Filter

    enum CommitmentFilter: String, CaseIterable {
        case all = "all"
        case active = "active"
        case pending = "pending"
        case completed = "completed"

        var displayName: String {
            switch self {
            case .all: return "All"
            case .active: return "Active"
            case .pending: return "Pending"
            case .completed: return "Completed"
            }
        }
    }

    private var filteredCommitments: [Commitment] {
        switch selectedFilter {
        case .all:
            return viewModel.commitments
        case .active:
            return viewModel.commitments.filter { $0.status == "active" || $0.status == "pending" }
        case .pending:
            return viewModel.commitments.filter { $0.status == "pending" }
        case .completed:
            return viewModel.commitments.filter { $0.status == "completed" }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Commitments",
            systemImage: "checkmark.seal",
            description: Text("Commitments you make during conversations will be tracked here")
        )
    }

    // MARK: - Commitments List

    private var commitmentsList: some View {
        List {
            // Summary section
            if selectedFilter == .all || selectedFilter == .active {
                Section {
                    HStack(spacing: 16) {
                        StatBox(
                            title: "Active",
                            count: viewModel.commitments.filter { $0.status != "completed" }.count,
                            color: .blue
                        )
                        StatBox(
                            title: "Due Today",
                            count: viewModel.commitments.filter { isDueToday($0) }.count,
                            color: .orange
                        )
                        StatBox(
                            title: "Overdue",
                            count: viewModel.commitments.filter { isOverdue($0) }.count,
                            color: .red
                        )
                    }
                    .padding(.vertical, 4)
                }
            }

            // Group by urgency
            ForEach(groupedCommitments.keys.sorted(), id: \.self) { urgency in
                Section {
                    ForEach(groupedCommitments[urgency] ?? []) { commitment in
                        CommitmentRow(commitment: commitment)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCommitment = commitment
                                showDetailSheet = true
                            }
                            .swipeActions(edge: .trailing) {
                                if commitment.status != "completed" {
                                    Button {
                                        Task { await viewModel.completeCommitment(commitment) }
                                    } label: {
                                        Label("Complete", systemImage: "checkmark")
                                    }
                                    .tint(.green)
                                }
                            }
                    }
                } header: {
                    Label(urgencyHeader(urgency), systemImage: urgencyIcon(urgency))
                        .foregroundColor(urgencyColor(urgency))
                }
            }
        }
    }

    private var groupedCommitments: [String: [Commitment]] {
        Dictionary(grouping: filteredCommitments) { $0.urgency }
    }

    private func isDueToday(_ commitment: Commitment) -> Bool {
        guard let dueDateString = commitment.dueDate else { return false }
        let formatter = ISO8601DateFormatter()
        guard let dueDate = formatter.date(from: dueDateString) else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    private func isOverdue(_ commitment: Commitment) -> Bool {
        guard let dueDateString = commitment.dueDate,
              commitment.status != "completed" else { return false }
        let formatter = ISO8601DateFormatter()
        guard let dueDate = formatter.date(from: dueDateString) else { return false }
        return dueDate < Date()
    }

    private func urgencyHeader(_ urgency: String) -> String {
        switch urgency.lowercased() {
        case "high": return "High Priority"
        case "medium": return "Medium Priority"
        case "low": return "Low Priority"
        default: return urgency.capitalized
        }
    }

    private func urgencyIcon(_ urgency: String) -> String {
        switch urgency.lowercased() {
        case "high": return "exclamationmark.triangle.fill"
        case "medium": return "exclamationmark.circle.fill"
        case "low": return "minus.circle.fill"
        default: return "circle.fill"
        }
    }

    private func urgencyColor(_ urgency: String) -> Color {
        switch urgency.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .blue
        default: return .secondary
        }
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Commitment Row

struct CommitmentRow: View {
    let commitment: Commitment

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Image(systemName: statusIcon)
                .font(.title2)
                .foregroundColor(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(commitment.description)
                    .font(.headline)
                    .strikethrough(commitment.status == "completed")

                HStack(spacing: 8) {
                    // Type badge
                    Label(commitment.type.capitalized, systemImage: typeIcon)
                        .font(.caption)
                        .foregroundColor(.blue)

                    // Person if present
                    if let person = commitment.person {
                        Text("-")
                            .foregroundColor(.secondary)
                        Label(person, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Due date
                if let dueDateString = commitment.dueDate {
                    Text(formattedDueDate(dueDateString))
                        .font(.caption)
                        .foregroundColor(dueDateColor(dueDateString))
                }
            }

            Spacer()

            if commitment.status != "completed" {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
        .opacity(commitment.status == "completed" ? 0.6 : 1.0)
    }

    private var statusIcon: String {
        switch commitment.status.lowercased() {
        case "completed": return "checkmark.circle.fill"
        case "overdue": return "exclamationmark.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch commitment.status.lowercased() {
        case "completed": return .green
        case "overdue": return .red
        default: return .blue
        }
    }

    private var typeIcon: String {
        switch commitment.type.lowercased() {
        case "call": return "phone.fill"
        case "meeting": return "person.2.fill"
        case "task": return "checklist"
        case "follow_up": return "arrow.turn.up.right"
        case "delivery": return "shippingbox.fill"
        default: return "star.fill"
        }
    }

    private func formattedDueDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        if Calendar.current.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Due today at \(timeFormatter.string(from: date))"
        } else if Calendar.current.isDateInTomorrow(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Due tomorrow at \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return "Due \(dateFormatter.string(from: date))"
        }
    }

    private func dueDateColor(_ dateString: String) -> Color {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return .secondary }

        if date < Date() && commitment.status != "completed" {
            return .red
        } else if Calendar.current.isDateInToday(date) {
            return .orange
        }
        return .secondary
    }
}

// MARK: - Commitment Detail Sheet

struct CommitmentDetailSheet: View {
    let commitment: Commitment
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 48))
                            .foregroundColor(typeColor)

                        Text(commitment.description)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Label(commitment.type.capitalized, systemImage: typeIcon)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(typeColor.opacity(0.2))
                                .foregroundColor(typeColor)
                                .cornerRadius(12)

                            Label(commitment.urgency.capitalized, systemImage: urgencyIcon)
                                .font(.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(urgencyColor.opacity(0.2))
                                .foregroundColor(urgencyColor)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.top)

                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        if let person = commitment.person {
                            DetailRow(icon: "person.fill", title: "Person", value: person)
                        }

                        if let dueDate = commitment.dueDate {
                            DetailRow(icon: "calendar", title: "Due Date", value: formattedDate(dueDate))
                        }

                        DetailRow(icon: "clock.fill", title: "Created", value: formattedDate(commitment.createdAt))

                        DetailRow(icon: "flag.fill", title: "Status", value: commitment.status.capitalized)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    Spacer()

                    // Actions
                    if commitment.status != "completed" {
                        Button(action: onComplete) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Mark as Complete")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var typeIcon: String {
        switch commitment.type.lowercased() {
        case "call": return "phone.fill"
        case "meeting": return "person.2.fill"
        case "task": return "checklist"
        case "follow_up": return "arrow.turn.up.right"
        case "delivery": return "shippingbox.fill"
        default: return "star.fill"
        }
    }

    private var typeColor: Color {
        switch commitment.type.lowercased() {
        case "call": return .green
        case "meeting": return .purple
        case "task": return .blue
        case "follow_up": return .orange
        case "delivery": return .cyan
        default: return .yellow
        }
    }

    private var urgencyIcon: String {
        switch commitment.urgency.lowercased() {
        case "high": return "exclamationmark.triangle.fill"
        case "medium": return "exclamationmark.circle.fill"
        case "low": return "minus.circle.fill"
        default: return "circle.fill"
        }
    }

    private var urgencyColor: Color {
        switch commitment.urgency.lowercased() {
        case "high": return .red
        case "medium": return .orange
        case "low": return .blue
        default: return .secondary
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 24)

            Text(title)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .fontWeight(.medium)
        }
    }
}

// MARK: - View Model

@MainActor
class CommitmentsViewModel: ObservableObject {
    @Published var commitments: [Commitment] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let api = APIService.shared

    func loadData() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true

        do {
            let response = try await api.getCommitments()
            commitments = response.commitments
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func completeCommitment(_ commitment: Commitment) async {
        do {
            _ = try await api.completeCommitment(commitmentId: commitment.id)

            // Update local state
            if let index = commitments.firstIndex(where: { $0.id == commitment.id }) {
                let updated = commitments[index]
                // Create new commitment with completed status
                commitments[index] = Commitment(
                    id: updated.id,
                    description: updated.description,
                    type: updated.type,
                    person: updated.person,
                    dueDate: updated.dueDate,
                    urgency: updated.urgency,
                    status: "completed",
                    createdAt: updated.createdAt
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    CommitmentsView()
}

import SwiftUI

/// View for displaying proactive suggestions from the AI
struct SuggestionsView: View {
    @StateObject private var viewModel = SuggestionsViewModel()
    @State private var selectedSuggestion: ProactiveSuggestion?
    @State private var showDetailSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.suggestions.isEmpty {
                    ProgressView("Loading suggestions...")
                } else if viewModel.suggestions.isEmpty {
                    emptyStateView
                } else {
                    suggestionsList
                }
            }
            .navigationTitle("Suggestions")
            .toolbar {
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
                if let suggestion = selectedSuggestion {
                    SuggestionDetailSheet(
                        suggestion: suggestion,
                        onAccept: {
                            Task {
                                await viewModel.acceptSuggestion(suggestion)
                                showDetailSheet = false
                                selectedSuggestion = nil
                            }
                        },
                        onDismiss: {
                            Task {
                                await viewModel.dismissSuggestion(suggestion)
                                showDetailSheet = false
                                selectedSuggestion = nil
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

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Suggestions",
            systemImage: "lightbulb",
            description: Text("Proactive suggestions based on your conversations will appear here")
        )
    }

    // MARK: - Suggestions List

    private var suggestionsList: some View {
        List {
            ForEach(viewModel.suggestions) { suggestion in
                SuggestionRow(suggestion: suggestion)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSuggestion = suggestion
                        showDetailSheet = true
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.dismissSuggestion(suggestion) }
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task { await viewModel.acceptSuggestion(suggestion) }
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                        }
                        .tint(.green)
                    }
            }
        }
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let suggestion: ProactiveSuggestion

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: typeIcon)
                .font(.title2)
                .foregroundColor(typeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(.headline)

                Text(suggestion.body)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    // Confidence indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(confidenceColor)
                            .frame(width: 8, height: 8)
                        Text(confidenceText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var typeIcon: String {
        switch suggestion.type {
        case "call_reminder": return "phone.fill"
        case "follow_up": return "arrow.turn.up.right"
        case "task_reminder": return "checkmark.circle"
        case "pattern_insight": return "chart.line.uptrend.xyaxis"
        case "connection_prompt": return "person.2.fill"
        case "event_reminder": return "calendar"
        default: return "lightbulb.fill"
        }
    }

    private var typeColor: Color {
        switch suggestion.type {
        case "call_reminder": return .green
        case "follow_up": return .blue
        case "task_reminder": return .orange
        case "pattern_insight": return .purple
        case "connection_prompt": return .pink
        case "event_reminder": return .cyan
        default: return .yellow
        }
    }

    private var confidenceColor: Color {
        if suggestion.confidence >= 0.8 {
            return .green
        } else if suggestion.confidence >= 0.6 {
            return .orange
        } else {
            return .gray
        }
    }

    private var confidenceText: String {
        let percent = Int(suggestion.confidence * 100)
        return "\(percent)% confident"
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: suggestion.createdAt) {
            let relative = RelativeDateTimeFormatter()
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return suggestion.createdAt
    }
}

// MARK: - Suggestion Detail Sheet

struct SuggestionDetailSheet: View {
    let suggestion: ProactiveSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

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

                        Text(suggestion.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text(typeName)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(typeColor.opacity(0.2))
                            .foregroundColor(typeColor)
                            .cornerRadius(12)
                    }
                    .padding(.top)

                    // Body
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggestion")
                            .font(.headline)

                        Text(suggestion.body)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Reasoning
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Why this suggestion?")
                            .font(.headline)

                        Text(suggestion.reasoning)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)

                    // Confidence
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(confidenceColor)
                        Text("Confidence: \(Int(suggestion.confidence * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // Suggested action preview
                    if let action = suggestion.suggestedAction {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggested Action")
                                .font(.headline)

                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.blue)
                                Text("\(action.skill) > \(action.tool)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(12)
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        Button(action: onAccept) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(suggestion.suggestedAction != nil ? "Accept & Execute" : "Mark as Helpful")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button(action: onDismiss) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Not Helpful")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
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
        switch suggestion.type {
        case "call_reminder": return "phone.fill"
        case "follow_up": return "arrow.turn.up.right"
        case "task_reminder": return "checkmark.circle"
        case "pattern_insight": return "chart.line.uptrend.xyaxis"
        case "connection_prompt": return "person.2.fill"
        case "event_reminder": return "calendar"
        default: return "lightbulb.fill"
        }
    }

    private var typeColor: Color {
        switch suggestion.type {
        case "call_reminder": return .green
        case "follow_up": return .blue
        case "task_reminder": return .orange
        case "pattern_insight": return .purple
        case "connection_prompt": return .pink
        case "event_reminder": return .cyan
        default: return .yellow
        }
    }

    private var typeName: String {
        switch suggestion.type {
        case "call_reminder": return "Call Reminder"
        case "follow_up": return "Follow Up"
        case "task_reminder": return "Task Reminder"
        case "pattern_insight": return "Pattern Insight"
        case "connection_prompt": return "Connection Prompt"
        case "event_reminder": return "Event Reminder"
        default: return suggestion.type.capitalized
        }
    }

    private var confidenceColor: Color {
        if suggestion.confidence >= 0.8 {
            return .green
        } else if suggestion.confidence >= 0.6 {
            return .orange
        } else {
            return .gray
        }
    }
}

// MARK: - View Model

@MainActor
class SuggestionsViewModel: ObservableObject {
    @Published var suggestions: [ProactiveSuggestion] = []
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
            let response = try await api.getSuggestions(status: "pending")
            suggestions = response.suggestions
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func acceptSuggestion(_ suggestion: ProactiveSuggestion) async {
        do {
            let response = try await api.acceptSuggestion(suggestionId: suggestion.id)

            // Remove from list
            suggestions.removeAll { $0.id == suggestion.id }

            // If there's a suggested action, we could execute it here
            if let action = response.suggestedAction {
                print("Accepted suggestion with action: \(action.skill) > \(action.tool)")
                // Could trigger action execution here
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func dismissSuggestion(_ suggestion: ProactiveSuggestion) async {
        do {
            _ = try await api.dismissSuggestion(suggestionId: suggestion.id)

            // Remove from list
            suggestions.removeAll { $0.id == suggestion.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    SuggestionsView()
}

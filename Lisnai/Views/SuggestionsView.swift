import SwiftUI

/// View for displaying proactive suggestions from the AI
struct SuggestionsView: View {
    @StateObject private var viewModel = SuggestionsViewModel()
    @State private var selectedSuggestion: ProactiveSuggestion?
    @State private var showDetailSheet = false
    @State private var showSuccessAlert = false
    @State private var successMessage = ""

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
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
                                let result = await viewModel.acceptSuggestion(suggestion)
                                showDetailSheet = false
                                selectedSuggestion = nil

                                // Show success feedback if action was executed
                                if let result = result, result.success && result.requiresUserInput == .none {
                                    successMessage = result.message
                                    showSuccessAlert = true
                                }
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
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(successMessage)
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
                    .listRowBackground(LisnColors.bgElevated)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            Task { await viewModel.dismissSuggestion(suggestion) }
                        } label: {
                            Label("Dismiss", systemImage: "xmark")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            Task {
                                let result = await viewModel.acceptSuggestion(suggestion)
                                if let result = result, result.success && result.requiresUserInput == .none {
                                    successMessage = result.message
                                    showSuccessAlert = true
                                }
                            }
                        } label: {
                            Label("Accept", systemImage: "checkmark")
                        }
                        .tint(LisnColors.success)
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LisnColors.bgPrimary)
    }
}

// MARK: - Suggestion Row

struct SuggestionRow: View {
    let suggestion: ProactiveSuggestion

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            // Type icon
            Image(systemName: typeIcon)
                .font(LisnFont.titleLarge())
                .foregroundColor(typeColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title)
                    .font(LisnFont.titleSmall())

                Text(suggestion.body)
                    .font(LisnFont.bodyMedium())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(2)

                HStack {
                    // Confidence indicator
                    HStack(spacing: 4) {
                        Circle()
                            .fill(confidenceColor)
                            .frame(width: 8, height: 8)
                        Text(confidenceText)
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textSecondary)
                    }

                    Text("\u{2022}")
                        .foregroundColor(LisnColors.textSecondary)

                    Text(formattedDate)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(LisnColors.textSecondary)
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
        case "call_reminder": return LisnColors.success
        case "follow_up": return LisnColors.accent
        case "task_reminder": return LisnColors.warning
        case "pattern_insight": return Color.purple
        case "connection_prompt": return Color.pink
        case "event_reminder": return Color.cyan
        default: return LisnColors.warning
        }
    }

    private var confidenceColor: Color {
        if suggestion.confidence >= 0.8 {
            return LisnColors.success
        } else if suggestion.confidence >= 0.6 {
            return LisnColors.warning
        } else {
            return LisnColors.textTertiary
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
                VStack(spacing: LisnSpacing.xl) {
                    // Header
                    VStack(spacing: LisnSpacing.sm) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 48))
                            .foregroundColor(typeColor)

                        Text(suggestion.title)
                            .font(LisnFont.titleLarge())
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text(typeName)
                            .font(LisnFont.caption())
                            .padding(.horizontal, LisnSpacing.sm)
                            .padding(.vertical, 4)
                            .background(typeColor.opacity(0.2))
                            .foregroundColor(typeColor)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }
                    .padding(.top)

                    // Body
                    GlassCard {
                        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                            Text("Suggestion")
                                .font(LisnFont.titleSmall())

                            Text(suggestion.body)
                                .font(LisnFont.bodyLarge())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Reasoning
                    GlassCard {
                        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                            Text("Why this suggestion?")
                                .font(LisnFont.titleSmall())

                            Text(suggestion.reasoning)
                                .font(LisnFont.bodyLarge())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Confidence
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(confidenceColor)
                        Text("Confidence: \(Int(suggestion.confidence * 100))%")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                    }

                    // Suggested action preview
                    if let action = suggestion.suggestedAction {
                        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                            Text("Suggested Action")
                                .font(LisnFont.titleSmall())

                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(LisnColors.accent)
                                Text("\(action.skill) > \(action.tool)")
                                    .font(LisnFont.bodyMedium())
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(LisnColors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: LisnSpacing.sm) {
                        Button(action: onAccept) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(suggestion.suggestedAction != nil ? "Accept & Execute" : "Mark as Helpful")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LisnColors.success)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                        }

                        Button(action: onDismiss) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Not Helpful")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LisnColors.bgSecondary)
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
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
        case "call_reminder": return LisnColors.success
        case "follow_up": return LisnColors.accent
        case "task_reminder": return LisnColors.warning
        case "pattern_insight": return Color.purple
        case "connection_prompt": return Color.pink
        case "event_reminder": return Color.cyan
        default: return LisnColors.warning
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
            return LisnColors.success
        } else if suggestion.confidence >= 0.6 {
            return LisnColors.warning
        } else {
            return LisnColors.textTertiary
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

    func acceptSuggestion(_ suggestion: ProactiveSuggestion) async -> ActionExecutionResult? {
        do {
            let response = try await api.acceptSuggestion(suggestionId: suggestion.id)

            // Remove from list
            suggestions.removeAll { $0.id == suggestion.id }

            // If there's a suggested action, execute it via ActionExecutor
            if let action = response.suggestedAction {
                print("[SuggestionsVM] Executing action: \(action.skill) > \(action.tool)")

                let executor = ActionExecutor.shared
                let result = await executor.executeSuggestedAction(action, suggestionId: suggestion.id)

                if result.success {
                    print("[SuggestionsVM] Action executed successfully: \(result.message)")
                } else {
                    print("[SuggestionsVM] Action failed: \(result.message)")
                    errorMessage = result.message
                    showError = true
                }

                return result
            }

            return nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return nil
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

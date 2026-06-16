import SwiftUI
import SwiftData

/// View for searching through memories with natural language queries
struct MemorySearchView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var subscriptionService: SubscriptionService
    @StateObject private var viewModel = MemorySearchViewModel()
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var selectedRecording: Recording?
    @State private var selectedTranscript: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var showPaywall = false
    @State private var showLimitCard = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                searchBar

                // Content
                if viewModel.isLoading {
                    loadingView
                } else if !viewModel.results.isEmpty {
                    resultsList
                } else if !searchText.isEmpty && !viewModel.isLoading {
                    noResultsView
                } else {
                    suggestionsView
                }
            }
            .background(LisnColors.bgPrimary)
            .navigationTitle("Search Memories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .navigationDestination(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(item: Binding(
                get: {
                    if let text = selectedTranscript {
                        return TranscriptDetail(text: text)
                    }
                    return nil
                },
                set: { _ in selectedTranscript = nil }
            )) { detail in
                NavigationStack {
                    ScrollView {
                        Text(detail.text)
                            .font(LisnFont.bodyMedium())
                            .padding()
                    }
                    .navigationTitle("Memory")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedTranscript = nil }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .onChange(of: searchText) { _, newValue in
                searchTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    viewModel.results = []
                    return
                }
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    await performSearchAsync()
                }
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(LisnColors.textSecondary)

                TextField("Search your memories...", text: $searchText)
                    .font(LisnFont.bodyMedium())
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        searchTask?.cancel()
                        Task { await performSearchAsync() }
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        viewModel.results = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(LisnColors.bgSecondary)
            .cornerRadius(LisnRadius.sm)

            if isSearching || isSearchFieldFocused {
                Button("Cancel") {
                    searchText = ""
                    isSearchFieldFocused = false
                    viewModel.results = []
                }
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.accent)
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: isSearchFieldFocused)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: LisnSpacing.md) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Searching memories...")
                .font(LisnFont.bodySmall())
                .foregroundColor(LisnColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - No Results View

    private var noResultsView: some View {
        ContentUnavailableView(
            "No Results",
            systemImage: "magnifyingglass",
            description: Text("No memories found for \"\(searchText)\"\nTry a different search query")
        )
    }

    // MARK: - Suggestions View

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LisnSpacing.md) {
                Text("Try searching for:")
                    .font(LisnFont.titleSmall())
                    .padding(.horizontal)

                VStack(spacing: LisnSpacing.sm) {
                    ForEach(searchSuggestions, id: \.self) { suggestion in
                        Button(action: {
                            searchText = suggestion
                            searchTask?.cancel()
                            Task { await performSearchAsync() }
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(LisnColors.textSecondary)
                                Text(suggestion)
                                    .font(LisnFont.bodyMedium())
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(LisnFont.caption())
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                            .padding()
                            .background(LisnColors.bgSecondary)
                            .cornerRadius(LisnRadius.sm)
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                    Text("Search Tips")
                        .font(LisnFont.titleSmall())

                    VStack(alignment: .leading, spacing: 4) {
                        tipRow(icon: "clock", text: "Use time words: \"yesterday\", \"last week\", \"this morning\"")
                        tipRow(icon: "person", text: "Search by name: \"conversation with John\"")
                        tipRow(icon: "tag", text: "Search topics: \"project meeting\", \"dinner plans\"")
                        tipRow(icon: "questionmark.circle", text: "Ask questions: \"What did I discuss about the budget?\"")
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: LisnSpacing.xs) {
            Image(systemName: icon)
                .foregroundColor(LisnColors.accent)
                .frame(width: 20)
            Text(text)
                .font(LisnFont.bodySmall())
                .foregroundColor(LisnColors.textSecondary)
        }
    }

    private var searchSuggestions: [String] {
        [
            "What happened yesterday?",
            "Meetings this week",
            "Conversations about work",
            "Last hour",
            "Plans for tomorrow"
        ]
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text("\(viewModel.results.count) memories found")
                    .font(LisnFont.bodySmall())
                    .foregroundColor(LisnColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, LisnSpacing.sm)

                ForEach(viewModel.results) { result in
                    let recording = viewModel.findRecording(for: result, context: modelContext)

                    Button {
                        if let recording {
                            selectedRecording = recording
                        } else {
                            selectedTranscript = result.transcriptSnippet
                        }
                    } label: {
                        SearchResultRow(result: result, recordingTitle: recording?.title)
                    }
                    .buttonStyle(.plain)

                    if result.id != viewModel.results.last?.id {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func performSearchAsync() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        // Paywall disabled — will enforce via Apple IAP later
        // let limitCheck = subscriptionService.canSearch()
        // if !limitCheck.isAllowed {
        //     showLimitCard = true
        //     return
        // }

        isSearching = true
        await viewModel.search(query: searchText, modelContext: modelContext)
        isSearching = false

        // Sync usage counters after consuming search quota
        await subscriptionService.syncUsageFromBackend()
    }
}

// MARK: - Transcript Detail (for sheet)

private struct TranscriptDetail: Identifiable {
    let id = UUID()
    let text: String
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult
    var recordingTitle: String?

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                // Title
                Text(recordingTitle ?? "Memory")
                    .font(LisnFont.titleSmall())
                    .foregroundColor(LisnColors.textPrimary)
                    .lineLimit(1)

                // Snippet — strip diarization labels like "[Speaker 1] (0:00 - 0:01): "
                Text(cleanedSnippet(result.transcriptSnippet))
                    .font(LisnFont.bodySmall())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack {
                    // Relevance indicator
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(LisnFont.caption())
                        Text("\(Int(result.relevanceScore * 100))% match")
                            .font(LisnFont.caption())
                    }
                    .foregroundColor(relevanceColor)

                    Spacer()

                    // Timestamp
                    if let timestamp = result.timestamp {
                        Text(formattedDate(timestamp))
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }

                // Topics
                if let topics = result.topics, !topics.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(topics.prefix(3), id: \.self) { topic in
                            LisnChip(text: topic, color: LisnColors.accent)
                        }
                    }
                }
            }

            Image(systemName: "chevron.right")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)
        }
        .padding()
        .background(LisnColors.bgElevated)
        .cornerRadius(LisnRadius.sm)
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    /// Remove diarization headers like "[Speaker 1] (0:00 - 1:23): " from transcript snippets
    private func cleanedSnippet(_ text: String) -> String {
        // Match patterns: [Speaker N] (H:MM:SS - H:MM:SS): or [Speaker N] (MM:SS - MM:SS):
        let pattern = #"\[Speaker \d+\]\s*\(\d+:\d+(?::\d+)?\s*-\s*\d+:\d+(?::\d+)?\):\s*"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        let cleaned = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        // Collapse multiple newlines and trim
        return cleaned
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private var relevanceColor: Color {
        if result.relevanceScore >= 0.8 {
            return LisnColors.success
        } else if result.relevanceScore >= 0.6 {
            return LisnColors.warning
        } else {
            return LisnColors.textTertiary
        }
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }

        if Calendar.current.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Today at \(timeFormatter.string(from: date))"
        } else if Calendar.current.isDateInYesterday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Yesterday at \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return dateFormatter.string(from: date)
        }
    }
}

// MARK: - View Model

@MainActor
class MemorySearchViewModel: ObservableObject {
    @Published var results: [SearchResult] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let dataService = DataService.shared

    func search(query: String, modelContext: ModelContext? = nil) async {
        isLoading = true

        do {
            let response = try await dataService.searchMemories(
                query: query,
                limit: 20,
                context: modelContext
            )
            results = response.results
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func findRecording(for result: SearchResult, context: ModelContext) -> Recording? {
        // Step 1: Find LocalMemory by serverMemoryId — has direct recordingId link
        let memId = result.memoryId
        let memDescriptor = FetchDescriptor<LocalMemory>(
            predicate: #Predicate { $0.serverMemoryId == memId }
        )
        if let localMemory = try? context.fetch(memDescriptor).first,
           let recordingId = localMemory.recordingId {
            let recDescriptor = FetchDescriptor<Recording>(
                predicate: #Predicate { $0.id == recordingId }
            )
            if let recording = try? context.fetch(recDescriptor).first {
                return recording
            }
        }

        // Step 2: Date-proximity fallback for legacy memories without recordingId
        guard let ts = result.timestamp,
              let date = ISO8601DateFormatter().date(from: ts) else { return nil }

        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

        let descriptor = FetchDescriptor<Recording>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        guard let recordings = try? context.fetch(descriptor) else { return nil }

        return recordings.min(by: {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        })
    }
}

// Make SearchResult conform to Identifiable
extension SearchResult: Identifiable {
    var id: String { memoryId }
}

#Preview {
    MemorySearchView()
}

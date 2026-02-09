import SwiftUI

/// View for searching through memories with natural language queries
struct MemorySearchView: View {
    @StateObject private var viewModel = MemorySearchViewModel()
    @State private var searchText = ""
    @State private var isSearching = false
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
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
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
                        performSearch()
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
                            performSearch()
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
        List {
            Section {
                Text("\(viewModel.results.count) memories found")
                    .font(LisnFont.bodySmall())
                    .foregroundColor(LisnColors.textSecondary)
                    .listRowBackground(LisnColors.bgElevated)
            }

            ForEach(viewModel.results) { result in
                SearchResultRow(result: result)
                    .listRowBackground(LisnColors.bgElevated)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LisnColors.bgPrimary)
    }

    // MARK: - Actions

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        Task {
            await viewModel.search(query: searchText)
            isSearching = false
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
            // Snippet
            Text(result.transcriptSnippet)
                .font(LisnFont.bodyMedium())
                .lineLimit(3)

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
        .padding(.vertical, 4)
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

    private let api = APIService.shared

    func search(query: String) async {
        isLoading = true

        do {
            let response = try await api.searchMemories(query: query, limit: 20)
            results = response.results
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

// Make SearchResult conform to Identifiable
extension SearchResult: Identifiable {
    var id: String { memoryId }
}

#Preview {
    MemorySearchView()
}

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
            .navigationTitle("Search Memories")
            .navigationBarTitleDisplayMode(.inline)
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
                    .foregroundColor(.secondary)

                TextField("Search your memories...", text: $searchText)
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
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(10)

            if isSearching || isSearchFieldFocused {
                Button("Cancel") {
                    searchText = ""
                    isSearchFieldFocused = false
                    viewModel.results = []
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: isSearchFieldFocused)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Searching memories...")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Try searching for:")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    ForEach(searchSuggestions, id: \.self) { suggestion in
                        Button(action: {
                            searchText = suggestion
                            performSearch()
                        }) {
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text(suggestion)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "arrow.up.left")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)

                Divider()
                    .padding(.vertical)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Tips")
                        .font(.headline)

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
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
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
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(viewModel.results) { result in
                SearchResultRow(result: result)
            }
        }
        .listStyle(.insetGrouped)
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
        VStack(alignment: .leading, spacing: 8) {
            // Snippet
            Text(result.transcriptSnippet)
                .font(.body)
                .lineLimit(3)

            HStack {
                // Relevance indicator
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("\(Int(result.relevanceScore * 100))% match")
                        .font(.caption)
                }
                .foregroundColor(relevanceColor)

                Spacer()

                // Timestamp
                if let timestamp = result.timestamp {
                    Text(formattedDate(timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Topics
            if let topics = result.topics, !topics.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(topics.prefix(3), id: \.self) { topic in
                        Text(topic)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var relevanceColor: Color {
        if result.relevanceScore >= 0.8 {
            return .green
        } else if result.relevanceScore >= 0.6 {
            return .orange
        } else {
            return .secondary
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

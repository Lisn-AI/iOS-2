import SwiftUI
import SwiftData

/// Main tab-based navigation structure
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recordingManager: RecordingManager
    @State private var selectedTab: Tab = .home
    @State private var showBriefings = false
    @State private var showCommitments = false
    @State private var navigationPath = NavigationPath()

    enum Tab: String, CaseIterable {
        case home = "Home"
        case history = "History"
        case chat = "Chat"
        case actions = "Actions"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .home: return "mic.fill"
            case .history: return "clock.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .actions: return "bolt.fill"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                HomeView()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                Button(action: { showBriefings = true }) {
                                    Label("Daily Briefing", systemImage: "sun.haze")
                                }
                                Button(action: { showCommitments = true }) {
                                    Label("Commitments", systemImage: "checkmark.seal")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }
                    }
            }
            .tabItem {
                Label(Tab.home.rawValue, systemImage: Tab.home.icon)
            }
            .tag(Tab.home)

            HistoryView()
                .tabItem {
                    Label(Tab.history.rawValue, systemImage: Tab.history.icon)
                }
                .tag(Tab.history)

            NavigationStack {
                ChatView(modelContext: modelContext)
            }
            .tabItem {
                Label(Tab.chat.rawValue, systemImage: Tab.chat.icon)
            }
            .tag(Tab.chat)

            ActionsView()
                .tabItem {
                    Label(Tab.actions.rawValue, systemImage: Tab.actions.icon)
                }
                .tag(Tab.actions)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
            }
            .tag(Tab.settings)
        }
        .tint(.blue)
        .sheet(isPresented: $showBriefings) {
            BriefingsView()
        }
        .sheet(isPresented: $showCommitments) {
            CommitmentsView()
        }
        // Handle notification navigation
        .onReceive(NotificationCenter.default.publisher(for: .openBriefing)) { _ in
            showBriefings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommitments)) { _ in
            showCommitments = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openActions)) { _ in
            selectedTab = .actions
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSuggestions)) { _ in
            selectedTab = .actions
        }
    }
}

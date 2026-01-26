import SwiftUI
import SwiftData

/// Main tab-based navigation structure
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recordingManager: RecordingManager
    @State private var selectedTab: Tab = .home

    enum Tab: String, CaseIterable {
        case home = "Home"
        case history = "History"
        case chat = "Chat"
        case settings = "Settings"

        var icon: String {
            switch self {
            case .home: return "mic.fill"
            case .history: return "clock.fill"
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .settings: return "gear"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
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

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(Tab.settings.rawValue, systemImage: Tab.settings.icon)
            }
            .tag(Tab.settings)
        }
        .tint(.blue)
    }
}

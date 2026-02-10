import SwiftUI
import SwiftData

/// Main tab-based navigation structure
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var authService: AuthService
    @State private var selectedTab: Tab = .home
    @State private var showBriefings = false
    @State private var showCommitments = false
    @State private var showSettings = false
    @State private var showSettingsPage = false
    @State private var showMemorySearch = false
    @State private var showPermissionRules = false
    @StateObject private var actionsViewModel = ActionsViewModel()
    @StateObject private var keyboardObserver = KeyboardObserver()

    enum Tab: String, CaseIterable {
        case home = "Home"
        case history = "History"
        case calendar = "Calendar"
        case chat = "Chat"
        case actions = "Actions"

        var icon: String {
            switch self {
            case .home: return "waveform.circle"
            case .history: return "clock.arrow.circlepath"
            case .calendar: return "calendar"
            case .chat: return "bubble.left.and.text.bubble.right"
            case .actions: return "bolt.ring.closed"
            }
        }
    }

    private let menuWidth: CGFloat = UIScreen.main.bounds.width * 0.78

    @State private var menuOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            // Side menu (behind main content)
            sideMenu
                .frame(width: menuWidth)
                .background(LisnColors.bgPrimary)
                .ignoresSafeArea()

            // Main tab content — slides right when menu opens
            ZStack {
                TabView(selection: $selectedTab) {
                    HomeView(showSettings: $showSettings)
                        .toolbar(.hidden, for: .tabBar)
                        .tabItem { Label(Tab.home.rawValue, systemImage: Tab.home.icon) }
                        .tag(Tab.home)

                    HistoryView()
                        .toolbar(.hidden, for: .tabBar)
                        .tabItem { Label(Tab.history.rawValue, systemImage: Tab.history.icon) }
                        .tag(Tab.history)

                    CalendarView()
                        .toolbar(.hidden, for: .tabBar)
                        .tabItem { Label("", systemImage: "") }
                        .tag(Tab.calendar)

                    ChatView(modelContext: modelContext)
                        .toolbar(.hidden, for: .tabBar)
                        .tabItem { Label(Tab.chat.rawValue, systemImage: Tab.chat.icon) }
                        .tag(Tab.chat)

                    ActionsView(viewModel: actionsViewModel)
                        .toolbar(.hidden, for: .tabBar)
                        .tabItem { Label(Tab.actions.rawValue, systemImage: Tab.actions.icon) }
                        .tag(Tab.actions)
                }
                .allowsHitTesting(!showSettings)
                .task {
                    await actionsViewModel.loadData()
                }

                // Dim overlay covers everything when menu is open
                if showSettings {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showSettings = false
                        }
                }
            }
            // Pill tab bar floats at the bottom
            .overlay(alignment: .bottom) {
                if !keyboardObserver.isKeyboardVisible {
                    PillTabBar(selectedTab: $selectedTab)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: keyboardObserver.isKeyboardVisible)
            .offset(x: menuOffset)
        }
        .onChange(of: showSettings) { _, isOpen in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                menuOffset = isOpen ? menuWidth : 0
            }
        }
        .sheet(isPresented: $showBriefings) {
            BriefingsView()
        }
        .sheet(isPresented: $showCommitments) {
            CommitmentsView()
        }
        .sheet(isPresented: $showSettingsPage) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showMemorySearch) {
            MemorySearchView()
        }
        .sheet(isPresented: $showPermissionRules) {
            PermissionRulesView()
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
            Task { await actionsViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSuggestions)) { _ in
            selectedTab = .actions
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHome)) { _ in
            selectedTab = .home
        }
    }

    // MARK: - Side Menu

    private var sideMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            // User profile
            if let user = authService.user {
                Spacer().frame(height: 60)
                VStack(alignment: .leading, spacing: LisnSpacing.xxs) {
                    if let photoURL = user.photoURL {
                        AsyncImage(url: photoURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.circle")
                                .font(.system(size: 48))
                                .foregroundColor(LisnColors.textSecondary)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.circle")
                            .font(.system(size: 48))
                            .foregroundColor(LisnColors.textSecondary)
                    }

                    Text(user.displayName ?? "User")
                        .font(LisnFont.titleLarge())
                        .foregroundColor(LisnColors.textPrimary)

                    Text(user.email ?? "")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)
                }
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.bottom, LisnSpacing.lg)

                Divider()
                    .padding(.horizontal, LisnSpacing.lg)
            }

            // Menu items
            VStack(alignment: .leading, spacing: 0) {
                sideMenuItem(icon: "magnifyingglass", title: "Search Memory") {
                    closeThen { showMemorySearch = true }
                }

                sideMenuItem(icon: "sun.haze", title: "Daily Briefings") {
                    closeThen { showBriefings = true }
                }

                sideMenuItem(icon: "checkmark.seal", title: "Commitments") {
                    closeThen { showCommitments = true }
                }

                sideMenuItem(icon: "lock.shield", title: "Permission Rules") {
                    closeThen { showPermissionRules = true }
                }

                sideMenuItem(icon: "bolt", title: "Actions") {
                    closeThen { selectedTab = .actions }
                }
            }
            .padding(.top, LisnSpacing.lg)

            Spacer()

            // Bottom section
            Divider()
                .padding(.horizontal, LisnSpacing.lg)

            VStack(alignment: .leading, spacing: 0) {
                sideMenuItem(icon: "gear", title: "Settings") {
                    closeThen { showSettingsPage = true }
                }

                sideMenuItem(icon: "person.circle", title: "Account") {
                    closeThen { showSettingsPage = true }
                }
            }
            .padding(.bottom, 40)
        }
    }

    private func sideMenuItem(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LisnSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(LisnColors.textPrimary)
                    .frame(width: 24)

                Text(title)
                    .font(LisnFont.bodyMedium())
                    .foregroundColor(LisnColors.textPrimary)

                Spacer()
            }
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.vertical, LisnSpacing.md)
        }
    }

    private func closeThen(_ action: @escaping () -> Void) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            showSettings = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            action()
        }
    }
}

// MARK: - Pill-Shaped Floating Tab Bar

private struct PillTabBar: View {
    @Binding var selectedTab: MainTabView.Tab

    /// Tabs excluding calendar (calendar gets the raised button)
    private let sideTabs: [(tab: MainTabView.Tab, position: TabPosition)] = [
        (.home, .left),
        (.history, .left),
        (.chat, .right),
        (.actions, .right),
    ]

    enum TabPosition { case left, right }

    var body: some View {
        ZStack {
            // The pill bar
            HStack(spacing: 0) {
                // Left tabs
                ForEach(sideTabs.filter { $0.position == .left }, id: \.tab) { item in
                    tabButton(item.tab)
                }

                // Empty spacer for the calendar slot
                Spacer()
                    .frame(width: 48)

                // Right tabs
                ForEach(sideTabs.filter { $0.position == .right }, id: \.tab) { item in
                    tabButton(item.tab)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(LisnColors.bgPrimary)
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
            )

            // Calendar button overlaid on top, exceeding the pill
            RaisedCalendarButton(selectedTab: $selectedTab)
                .offset(y: -20)
        }
        .padding(.horizontal, 28)
    }

    private func tabButton(_ tab: MainTabView.Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab
            }
            LisnHaptics.light()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18, weight: .medium))
                    .symbolEffect(.bounce, value: selectedTab == tab)

                Text(tab.rawValue)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(selectedTab == tab ? LisnColors.textPrimary : LisnColors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

// Make Tab hashable for ForEach
extension MainTabView.Tab: Hashable {}

// MARK: - Keyboard Observer

import Combine

final class KeyboardObserver: ObservableObject {
    @Published var isKeyboardVisible = false

    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = true }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .sink { [weak self] _ in self?.isKeyboardVisible = false }
            .store(in: &cancellables)
    }
}

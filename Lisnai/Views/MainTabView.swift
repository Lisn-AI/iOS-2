import SwiftUI
import SwiftData

/// Main tab-based navigation structure
struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var subscriptionService: SubscriptionService
    @State private var selectedTab: Tab = .home
    @State private var showPaywall = false
    @State private var showBriefings = false
    @State private var showSettings = false
    @State private var showSettingsPage = false
    @State private var showMemorySearch = false
    @State private var showGateways = false
    @StateObject private var actionsViewModel = ActionsViewModel()
    @StateObject private var keyboardObserver = KeyboardObserver()
    // Live suggestion action state
    @State private var liveSuggestionAction: PendingAction?
    @State private var showSuggestionSuccess = false
    @State private var suggestionSuccessMessage = ""

    // Recording action edit state
    @State private var recordingActionToEdit: PendingAction?

    // Action-creation paywall state — shown when canUseAction() denies.
    @State private var showActionLimitAlert = false
    @State private var actionLimitMessage = ""

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
                    await actionsViewModel.loadData(modelContext: modelContext)
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
        .sheet(isPresented: $showSettingsPage) {
            NavigationStack {
                SettingsView()
            }
        }
        .sheet(isPresented: $showMemorySearch) {
            MemorySearchView()
        }
        .sheet(isPresented: $showGateways) {
            GatewaysView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionService)
        }
        // Paywall disabled — will enforce via Apple IAP later
        // .onReceive(NotificationCenter.default.publisher(for: .showPaywall)) { _ in
        //     showPaywall = true
        // }
        // Handle notification navigation
        .onReceive(NotificationCenter.default.publisher(for: .openBriefing)) { _ in
            showBriefings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCommitments)) { _ in
            selectedTab = .actions // Commitments now shown in Actions tab
        }
        .onReceive(NotificationCenter.default.publisher(for: .openActions)) { _ in
            selectedTab = .actions
            Task { await actionsViewModel.refresh(modelContext: modelContext) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSuggestions)) { _ in
            selectedTab = .actions
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToHome)) { _ in
            selectedTab = .home
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChat)) { notification in
            handleOpenChat(notification)
        }
        // Listen for "Do it" taps on live suggestion Live Activity
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ExecuteSuggestionAction"))) { notification in
            guard let userInfo = notification.userInfo,
                  let skill = userInfo["skill"] as? String else { return }

            let title = userInfo["title"] as? String ?? ""
            let body = userInfo["body"] as? String ?? ""

            // Build params from actionParams if available, otherwise from title/body
            var params: [String: AnyCodable] = [:]
            if let actionParams = userInfo["actionParams"] as? [String: Any] {
                for (key, value) in actionParams {
                    params[key] = AnyCodable(value)
                }
            }
            // Ensure title/content is populated for form display
            if params["title"] == nil && !title.isEmpty {
                params["title"] = AnyCodable(title)
            }
            if params["content"] == nil && !body.isEmpty {
                params["content"] = AnyCodable(body)
            }

            let tool = ActionExecutor.normalizeTool(
                params["tool"]?.stringValue ?? skill,
                skill: ActionExecutor.normalizeSkill(skill)
            )

            let action = PendingAction(
                id: UUID().uuidString,
                skill: ActionExecutor.normalizeSkill(skill),
                tool: tool,
                type: tool,
                params: params,
                status: "pending",
                createdAt: ISO8601DateFormatter().string(from: Date())
            )

            liveSuggestionAction = action
        }
        .sheet(item: $liveSuggestionAction) { action in
            ActionEditSheet(
                action: action,
                onConfirm: { editedAction in
                    liveSuggestionAction = nil
                    // Gate on action quota / free-window before executing.
                    switch subscriptionService.gateAction(triggerPrefix: "action") {
                    case .allowed:
                        Task {
                            let result = await ActionExecutor.shared.executeAction(editedAction)
                            if result.success && result.requiresUserInput == .none {
                                suggestionSuccessMessage = result.message
                                showSuggestionSuccess = true
                            }
                        }
                    case .denied(let used, let limit):
                        actionLimitMessage = "You've used \(used)/\(limit) actions today. Upgrade to keep creating actions."
                        showActionLimitAlert = true
                    case .freeWindowExpired:
                        showPaywall = true
                    }
                },
                onCancel: {
                    liveSuggestionAction = nil
                }
            )
        }
        // Listen for actions from recording that need edit sheet
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PresentActionEditSheet"))) { notification in
            guard let action = notification.userInfo?["action"] as? PendingAction else { return }
            recordingActionToEdit = action
        }
        .sheet(item: $recordingActionToEdit) { action in
            ActionEditSheet(
                action: action,
                onConfirm: { editedAction in
                    recordingActionToEdit = nil
                    switch subscriptionService.gateAction(triggerPrefix: "action") {
                    case .allowed:
                        Task {
                            let result = await ActionExecutor.shared.executeAction(editedAction)
                            if result.success && result.requiresUserInput == .none {
                                suggestionSuccessMessage = result.message
                                showSuggestionSuccess = true
                            }
                        }
                    case .denied(let used, let limit):
                        actionLimitMessage = "You've used \(used)/\(limit) actions today. Upgrade to keep creating actions."
                        showActionLimitAlert = true
                    case .freeWindowExpired:
                        showPaywall = true
                    }
                },
                onCancel: {
                    recordingActionToEdit = nil
                }
            )
        }
        .alert("Action limit reached", isPresented: $showActionLimitAlert) {
            Button("Upgrade") { showPaywall = true }
            Button("Not now", role: .cancel) { }
        } message: {
            Text(actionLimitMessage)
        }
        .alert("Success", isPresented: $showSuggestionSuccess) {
            Button("OK") { }
        } message: {
            Text(suggestionSuccessMessage)
        }
    }

    private func handleOpenChat(_ notification: Notification) {
        let title = notification.userInfo?["title"] as? String
        let summary = notification.userInfo?["summary"] as? String
        selectedTab = .chat
        if let title = title, let summary = summary {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NotificationCenter.default.post(
                    name: .chatWithContext,
                    object: nil,
                    userInfo: ["title": title, "summary": summary]
                )
            }
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

                sideMenuItem(icon: "network", title: "Gateways") {
                    closeThen { showGateways = true }
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
                // Subscription button — always visible, adapts label to tier
                Button {
                    closeThen { showPaywall = true }
                } label: {
                    HStack(spacing: LisnSpacing.sm) {
                        Image(systemName: subscriptionService.isMax ? "crown.fill" : "crown")
                            .font(.system(size: 16))
                            .foregroundStyle(LisnColors.accent)

                        if subscriptionService.isMax {
                            Text("Lisn Max")
                                .font(LisnFont.labelLarge())
                                .foregroundStyle(LisnColors.accent)
                            if subscriptionService.isCancelledButActive {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(LisnColors.warning)
                            }
                        } else if subscriptionService.isPro {
                            Text("Lisn Pro · Go Max")
                                .font(LisnFont.labelLarge())
                                .foregroundStyle(LisnColors.accent)
                        } else {
                            Text("Upgrade to Pro")
                                .font(LisnFont.labelLarge())
                                .foregroundStyle(LisnColors.accent)
                        }
                    }
                    .padding(.horizontal, LisnSpacing.lg)
                    .padding(.vertical, LisnSpacing.sm)
                }

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
            .modifier(LiquidGlassCapsuleModifier())

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

// MARK: - Liquid Glass Modifiers

/// Pill tab bar: native Liquid Glass on iOS 26+, opaque capsule fallback on older
private struct LiquidGlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(
                    Capsule()
                        .fill(LisnColors.bgPrimary)
                        .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 4)
                        .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
                )
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

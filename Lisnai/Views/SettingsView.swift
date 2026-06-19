import SwiftUI
import FirebaseAuth

/// Settings view for app configuration
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var subscriptionService: SubscriptionService
    @StateObject private var notificationService = NotificationService.shared
    @StateObject private var ambientMonitor = AmbientAudioMonitor.shared
    @State private var showPaywall = false
    @State private var showBriefings = false
    @State private var showCommitments = false
    @State private var showPermissionRules = false
    @State private var showGateways = false
    @State private var showDeleteConfirmation = false
    @State private var showAIConsentReview = false
    @State private var isDeleting = false
    @State private var showCloudEnableConfirmation = false
    @State private var showCloudDisableConfirmation = false
    @State private var pendingCloudToggle: Bool? = nil

    // User preferences
    @AppStorage("cloudBackupEnabled") private var cloudBackupEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("dailyBriefingEnabled") private var dailyBriefingEnabled = true
    @AppStorage("suggestionsEnabled") private var suggestionsEnabled = true
    @AppStorage("commitmentRemindersEnabled") private var commitmentRemindersEnabled = true
    @AppStorage("quietHoursEnabled") private var quietHoursEnabled = true
    @AppStorage("quietHoursStart") private var quietHoursStart = 22 // 10 PM
    @AppStorage("quietHoursEnd") private var quietHoursEnd = 7 // 7 AM
    @AppStorage("maxNotificationsPerDay") private var maxNotificationsPerDay = 5

    var body: some View {
        List {
            // Upgrade Card (for non-max users)
            Section {
                Button(action: {
                    AnalyticsService.shared.track(.paywallShown, properties: [
                        "placement": "settings_upgrade_card",
                        "current_tier": subscriptionService.tier.rawValue
                    ])
                    showPaywall = true
                }) {
                    HStack(spacing: LisnSpacing.sm) {
                        Image(systemName: subscriptionService.isMax ? "crown.fill" : "crown.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white)

                        VStack(alignment: .leading, spacing: 2) {
                            if subscriptionService.isMax {
                                Text("Lisn Max")
                                    .font(LisnFont.titleSmall())
                                    .foregroundStyle(.white)
                                if subscriptionService.isCancelledButActive,
                                   let date = subscriptionService.cancellationExpiryDisplay {
                                    Text("Expires \(date)")
                                        .font(LisnFont.caption())
                                        .foregroundStyle(.white.opacity(0.8))
                                } else {
                                    Text("Manage subscription")
                                        .font(LisnFont.caption())
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            } else if subscriptionService.isPro {
                                Text("Lisn Pro")
                                    .font(LisnFont.titleSmall())
                                    .foregroundStyle(.white)
                                if subscriptionService.isCancelledButActive,
                                   let date = subscriptionService.cancellationExpiryDisplay {
                                    Text("Expires \(date) · Upgrade?")
                                        .font(LisnFont.caption())
                                        .foregroundStyle(.white.opacity(0.8))
                                } else {
                                    Text("Go Max or manage plan")
                                        .font(LisnFont.caption())
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            } else {
                                Text("Upgrade to Pro")
                                    .font(LisnFont.titleSmall())
                                    .foregroundStyle(.white)
                                if subscriptionService.isTrialActive {
                                    Text("\(subscriptionService.trialDaysRemaining) days left in trial")
                                        .font(LisnFont.caption())
                                        .foregroundStyle(.white.opacity(0.8))
                                } else {
                                    Text("Unlock unlimited features")
                                        .font(LisnFont.caption())
                                        .foregroundStyle(.white.opacity(0.8))
                                }
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.vertical, LisnSpacing.xs)
                }
                .listRowBackground(
                    LinearGradient(
                        colors: subscriptionService.isCancelledButActive
                            ? [LisnColors.warning, LisnColors.warning.opacity(0.7)]
                            : [LisnColors.accent, LisnColors.orbDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                )
            }

            // Quick Access Section
            Section {
                Button(action: { showBriefings = true }) {
                    HStack {
                        Label("Daily Briefings", systemImage: "sun.haze")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }
                .listRowBackground(LisnColors.bgElevated)

                Button(action: { showCommitments = true }) {
                    HStack {
                        Label("Commitments", systemImage: "checkmark.seal")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }
                .listRowBackground(LisnColors.bgElevated)

                Button(action: { showGateways = true }) {
                    HStack {
                        Label("Gateways", systemImage: "network")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }
                .listRowBackground(LisnColors.bgElevated)

                Button(action: { showPermissionRules = true }) {
                    HStack {
                        Label("Permission Rules", systemImage: "lock.shield")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }
                .listRowBackground(LisnColors.bgElevated)
            } header: {
                Text("Quick Access")
                    .lisnSectionHeader()
            }

            // Cloud Backup Section
            Section {
                if subscriptionService.hasCloudBackup {
                    Toggle(isOn: Binding(
                        get: { cloudBackupEnabled },
                        set: { newValue in
                            pendingCloudToggle = newValue
                            if newValue {
                                showCloudEnableConfirmation = true
                            } else {
                                showCloudDisableConfirmation = true
                            }
                        }
                    )) {
                        Label("Cloud Backup", systemImage: "icloud")
                    }
                    .listRowBackground(LisnColors.bgElevated)
                } else {
                    Button(action: { showPaywall = true }) {
                        HStack {
                            Label("Cloud Backup", systemImage: "icloud")
                                .foregroundStyle(LisnColors.textTertiary)
                            Spacer()
                            Text("Pro")
                                .font(LisnFont.captionBold())
                                .foregroundStyle(LisnColors.accent)
                                .padding(.horizontal, LisnSpacing.xs)
                                .padding(.vertical, 2)
                                .background(LisnColors.accent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .listRowBackground(LisnColors.bgElevated)
                }

                if !cloudBackupEnabled && subscriptionService.hasCloudBackup {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(LisnColors.warning)
                            .font(LisnFont.caption())

                        Text("Without backup, deleting the app will permanently delete all your memories.")
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textSecondary)
                    }
                    .listRowBackground(LisnColors.bgElevated)
                }
            } header: {
                Text("Data")
                    .lisnSectionHeader()
            } footer: {
                Text(cloudBackupEnabled
                    ? "Your data is stored on our servers and synced across devices."
                    : "Your data is stored locally on this device only. The server processes recordings but doesn't keep your data."
                )
            }

            // Notifications Section
            Section {
                Toggle(isOn: $notificationsEnabled) {
                    Label("Push Notifications", systemImage: "bell")
                }
                .listRowBackground(LisnColors.bgElevated)

                if notificationsEnabled {
                    Toggle(isOn: $dailyBriefingEnabled) {
                        Label("Daily Briefings", systemImage: "sun.haze")
                    }
                    .listRowBackground(LisnColors.bgElevated)

                    Toggle(isOn: $suggestionsEnabled) {
                        Label("Proactive Suggestions", systemImage: "lightbulb")
                    }
                    .listRowBackground(LisnColors.bgElevated)

                    Toggle(isOn: $commitmentRemindersEnabled) {
                        Label("Commitment Reminders", systemImage: "checkmark.seal")
                    }
                    .listRowBackground(LisnColors.bgElevated)

                    Toggle(isOn: $ambientMonitor.isEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Ambient Detection", systemImage: "waveform")
                            Text("Get notified when conversation is detected nearby")
                                .font(LisnFont.caption())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                    }
                    .listRowBackground(LisnColors.bgElevated)
                }
            } header: {
                Text("Notifications")
                    .lisnSectionHeader()
            } footer: {
                Text("Control which types of notifications you receive from LisnAI.")
            }

            // Quiet Hours Section
            if notificationsEnabled {
                Section {
                    Toggle(isOn: $quietHoursEnabled) {
                        Label("Quiet Hours", systemImage: "moon")
                    }
                    .listRowBackground(LisnColors.bgElevated)

                    if quietHoursEnabled {
                        Stepper(value: $quietHoursStart, in: 0...23) {
                            HStack {
                                Text("Start")
                                Spacer()
                                Text(formatHour(quietHoursStart))
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                        }
                        .listRowBackground(LisnColors.bgElevated)

                        Stepper(value: $quietHoursEnd, in: 0...23) {
                            HStack {
                                Text("End")
                                Spacer()
                                Text(formatHour(quietHoursEnd))
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                        }
                        .listRowBackground(LisnColors.bgElevated)

                        Stepper(value: $maxNotificationsPerDay, in: 1...20) {
                            HStack {
                                Text("Max per day")
                                Spacer()
                                Text("\(maxNotificationsPerDay)")
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                        }
                        .listRowBackground(LisnColors.bgElevated)
                    }
                } header: {
                    Text("Notification Schedule")
                        .lisnSectionHeader()
                } footer: {
                    Text("During quiet hours, only urgent notifications will be delivered.")
                }
            }

            // Account Section
            Section {
                if let user = authService.user {
                    HStack {
                        Image(systemName: "person.circle")
                            .font(.title2)
                            .foregroundColor(LisnColors.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? "User")
                                .font(LisnFont.bodyMedium())
                                .fontWeight(.medium)
                            Text(user.email ?? "No email")
                                .font(LisnFont.caption())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                    }
                    .listRowBackground(LisnColors.bgElevated)

                    // Device token status
                    HStack {
                        Image(systemName: notificationService.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(notificationService.isAuthorized ? LisnColors.success : LisnColors.error)
                        Text("Push Notifications")
                        Spacer()
                        Text(notificationService.isAuthorized ? "Enabled" : "Disabled")
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textSecondary)
                    }
                    .listRowBackground(LisnColors.bgElevated)

                    // Subscription Status
                    if subscriptionService.isPro {
                        HStack {
                            Label("Subscription", systemImage: "creditcard")
                            Spacer()
                            Text(subscriptionService.tier.displayName)
                                .font(LisnFont.captionBold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, LisnSpacing.xs)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [LisnColors.accent, LisnColors.orbDark],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        .listRowBackground(LisnColors.bgElevated)
                    }

                    // TODO: Uncomment when Apple IAP is ready
                    // if subscriptionService.isPro {
                    //     Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    //         HStack {
                    //             Label("Manage Subscription", systemImage: "creditcard")
                    //             Spacer()
                    //             Text(subscriptionService.tier.displayName)
                    //                 .font(LisnFont.captionBold())
                    //                 .foregroundStyle(LisnColors.accent)
                    //             Image(systemName: "chevron.right")
                    //                 .font(.caption)
                    //                 .foregroundStyle(LisnColors.textTertiary)
                    //         }
                    //     }
                    //     .listRowBackground(LisnColors.bgElevated)
                    // }

                    Button {
                        do {
                            try authService.signOut()
                        } catch {
                            print("Sign out error: \(error)")
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .listRowBackground(LisnColors.bgElevated)
                }
            } header: {
                Text("Account")
                    .lisnSectionHeader()
            }

            // About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(LisnColors.textSecondary)
                }
                .listRowBackground(LisnColors.bgElevated)

                Link(destination: URL(string: "https://lisnai-website.onrender.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .listRowBackground(LisnColors.bgElevated)

                Link(destination: URL(string: "https://lisnai-website.onrender.com/terms")!) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                .listRowBackground(LisnColors.bgElevated)

                // AI data consent — shows current status + lets user review the consent
                Button {
                    showAIConsentReview = true
                } label: {
                    HStack {
                        Label("AI Data Processing", systemImage: "brain.head.profile")
                        Spacer()
                        Text(AIConsentManager.hasConsented ? "Consented" : "Required")
                            .font(LisnFont.caption())
                            .foregroundStyle(AIConsentManager.hasConsented ? LisnColors.success : LisnColors.warning)
                    }
                }
                .listRowBackground(LisnColors.bgElevated)

                Link(destination: URL(string: "https://lisnai-website.onrender.com/support")!) {
                    Label("Support", systemImage: "questionmark.circle")
                }
                .listRowBackground(LisnColors.bgElevated)

                Link(destination: URL(string: "mailto:team@lisnai.com")!) {
                    Label("Report an Issue", systemImage: "ladybug")
                }
                .listRowBackground(LisnColors.bgElevated)
            } header: {
                Text("About")
                    .lisnSectionHeader()
            }

            // Danger Zone
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeleting {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Deleting...")
                        }
                    } else {
                        Label("Delete All Data", systemImage: "trash")
                            .foregroundColor(LisnColors.error)
                    }
                }
                .disabled(isDeleting)
                .listRowBackground(LisnColors.bgElevated)
            } header: {
                Text("Danger Zone")
                    .lisnSectionHeader()
            } footer: {
                Text("This will permanently delete all your recordings, transcriptions, and summaries from this device and the cloud.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(LisnColors.bgPrimary)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(LisnColors.bgPrimary, for: .navigationBar)
        .onAppear { AnalyticsService.shared.track(.settingsOpened) }
        .sheet(isPresented: $showBriefings) {
            BriefingsView()
        }
        .sheet(isPresented: $showCommitments) {
            CommitmentsView()
        }
        .sheet(isPresented: $showGateways) {
            GatewaysView()
        }
        .sheet(isPresented: $showPermissionRules) {
            PermissionRulesView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionService)
        }
        .sheet(isPresented: $showAIConsentReview) {
            AIConsentView {
                // Already consented or just consented — dismiss is enough
            }
        }
        .confirmationDialog(
            "Delete All Data?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Everything", role: .destructive) {
                Task {
                    await deleteAllData()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all your recordings, transcriptions, memories, and summaries. This action cannot be undone.")
        }
        .alert("Enable Cloud Backup?", isPresented: $showCloudEnableConfirmation) {
            Button("Enable") {
                cloudBackupEnabled = true
                DataService.shared.isCloudMode = true
            }
            Button("Cancel", role: .cancel) {
                pendingCloudToggle = nil
            }
        } message: {
            Text("Future recordings will be stored on our servers and synced across devices. Your existing local data will remain on this device.")
        }
        .alert("Disable Cloud Backup?", isPresented: $showCloudDisableConfirmation) {
            Button("Disable", role: .destructive) {
                cloudBackupEnabled = false
                DataService.shared.isCloudMode = false
            }
            Button("Cancel", role: .cancel) {
                pendingCloudToggle = nil
            }
        } message: {
            Text("New recordings will be stored locally only. Your existing cloud data will remain on the server but no new data will be uploaded.")
        }
        .task {
            await notificationService.setup()
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        var components = DateComponents()
        components.hour = hour
        if let date = Calendar.current.date(from: components) {
            return formatter.string(from: date)
        }
        return "\(hour):00"
    }

    private func deleteAllData() async {
        isDeleting = true
        // TODO: Implement delete all data from backend and local storage
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        isDeleting = false
    }
}

// MARK: - Permission Rules View

struct PermissionRulesView: View {
    @StateObject private var viewModel = PermissionRulesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.rules.isEmpty {
                    ProgressView("Loading rules...")
                } else if viewModel.rules.isEmpty {
                    ContentUnavailableView(
                        "No Permission Rules",
                        systemImage: "lock.shield",
                        description: Text("Permission rules you create will appear here")
                    )
                } else {
                    rulesList
                }
            }
            .navigationTitle("Permission Rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .task {
                await viewModel.loadData()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    private var rulesList: some View {
        List {
            ForEach(viewModel.rules) { rule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: (rule.enabled ?? true) ? "checkmark.circle.fill" : "circle")
                            .foregroundColor((rule.enabled ?? true) ? LisnColors.success : LisnColors.textSecondary)

                        Text(rule.pattern)
                            .font(LisnFont.titleSmall())
                    }

                    if let description = rule.description {
                        Text(description)
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                    }

                    HStack {
                        Label(rule.matchMode.capitalized, systemImage: "magnifyingglass")
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.accent)

                        Label(rule.scope.capitalized, systemImage: "scope")
                            .font(LisnFont.caption())
                            .foregroundColor(Color.purple)
                    }
                }
                .padding(.vertical, 4)
                .listRowBackground(LisnColors.bgElevated)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await viewModel.deleteRule(rule) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LisnColors.bgPrimary)
    }
}

// MARK: - Permission Rules View Model

@MainActor
class PermissionRulesViewModel: ObservableObject {
    @Published var rules: [PermissionRule] = []
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
            let response = try await api.getPermissionRules()
            rules = response.rules
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func deleteRule(_ rule: PermissionRule) async {
        do {
            _ = try await api.deletePermissionRule(ruleId: rule.id)
            rules.removeAll { $0.id == rule.id }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

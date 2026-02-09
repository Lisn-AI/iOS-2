import SwiftUI
import FirebaseAuth

/// Settings view for app configuration
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var notificationService = NotificationService.shared
    @State private var showBriefings = false
    @State private var showCommitments = false
    @State private var showPermissionRules = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

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
                Toggle(isOn: $cloudBackupEnabled) {
                    Label("Cloud Backup", systemImage: "icloud")
                }
                .listRowBackground(LisnColors.bgElevated)

                if !cloudBackupEnabled {
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
                Text("Enable cloud backup to sync your transcriptions and summaries across devices.")
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

                Link(destination: URL(string: "https://lisnai.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }
                .listRowBackground(LisnColors.bgElevated)

                Link(destination: URL(string: "https://lisnai.com/terms")!) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
                .listRowBackground(LisnColors.bgElevated)

                Link(destination: URL(string: "https://github.com/lisnai/ios/issues")!) {
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
        .sheet(isPresented: $showBriefings) {
            BriefingsView()
        }
        .sheet(isPresented: $showCommitments) {
            CommitmentsView()
        }
        .sheet(isPresented: $showPermissionRules) {
            PermissionRulesView()
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

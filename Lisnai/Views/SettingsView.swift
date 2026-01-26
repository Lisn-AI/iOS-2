import SwiftUI
import FirebaseAuth

/// Settings view for app configuration
struct SettingsView: View {
    @EnvironmentObject var authService: AuthService
    @AppStorage("cloudBackupEnabled") private var cloudBackupEnabled = false
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    var body: some View {
        List {
            // Cloud Backup Section
            Section {
                Toggle(isOn: $cloudBackupEnabled) {
                    Label("Cloud Backup", systemImage: "icloud")
                }

                if !cloudBackupEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("Without backup, deleting the app will permanently delete all your memories.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Enable cloud backup to sync your transcriptions and summaries across devices.")
            }

            // Notifications Section
            Section {
                Toggle(isOn: $notificationsEnabled) {
                    Label("Recording Reminders", systemImage: "bell")
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Get reminded to start recording when you leave home.")
            }

            // Account Section
            Section {
                if let user = authService.user {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? "User")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(user.email ?? "No email")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        do {
                            try authService.signOut()
                        } catch {
                            print("Sign out error: \(error)")
                        }
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } header: {
                Text("Account")
            }

            // About Section
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(appVersion)
                        .foregroundColor(.secondary)
                }

                Link(destination: URL(string: "https://lisnai.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Link(destination: URL(string: "https://lisnai.com/terms")!) {
                    Label("Terms of Service", systemImage: "doc.text")
                }
            } header: {
                Text("About")
            }

            // Danger Zone
            Section {
                Button(role: .destructive) {
                    // TODO: Implement delete all data
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                        .foregroundColor(.red)
                }
            } header: {
                Text("Danger Zone")
            } footer: {
                Text("This will permanently delete all your recordings, transcriptions, and summaries from this device.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

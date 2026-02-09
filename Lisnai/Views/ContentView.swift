import SwiftUI
import SwiftData

/// Root content view that handles auth state and displays appropriate UI
struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var authService: AuthService
    @State private var breathe = false

    var body: some View {
        Group {
            if !authService.isAuthReady {
                // Breathing accent loader while determining auth state
                loadingView
            } else if authService.isLoggedIn {
                MainTabView()
                    .onAppear {
                        // Start suggestion monitoring when user is logged in
                        SuggestionMonitor.shared.startMonitoring()
                    }
                    .onDisappear {
                        SuggestionMonitor.shared.stopMonitoring()
                    }
            } else {
                LoginView()
                    .onAppear {
                        // Stop monitoring when logged out
                        SuggestionMonitor.shared.stopMonitoring()
                    }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authService.isLoggedIn)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: authService.isAuthReady)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: LisnSpacing.lg) {
            ZStack {
                Circle()
                    .fill(LisnColors.accent.opacity(0.15))
                    .frame(width: 100, height: 100)
                    .scaleEffect(breathe ? 1.2 : 0.9)
                    .opacity(breathe ? 0.6 : 1.0)

                Circle()
                    .fill(LisnColors.accent.opacity(0.3))
                    .frame(width: 70, height: 70)
                    .scaleEffect(breathe ? 1.1 : 0.95)

                Image(systemName: "waveform")
                    .font(.system(size: 28))
                    .foregroundColor(LisnColors.accent)
            }
            .animation(
                .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: breathe
            )
            .onAppear { breathe = true }

            Text("Loading...")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LisnColors.bgPrimary)
    }
}

#Preview("Logged In") {
    ContentView()
        .environmentObject(RecordingManager())
        .environmentObject(LocationManager())
        .environmentObject(AuthService())
}

#Preview("Logged Out") {
    LoginView()
        .environmentObject(AuthService())
}

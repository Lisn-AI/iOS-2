import SwiftUI
import SwiftData

/// Root content view that handles auth state and displays appropriate UI
struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if !authService.isAuthReady {
                // Show loading while determining auth state
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .animation(.easeInOut, value: authService.isLoggedIn)
        .animation(.easeInOut, value: authService.isAuthReady)
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

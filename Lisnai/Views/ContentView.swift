import SwiftUI
import SwiftData

/// Root content view that handles auth state and displays appropriate UI
struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var authService: AuthService

    var body: some View {
        Group {
            if authService.isLoggedIn {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut, value: authService.isLoggedIn)
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

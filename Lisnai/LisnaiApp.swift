import SwiftUI
import SwiftData
import FirebaseCore
import GoogleSignIn

// Firebase configuration
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }

    // Handle Google Sign In URL callback
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

@main
struct LisnaiApp: App {
    // Connect AppDelegate for Firebase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authService = AuthService()

    /// SwiftData model container for local persistence
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Transcription.self,
            Summary.self,
            ChatMessage.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(locationManager)
                .environmentObject(authService)
        }
        .modelContainer(sharedModelContainer)
    }
}

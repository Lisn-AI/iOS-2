import SwiftUI
import SwiftData
import FirebaseCore
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

// Firebase configuration and push notifications
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationService = NotificationService.shared

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()

        // Set up push notifications with enhanced service
        setupPushNotifications(application)

        // Configure global UIKit appearance for theming
        configureAppearance()

        return true
    }

    // MARK: - UIKit Appearance

    private func configureAppearance() {
        // Force light mode globally
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = .light
                }
            }
        }

        let bgPrimary = UIColor(named: "BGPrimary") ?? UIColor(red: 1.0, green: 0.992, blue: 0.969, alpha: 1.0)

        // Navigation bar - matches bgPrimary
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = bgPrimary

        if let interSemiBold17 = UIFont(name: "Inter-SemiBold", size: 17) {
            navBarAppearance.titleTextAttributes = [
                .font: interSemiBold17,
                .foregroundColor: UIColor.label
            ]
        }
        if let interBold34 = UIFont(name: "Inter-Bold", size: 34) {
            navBarAppearance.largeTitleTextAttributes = [
                .font: interBold34,
                .foregroundColor: UIColor.label
            ]
        }

        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().compactAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = UIColor.label

        // Clear table/list backgrounds so our bgPrimary shows through
        UITableView.appearance().backgroundColor = .clear
    }

    // MARK: - Push Notifications Setup

    private func setupPushNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        // Set up notification service (registers categories and requests authorization)
        Task {
            await notificationService.setup()
        }
    }

    // MARK: - APNs Token Registration

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Set Firebase messaging token
        Messaging.messaging().apnsToken = deviceToken

        // Also register with our notification service for direct APNs handling
        Task { @MainActor in
            notificationService.handleDeviceTokenRegistration(deviceToken)
        }

        print("[AppDelegate] APNs token registered")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
    }

    // Handle Google Sign In URL callback
    func application(_ app: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo

        // Check notification type - for some types we might want different behavior
        if let notificationType = userInfo["type"] as? String ?? userInfo["notificationType"] as? String {
            // For urgent suggestions, always show with alert
            if notificationType == "urgent_suggestion" {
                completionHandler([.banner, .sound, .badge, .list])
                return
            }
        }

        // Default: Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }

    // Handle notification tap and action buttons
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let actionIdentifier = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier

        // Get notification type from various possible keys
        let notificationType = userInfo["type"] as? String
            ?? userInfo["notificationType"] as? String
            ?? category.lowercased().replacingOccurrences(of: "_", with: "-")

        // Use the enhanced notification service for handling
        Task { @MainActor in
            await NotificationService.shared.handleNotificationAction(
                type: notificationType,
                userInfo: userInfo,
                actionIdentifier: actionIdentifier
            )
        }

        completionHandler()
    }
}

// MARK: - MessagingDelegate

extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("FCM token received: \(token)")

        // Register token with backend
        Task { @MainActor in
            do {
                let deviceId = await UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                _ = try await APIService.shared.registerFCMToken(token: token, deviceId: deviceId)
                print("FCM token registered with backend")
            } catch {
                print("Failed to register FCM token: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openBriefing = Notification.Name("openBriefing")
    static let openCommitments = Notification.Name("openCommitments")
    static let openActions = Notification.Name("openActions")
    static let openSuggestions = Notification.Name("openSuggestions")
    static let navigateToHome = Notification.Name("navigateToHome")
    static let openChat = Notification.Name("openChat")
    static let chatWithContext = Notification.Name("chatWithContext")
}

@main
struct LisnaiApp: App {
    // Connect AppDelegate for Firebase
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var authService = AuthService()
    @StateObject private var taskActivityManager = TaskActivityManager.shared
    @StateObject private var suggestionMonitor = SuggestionMonitor.shared

    @State private var showSplash = true

    /// SwiftData model container for local persistence
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Recording.self,
            Transcription.self,
            Summary.self,
            ChatMessage.self,
            Insight.self,
            LocalMemory.self,
            LocalContact.self,
            LocalCommitment.self,
            LocalSuggestion.self,
            LocalBriefing.self,
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
            ZStack {
                ContentView()
                    .preferredColorScheme(.light)
                    .environmentObject(recordingManager)
                    .environmentObject(locationManager)
                    .environmentObject(authService)
                    .onOpenURL { url in
                        handleDeepLink(url)
                    }

                if showSplash {
                    SplashLogoView()
                        .transition(.opacity)
                        .zIndex(1)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    showSplash = false
                                }
                            }
                        }
                }
            }
        }
        .modelContainer(sharedModelContainer)
    }

    /// Handle deep links from backend actions and Live Activities
    /// Formats:
    /// - lisnai://action/{type}/{actionId} - Action execution
    /// - lisnai://task/execute/{actionId} - Execute task from Live Activity
    /// - lisnai://task/dismiss/{actionId} - Dismiss task from Live Activity
    /// - lisnai://tasks - Open tasks view
    private func handleDeepLink(_ url: URL) {
        // Handle Google Sign In URLs
        if GIDSignIn.sharedInstance.handle(url) {
            return
        }

        // Handle LisnAI deep links
        guard url.scheme == "lisnai" else { return }

        let pathComponents = url.pathComponents.filter { $0 != "/" }

        switch url.host {
        case "action":
            // Handle action execution
            Task {
                if let result = await ActionExecutor.shared.handleDeepLink(url) {
                    if result.success {
                        print("Deep link action executed: \(result.message)")
                    } else {
                        print("Deep link action failed: \(result.message)")
                    }
                }
            }

        case "task":
            // Handle task Live Activity deep links
            guard pathComponents.count >= 1 else { return }
            let action = pathComponents[0]
            let taskId = pathComponents.count > 1 ? pathComponents[1] : nil

            Task {
                await handleTaskDeepLink(action: action, taskId: taskId)
            }

        case "tasks":
            // Open the tasks/actions view
            NotificationCenter.default.post(name: .openActions, object: nil)

        default:
            print("Unknown deep link host: \(url.host ?? "nil")")
        }
    }

    /// Handle task-related deep links from Live Activity
    private func handleTaskDeepLink(action: String, taskId: String?) async {
        switch action {
        case "execute":
            guard let taskId = taskId else { return }
            // Execute the task
            do {
                let response = try await APIService.shared.acceptSuggestion(suggestionId: taskId)
                if let suggestedAction = response.suggestedAction {
                    // Create pending action and execute
                    print("Task accepted, suggested action: \(suggestedAction.skill):\(suggestedAction.tool)")
                }
                // Refresh the Live Activity
                if let userId = authService.user?.uid {
                    await taskActivityManager.refreshActivity(userId: userId)
                }
            } catch {
                print("Failed to execute task: \(error)")
            }

        case "dismiss":
            guard let taskId = taskId else {
                // Dismiss all - end Live Activity
                await taskActivityManager.endCurrentActivity()
                return
            }
            // Dismiss specific task
            do {
                _ = try await APIService.shared.dismissSuggestion(suggestionId: taskId)
                // Refresh the Live Activity to show next task
                if let userId = authService.user?.uid {
                    await taskActivityManager.refreshActivity(userId: userId)
                }
            } catch {
                print("Failed to dismiss task: \(error)")
            }

        default:
            print("Unknown task action: \(action)")
        }
    }
}

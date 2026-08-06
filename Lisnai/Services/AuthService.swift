import Foundation
import FirebaseCore
import FirebaseAuth
import GoogleSignIn
import AuthenticationServices
import CryptoKit
import UIKit

/// Handles user authentication with Firebase
@MainActor
class AuthService: NSObject, ObservableObject {
    @Published var user: User?
    @Published var isLoading = false
    @Published var error: String?
    @Published var isAuthReady = false  // True once we know the auth state

    var isLoggedIn: Bool {
        user != nil
    }

    // For Apple Sign In
    private var currentNonce: String?
    private var appleSignInCompletion: ((Result<User, Error>) -> Void)?
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    override init() {
        super.init()
        // Listen for auth state changes
        setupAuthStateListener()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State

    private func setupAuthStateListener() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.user = user
                self?.isAuthReady = true
                if let user = user {
                    print("Auth state changed: signed in as \(user.email ?? "unknown")")
                    // Identify user in Mixpanel
                    AnalyticsService.shared.identify(
                        userId: user.uid,
                        email: user.email,
                        name: user.displayName
                    )
                    await SubscriptionService.shared.loginUser(firebaseUID: user.uid)
                    await SubscriptionService.shared.syncUsageFromBackend()
                    // Submit cached onboarding survey (if exists)
                    Self.submitPendingSurvey()
                } else {
                    print("Auth state changed: signed out")
                    AnalyticsService.shared.reset()
                    await SubscriptionService.shared.logoutUser()
                }
            }
        }
    }

    func checkAuthState() {
        user = Auth.auth().currentUser
        isAuthReady = true
    }

    // MARK: - Pending Survey Submission

    /// Reads cached onboarding survey from UserDefaults and submits to backend + Mixpanel.
    /// Called once after first sign-in. Clears the cache after successful submit.
    static func submitPendingSurvey() {
        guard UserDefaults.standard.bool(forKey: "pendingSurvey_exists") else { return }

        let source = UserDefaults.standard.string(forKey: "pendingSurvey_acquisitionSource")
        let intents = UserDefaults.standard.stringArray(forKey: "pendingSurvey_useCaseIntents") ?? []
        let tools = UserDefaults.standard.stringArray(forKey: "pendingSurvey_priorTools") ?? []

        let payload: [String: Any] = [
            "acquisition_source": source ?? "skipped",
            "use_case_intents": intents,
            "prior_tool": tools,
            "completed_at": ISO8601DateFormatter().string(from: Date()),
            "onboarding_version": "v2",
        ]

        // Backend
        Task {
            do {
                try await APIService.shared.submitSurvey(payload)
                print("[Survey] Pending survey submitted to backend after sign-in")
            } catch {
                print("[Survey] Pending survey backend submit failed: \(error.localizedDescription)")
            }
        }

        // Mixpanel user properties
        if let source {
            AnalyticsService.shared.setUserProperty("acquisition_source", value: source)
        }
        if !intents.isEmpty {
            AnalyticsService.shared.setUserProperty("use_case_intents", value: intents)
        }
        if !tools.isEmpty {
            AnalyticsService.shared.setUserProperty("prior_tool", value: tools)
        }

        // Clear cache so we don't submit again
        UserDefaults.standard.removeObject(forKey: "pendingSurvey_exists")
        UserDefaults.standard.removeObject(forKey: "pendingSurvey_acquisitionSource")
        UserDefaults.standard.removeObject(forKey: "pendingSurvey_useCaseIntents")
        UserDefaults.standard.removeObject(forKey: "pendingSurvey_priorTools")

        print("[Survey] Pending survey cache cleared")
    }

    // MARK: - Google Sign In

    func signInWithGoogle() async throws {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            throw AuthError.missingClientID
        }

        // Get the presenting view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noViewController
        }

        // Configure Google Sign In
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        isLoading = true
        error = nil

        do {
            // Sign in with Google
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw AuthError.missingToken
            }

            let accessToken = result.user.accessToken.tokenString

            // Create Firebase credential
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )

            // Sign in to Firebase
            let authResult = try await Auth.auth().signIn(with: credential)
            self.user = authResult.user

            print("Successfully signed in with Google: \(authResult.user.email ?? "no email")")

        } catch let error as GIDSignInError where error.code == .canceled {
            throw AuthError.cancelled
        } catch {
            self.error = error.localizedDescription
            throw error
        }

        isLoading = false
    }

    // MARK: - Apple Sign In

    func signInWithApple() {
        let nonce = randomNonceString()
        currentNonce = nonce

        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let authorizationController = ASAuthorizationController(authorizationRequests: [request])
        authorizationController.delegate = self
        authorizationController.presentationContextProvider = self
        authorizationController.performRequests()

        isLoading = true
        error = nil
    }

    // MARK: - Sign Out

    func signOut() throws {
        try Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
        user = nil
        print("Successfully signed out")
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser else {
            throw AuthError.notLoggedIn
        }

        try await user.delete()
        self.user = nil
        print("Account deleted successfully")
    }

    // MARK: - Helpers

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }

        return String(nonce)
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Apple Sign In Delegate

extension AuthService: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self.error = "Invalid credential type"
                self.isLoading = false
                return
            }

            guard let nonce = currentNonce else {
                self.error = "Invalid state: no nonce"
                self.isLoading = false
                return
            }

            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                self.error = "Unable to fetch identity token"
                self.isLoading = false
                return
            }

            let credential = OAuthProvider.appleCredential(
                withIDToken: idTokenString,
                rawNonce: nonce,
                fullName: appleIDCredential.fullName
            )

            do {
                let authResult = try await Auth.auth().signIn(with: credential)
                self.user = authResult.user
                print("Successfully signed in with Apple: \(authResult.user.email ?? "no email")")
            } catch {
                self.error = error.localizedDescription
            }

            self.isLoading = false
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                // User cancelled - don't show error
            } else {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}

// MARK: - Presentation Context Provider

extension AuthService: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window
        }
        return UIWindow()
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case missingClientID
    case noViewController
    case missingToken
    case cancelled
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "Firebase client ID not found"
        case .noViewController:
            return "Could not find root view controller"
        case .missingToken:
            return "Could not get authentication token"
        case .cancelled:
            return "Sign in was cancelled"
        case .notLoggedIn:
            return "No user is logged in"
        }
    }
}

import SwiftUI
import AuthenticationServices

/// Login/Sign Up view with Google and Apple Sign In
struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                Spacer()
                    .frame(height: 60)

                // App Icon/Logo
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                }

                // Title
                Text("Lisnai")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Subtitle
                Text("Your voice-powered memory")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .frame(maxHeight: .infinity)

            // Sign In Buttons
            VStack(spacing: 16) {
                // Apple Sign In
                Button(action: {
                    authService.signInWithApple()
                }) {
                    HStack(spacing: 12) {
                        Image(systemName: "apple.logo")
                            .font(.title2)

                        Text("Continue with Apple")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .cornerRadius(28)
                }

                // Google Sign In
                Button(action: {
                    Task {
                        do {
                            try await authService.signInWithGoogle()
                        } catch AuthError.cancelled {
                            // User cancelled, do nothing
                        } catch {
                            showError = true
                        }
                    }
                }) {
                    HStack(spacing: 12) {
                        // Google logo
                        Image(systemName: "g.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)

                        Text("Continue with Google")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(.systemGray6))
                    .cornerRadius(28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
                }

                // Loading indicator
                if authService.isLoading {
                    ProgressView()
                        .padding(.top, 8)
                }

                // Terms
                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .alert("Sign In Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(authService.error ?? "An error occurred")
        }
        .onChange(of: authService.error) { _, newError in
            if newError != nil {
                showError = true
            }
        }
    }
}

// MARK: - Onboarding Welcome View

struct OnboardingView: View {
    @State private var currentPage = 0

    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "mic.fill",
            title: "Record Your Day",
            description: "Capture conversations, meetings, and moments with continuous background recording."
        ),
        OnboardingPage(
            icon: "text.bubble.fill",
            title: "AI Transcription",
            description: "Your recordings are automatically transcribed and summarized on-device."
        ),
        OnboardingPage(
            icon: "magnifyingglass",
            title: "Search Your Memory",
            description: "Ask questions about your past and get instant answers from your voice history."
        )
    ]

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            // Continue button on last page
            if currentPage == pages.count - 1 {
                Button(action: {
                    // Navigate to login
                }) {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.blue)
                        .cornerRadius(28)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
            }

            Text(page.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
    }
}

#Preview("Login") {
    LoginView()
        .environmentObject(AuthService())
}

#Preview("Onboarding") {
    OnboardingView()
}

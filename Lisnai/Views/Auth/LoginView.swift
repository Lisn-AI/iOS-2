import SwiftUI
import AuthenticationServices

/// Login/Sign Up view with Google and Apple Sign In
struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: LisnSpacing.md) {
                Spacer()
                    .frame(height: 60)

                // App Icon/Logo
                ZStack {
                    Circle()
                        .fill(LisnColors.accent.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(LisnColors.accent)
                }

                // Title
                Text("Lisnai")
                    .font(LisnFont.displayLarge())

                // Subtitle
                Text("Your voice-powered memory")
                    .font(LisnFont.titleMedium())
                    .foregroundColor(LisnColors.textSecondary)

                Spacer()
            }
            .frame(maxHeight: .infinity)

            // Sign In Buttons
            VStack(spacing: LisnSpacing.md) {
                // Apple Sign In
                Button(action: {
                    authService.signInWithApple()
                }) {
                    HStack(spacing: LisnSpacing.sm) {
                        Image(systemName: "apple.logo")
                            .font(.title2)

                        Text("Continue with Apple")
                            .font(LisnFont.labelLarge())
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.black)
                    .cornerRadius(LisnRadius.pill)
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
                    HStack(spacing: LisnSpacing.sm) {
                        // Google logo
                        Image(systemName: "g.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)

                        Text("Continue with Google")
                            .font(LisnFont.labelLarge())
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(LisnColors.bgSecondary)
                    .cornerRadius(LisnRadius.pill)
                    .overlay(
                        RoundedRectangle(cornerRadius: LisnRadius.pill)
                            .stroke(LisnColors.border, lineWidth: 1)
                    )
                }

                // Loading indicator
                if authService.isLoading {
                    ProgressView()
                        .padding(.top, LisnSpacing.xs)
                }

                // Terms
                Text("By continuing, you agree to our Terms of Service and Privacy Policy")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, LisnSpacing.md)
            }
            .padding(.horizontal, LisnSpacing.xl)
            .padding(.bottom, LisnSpacing.xxxl)
        }
        .background(LisnColors.bgPrimary)
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
                        .font(LisnFont.labelLarge())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(LisnColors.accent)
                        .cornerRadius(LisnRadius.pill)
                }
                .padding(.horizontal, LisnSpacing.xl)
                .padding(.bottom, LisnSpacing.xxxl)
            }
        }
        .background(LisnColors.bgPrimary)
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
        VStack(spacing: LisnSpacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LisnColors.accent.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: page.icon)
                    .font(.system(size: 50))
                    .foregroundColor(LisnColors.accent)
            }

            Text(page.title)
                .font(LisnFont.titleLarge())
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LisnSpacing.xxxl)

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

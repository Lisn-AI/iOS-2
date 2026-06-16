import SwiftUI

/// Main onboarding flow — 5 screens via scroll storytelling
struct OnboardingCoordinator: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("selectedUserDomain") private var selectedDomainRaw: String = ""
    @State private var selectedDomain: UserDomain?
    @State private var demoResult: DemoResult?
    @State private var survey = SurveyResponse()

    private let screenHeight = UIScreen.main.bounds.height

    var body: some View {
        ZStack {
            // Base background
            LisnColors.bgPrimary.ignoresSafeArea()

            // Animated MeshGradient background (iOS 18+)
            meshBackground
                .ignoresSafeArea()
                .opacity(0.6)

            // Scroll content
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingWelcomeScreen()
                        .frame(height: screenHeight)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                                .opacity(phase.isIdentity ? 1.0 : 0.0)
                                .blur(radius: phase.isIdentity ? 0 : 4)
                        }

                    OnboardingValueScreen()
                        .frame(height: screenHeight)
                        .scrollTransition { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                                .opacity(phase.isIdentity ? 1.0 : 0.0)
                                .blur(radius: phase.isIdentity ? 0 : 4)
                        }

                    OnboardingSurveyScreen(survey: $survey) {
                        // Continue tapped — submit survey + Mixpanel, then user can scroll past
                        submitSurvey()
                    }
                    .frame(minHeight: screenHeight)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                            .opacity(phase.isIdentity ? 1.0 : 0.0)
                            .blur(radius: phase.isIdentity ? 0 : 4)
                    }

                    OnboardingDemoScreen(domain: selectedDomain, result: $demoResult)
                        .frame(minHeight: screenHeight)
                        .scrollTransition { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1.0 : 0.0)
                                .blur(radius: phase.isIdentity ? 0 : 4)
                        }

                    OnboardingCTAScreen(demoResult: demoResult) {
                        completeOnboarding()
                    }
                    .frame(height: screenHeight)
                    .scrollTransition { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.88)
                            .opacity(phase.isIdentity ? 1.0 : 0.0)
                            .blur(radius: phase.isIdentity ? 0 : 4)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
        }
        .ignoresSafeArea()
        .onAppear {
            AnalyticsService.shared.track(.onboardingStarted)
        }
    }

    // MARK: - Background (single ambient bloom — see DESIGN.md Part 4)

    private var meshBackground: some View {
        LisnAmbientBackground()
    }

    private func completeOnboarding() {
        if let domain = selectedDomain {
            selectedDomainRaw = domain.rawValue
        }
        AnalyticsService.shared.track(.onboardingCompleted)
        withAnimation(.easeOut(duration: 0.4)) {
            hasCompletedOnboarding = true
        }
    }

    /// Persist survey answers to backend + Mixpanel user properties.
    /// Called when user taps Continue on survey screen.
    /// Best-effort — if backend is down, we don't block onboarding flow.
    private func submitSurvey() {
        guard survey.isComplete else { return }
        let payload = survey.backendPayload()

        // Backend
        Task {
            do {
                try await APIService.shared.submitSurvey(payload)
                print("[Survey] Submitted to backend")
            } catch {
                print("[Survey] Backend submit failed (non-fatal): \(error.localizedDescription)")
            }
        }

        // Mixpanel: user properties + event
        if let source = survey.acquisitionSource?.rawValue {
            AnalyticsService.shared.setUserProperty("acquisition_source", value: source)
        }
        AnalyticsService.shared.setUserProperty(
            "use_case_intents",
            value: survey.useCaseIntents.map { $0.rawValue }
        )
        if !survey.priorTools.isEmpty {
            AnalyticsService.shared.setUserProperty(
                "prior_tool",
                value: survey.priorTools.map { $0.rawValue }
            )
        }
        AnalyticsService.shared.track(.surveySubmitted, properties: [
            "acquisition_source": survey.acquisitionSource?.rawValue ?? "skipped",
            "use_case_count": survey.useCaseIntents.count,
            "prior_tool_count": survey.priorTools.count,
        ])
    }
}

#Preview {
    OnboardingCoordinator()
}

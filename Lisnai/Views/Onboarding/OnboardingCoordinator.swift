import SwiftUI

/// Main onboarding flow — 6 screens via scroll storytelling.
/// Clean opacity transitions (no blur/scale) per onboarding redesign plan.
struct OnboardingCoordinator: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("selectedUserDomain") private var selectedDomainRaw: String = ""
    @State private var selectedDomain: UserDomain?
    @State private var demoResult: DemoResult?
    @State private var survey = SurveyResponse()
    @State private var showSetupScreen = false

    private let screenHeight = UIScreen.main.bounds.height

    var body: some View {
        ZStack {
            LisnColors.bgPrimary.ignoresSafeArea()

            LisnAmbientBackground()
                .ignoresSafeArea()
                .opacity(0.6)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    OnboardingWelcomeScreen()
                        .frame(height: screenHeight)
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.3)
                        }

                    OnboardingValueScreen()
                        .frame(height: screenHeight)
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.3)
                        }

                    OnboardingSurveyScreen(survey: $survey) {
                        submitSurvey()
                    }
                    .containerRelativeFrame(.vertical)
                    .scrollTransition { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0.3)
                    }

                    OnboardingDemoScreen(domain: selectedDomain, result: $demoResult)
                        .frame(minHeight: screenHeight)
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.3)
                        }

                    OnboardingCTAScreen(demoResult: demoResult) {
                        showSetupScreen = true
                    }
                    .frame(height: screenHeight)
                    .scrollTransition { content, phase in
                        content.opacity(phase.isIdentity ? 1 : 0.3)
                    }
                }
            }
            .scrollTargetBehavior(.paging)
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showSetupScreen) {
            OnboardingSetupScreen {
                completeOnboarding()
            }
        }
        .onAppear {
            AnalyticsService.shared.track(.onboardingStarted)
        }
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

    private func submitSurvey() {
        guard survey.isComplete else { return }
        let payload = survey.backendPayload()

        Task {
            do {
                try await APIService.shared.submitSurvey(payload)
                print("[Survey] Submitted to backend")
            } catch {
                print("[Survey] Backend submit failed (non-fatal): \(error.localizedDescription)")
            }
        }

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

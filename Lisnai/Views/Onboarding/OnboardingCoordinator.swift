import SwiftUI

/// Tracks time spent on a screen and fires analytics on disappear.
private struct DwellTimeTracker: ViewModifier {
    let pageName: String
    @State private var appearedAt: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                appearedAt = Date()
                AnalyticsService.shared.track(.onboardingPageViewed, properties: [
                    "page": pageName
                ])
            }
            .onDisappear {
                guard let start = appearedAt else { return }
                let dwellSeconds = Date().timeIntervalSince(start)
                AnalyticsService.shared.track(.onboardingPageDwellTime, properties: [
                    "page": pageName,
                    "dwell_seconds": round(dwellSeconds * 10) / 10
                ])
            }
    }
}

private extension View {
    func trackDwellTime(page: String) -> some View {
        modifier(DwellTimeTracker(pageName: page))
    }
}

/// Main onboarding flow — 5 screens via scroll storytelling + setup overlay.
/// Clean opacity transitions (no blur/scale) per onboarding redesign plan.
struct OnboardingCoordinator: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("selectedUserDomain") private var selectedDomainRaw: String = ""
    @State private var selectedDomain: UserDomain?
    @State private var demoResult: DemoResult?
    @State private var survey = SurveyResponse()
    @State private var showSetupScreen = false
    @State private var onboardingStartTime = Date()

    private let screenHeight = UIScreen.main.bounds.height

    var body: some View {
        ZStack {
            LisnColors.bgPrimary.ignoresSafeArea()

            LisnAmbientBackground()
                .ignoresSafeArea()
                .opacity(0.6)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        OnboardingWelcomeScreen()
                            .frame(height: screenHeight)
                            .id("welcome")
                            .trackDwellTime(page: "welcome")
                            .scrollTransition { content, phase in
                                content.opacity(phase.isIdentity ? 1 : 0.3)
                            }

                        OnboardingValueScreen()
                            .frame(height: screenHeight)
                            .id("value")
                            .trackDwellTime(page: "how_it_works")
                            .scrollTransition { content, phase in
                                content.opacity(phase.isIdentity ? 1 : 0.3)
                            }

                        OnboardingSurveyScreen(survey: $survey) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo("demo", anchor: .top)
                            }
                        }
                        .containerRelativeFrame(.vertical)
                        .id("survey")
                        .trackDwellTime(page: "survey")
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.3)
                        }

                        OnboardingDemoScreen(domain: selectedDomain, result: $demoResult)
                            .frame(minHeight: screenHeight)
                            .id("demo")
                            .trackDwellTime(page: "demo")
                            .scrollTransition { content, phase in
                                content.opacity(phase.isIdentity ? 1 : 0.3)
                            }

                        OnboardingCTAScreen(demoResult: demoResult) {
                            showSetupScreen = true
                        }
                        .frame(height: screenHeight)
                        .id("cta")
                        .trackDwellTime(page: "cta")
                        .scrollTransition { content, phase in
                            content.opacity(phase.isIdentity ? 1 : 0.3)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
            }
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
        let totalSeconds = Date().timeIntervalSince(onboardingStartTime)
        AnalyticsService.shared.track(.onboardingCompleted, properties: [
            "total_seconds": round(totalSeconds * 10) / 10,
            "did_record_demo": demoResult != nil,
        ])
        withAnimation(.easeOut(duration: 0.4)) {
            hasCompletedOnboarding = true
        }
    }
}

#Preview {
    OnboardingCoordinator()
}

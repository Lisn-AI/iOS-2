import SwiftUI

/// Main onboarding flow — 5 screens via scroll storytelling
struct OnboardingCoordinator: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("selectedUserDomain") private var selectedDomainRaw: String = ""
    @State private var selectedDomain: UserDomain?
    @State private var demoResult: DemoResult?
    @State private var meshPhase: Bool = false

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

                    OnboardingSurveyScreen(selectedDomain: $selectedDomain)
                        .frame(height: screenHeight)
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
    }

    // MARK: - Animated Mesh Background

    @ViewBuilder
    private var meshBackground: some View {
        if #available(iOS 18.0, *) {
            if colorScheme == .dark {
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [meshPhase ? 0.1 : 0.0, 0.5], [meshPhase ? 0.6 : 0.4, meshPhase ? 0.6 : 0.4], [meshPhase ? 0.9 : 1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(red: 0.04, green: 0.04, blue: 0.06),
                        Color(red: 0.08, green: 0.06, blue: 0.12),
                        Color(red: 0.04, green: 0.04, blue: 0.06),
                        Color(red: 0.06, green: 0.04, blue: 0.08),
                        meshPhase
                            ? Color(red: 0.20, green: 0.12, blue: 0.06)
                            : Color(red: 0.12, green: 0.06, blue: 0.16),
                        Color(red: 0.06, green: 0.04, blue: 0.08),
                        Color(red: 0.04, green: 0.04, blue: 0.06),
                        Color(red: 0.06, green: 0.05, blue: 0.10),
                        Color(red: 0.04, green: 0.04, blue: 0.06)
                    ]
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                        meshPhase = true
                    }
                }
            } else {
                // Light mode: warm cream / soft peach / lavender
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: [
                        [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                        [meshPhase ? 0.1 : 0.0, 0.5], [meshPhase ? 0.6 : 0.4, meshPhase ? 0.6 : 0.4], [meshPhase ? 0.9 : 1.0, 0.5],
                        [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
                    ],
                    colors: [
                        Color(red: 1.0, green: 0.99, blue: 0.96),
                        Color(red: 0.98, green: 0.95, blue: 0.92),
                        Color(red: 1.0, green: 0.99, blue: 0.96),
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        meshPhase
                            ? Color(red: 0.96, green: 0.88, blue: 0.78) // warm peach center
                            : Color(red: 0.94, green: 0.92, blue: 0.98), // soft lavender center
                        Color(red: 0.98, green: 0.96, blue: 0.94),
                        Color(red: 1.0, green: 0.99, blue: 0.96),
                        Color(red: 0.97, green: 0.95, blue: 0.93),
                        Color(red: 1.0, green: 0.99, blue: 0.96)
                    ]
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                        meshPhase = true
                    }
                }
            }
        } else {
            // Fallback for iOS 17
            LinearGradient(
                colors: colorScheme == .dark
                    ? [
                        Color(red: 0.04, green: 0.04, blue: 0.06),
                        Color(red: 0.10, green: 0.06, blue: 0.14),
                        Color(red: 0.04, green: 0.04, blue: 0.06)
                    ]
                    : [
                        Color(red: 1.0, green: 0.99, blue: 0.96),
                        Color(red: 0.96, green: 0.92, blue: 0.88),
                        Color(red: 1.0, green: 0.99, blue: 0.96)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func completeOnboarding() {
        if let domain = selectedDomain {
            selectedDomainRaw = domain.rawValue
        }
        withAnimation(.easeOut(duration: 0.4)) {
            hasCompletedOnboarding = true
        }
    }
}

#Preview {
    OnboardingCoordinator()
}

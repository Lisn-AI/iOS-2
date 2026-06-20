import SwiftUI
import Lottie

/// Screen 1: Hero welcome with Lottie animation + gradient text.
struct OnboardingWelcomeScreen: View {
    @State private var showLottie = false
    @State private var showLine1 = false
    @State private var showLine2 = false
    @State private var showSubtitle = false
    @State private var showHint = false
    @State private var hintBounce = false

    // Floating particle state
    @State private var particleOffset1: CGFloat = 0
    @State private var particleOffset2: CGFloat = 0
    @State private var particleOffset3: CGFloat = 0

    var body: some View {
        ZStack {
            // Floating ambient particles
            floatingParticles

            VStack(spacing: 0) {
                Spacer()

                // Lottie animation (centered, bigger and attention-grabbing)
                if showLottie {
                    LottieView(animation: .named("rocket"))
                        .playing(loopMode: .loop)
                        .frame(width: 200, height: 200)
                        .transition(.scale.combined(with: .opacity))
                        .padding(.bottom, LisnSpacing.xl)
                }

                // Hero text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remember")
                        .font(.custom("Inter-Bold", size: 52))
                        .foregroundColor(LisnColors.textPrimary)
                        .opacity(showLine1 ? 1 : 0)
                        .offset(y: showLine1 ? 0 : 30)

                    Text("Everything.")
                        .font(.custom("Inter-Bold", size: 52))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LisnColors.orbLight, LisnColors.accent, LisnColors.orbDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .opacity(showLine2 ? 1 : 0)
                        .offset(y: showLine2 ? 0 : 30)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)

                // Subtitle
                Text("Your Conversations, Captured\nand Understood. Effortlessly.")
                    .font(.custom("Inter-Regular", size: 17))
                    .foregroundColor(LisnColors.textSecondary)
                    .lineSpacing(5)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 12)
                    .padding(.top, 20)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
                Spacer()

                // Scroll hint
                if showHint {
                    VStack(spacing: 6) {
                        Text("SCROLL")
                            .font(.custom("Inter-Medium", size: 11))
                            .foregroundColor(LisnColors.textTertiary)
                            .tracking(3)

                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 18, weight: .light))
                            .foregroundColor(LisnColors.accent.opacity(0.5))
                            .offset(y: hintBounce ? 5 : 0)
                    }
                    .transition(.opacity)
                    .padding(.bottom, 60)
                }
            }
        }
        .onAppear { startAnimation() }
    }

    private var floatingParticles: some View {
        ZStack {
            Circle()
                .fill(LisnColors.accent.opacity(0.15))
                .frame(width: 12, height: 12)
                .offset(x: -80, y: -200 + particleOffset1)
                .blur(radius: 1)

            Circle()
                .fill(LisnColors.orbLight.opacity(0.12))
                .frame(width: 8, height: 8)
                .offset(x: 100, y: -100 + particleOffset2)
                .blur(radius: 1)

            Circle()
                .fill(LisnColors.accent.opacity(0.1))
                .frame(width: 16, height: 16)
                .offset(x: 60, y: 150 + particleOffset3)
                .blur(radius: 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                particleOffset1 = -20
            }
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true).delay(0.5)) {
                particleOffset2 = 15
            }
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true).delay(1)) {
                particleOffset3 = -25
            }
        }
    }

    private func startAnimation() {
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2)) {
            showLottie = true
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.5)) {
            showLine1 = true
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.8)) {
            showLine2 = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) {
            showSubtitle = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.5)) { showHint = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.2)) {
                hintBounce = true
            }
        }
    }
}

#Preview {
    OnboardingWelcomeScreen()
        .background(LisnColors.bgPrimary)
}

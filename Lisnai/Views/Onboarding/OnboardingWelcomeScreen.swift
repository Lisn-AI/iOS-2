import SwiftUI
import Vortex

/// Screen 1: Cinematic welcome with gradient text and ambient glow
struct OnboardingWelcomeScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLine1 = false
    @State private var showLine2 = false
    @State private var showSubtitle = false
    @State private var showHint = false
    @State private var hintBounce = false
    @State private var glowPulse = false
    @State private var particlesActive = false

    var body: some View {
        ZStack {
            // Central ambient glow orb
            RadialGradient(
                colors: [
                    LisnColors.accent.opacity(glowPulse ? 0.15 : 0.08),
                    LisnColors.accent.opacity(0.03),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 350
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: glowPulse)

            // Ambient particles
            VortexView(createAmbientSystem()) {
                Circle()
                    .fill(LisnColors.accent.opacity(colorScheme == .dark ? 0.5 : 0.3))
                    .frame(width: 4)
                    .blur(radius: 1)
                    .tag("dot")
            }
            .opacity(particlesActive ? (colorScheme == .dark ? 0.5 : 0.35) : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()
                Spacer()

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
                                colors: [
                                    LisnColors.orbLight,
                                    LisnColors.accent,
                                    LisnColors.orbDark
                                ],
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
                    .padding(.bottom, 48)
                }
            }
        }
        .onAppear { startAnimation() }
    }

    private func startAnimation() {
        glowPulse = true

        withAnimation(.easeIn(duration: 1.0)) {
            particlesActive = true
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.4)) {
            showLine1 = true
        }
        withAnimation(.spring(response: 0.8, dampingFraction: 0.72).delay(0.7)) {
            showLine2 = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.3)) {
            showSubtitle = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeInOut(duration: 0.5)) { showHint = true }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(0.2)) {
                hintBounce = true
            }
        }
    }
}

// MARK: - Ambient Particle System

func createAmbientSystem() -> VortexSystem {
    var system = VortexSystem(tags: ["dot"])
    system.position = [0.5, 0.5]
    system.speed = 0.10
    system.speedVariation = 0.06
    system.angle = .degrees(0)
    system.angleRange = .degrees(360)
    system.birthRate = 5
    system.lifespan = 6.0
    system.lifespanVariation = 2.0
    system.size = 0.2
    system.sizeVariation = 0.1
    system.sizeMultiplierAtDeath = 0
    return system
}

#Preview {
    OnboardingWelcomeScreen()
        .background(LisnColors.bgPrimary)
}

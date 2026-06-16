import SwiftUI

/// Screen 1: Cinematic welcome with gradient text on a single ambient bloom.
/// Per DESIGN.md Part 5: pure typography moment, no Vortex, no mascot.
struct OnboardingWelcomeScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLine1 = false
    @State private var showLine2 = false
    @State private var showSubtitle = false
    @State private var showHint = false
    @State private var hintBounce = false

    var body: some View {
        ZStack {
            // Single ambient bloom — no competing animations
            LisnAmbientBackground()

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

#Preview {
    OnboardingWelcomeScreen()
        .background(LisnColors.bgPrimary)
}

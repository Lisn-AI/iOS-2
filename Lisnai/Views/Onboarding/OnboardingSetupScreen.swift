import SwiftUI

/// Screen between onboarding CTA and LoginView.
/// Cal AI-inspired "setting up your journal" loading sequence.
/// Creates anticipation + sunk-cost — user feels the app built something for them.
struct OnboardingSetupScreen: View {
    let onComplete: () -> Void

    @State private var showTitle = false
    @State private var item1 = false
    @State private var item2 = false
    @State private var item3 = false
    @State private var item4 = false
    @State private var showButton = false
    @State private var glowPulse = false

    private let items: [(icon: String, text: String)] = [
        ("waveform", "Voice recognition configured"),
        ("brain.head.profile", "AI insights engine ready"),
        ("archivebox", "Memory vault initialized"),
        ("bolt.circle", "Smart actions enabled"),
    ]

    var body: some View {
        ZStack {
            LisnColors.bgPrimary.ignoresSafeArea()

            // Ambient glow
            RadialGradient(
                colors: [
                    LisnColors.accent.opacity(glowPulse ? 0.15 : 0.05),
                    Color.clear
                ],
                center: .center,
                startRadius: 10,
                endRadius: 250
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true), value: glowPulse)

            VStack(spacing: 0) {
                Spacer()

                // Title
                VStack(spacing: LisnSpacing.sm) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 36))
                        .foregroundStyle(LisnColors.accent)

                    Text("Setting up your\nAI journal...")
                        .font(.custom("Inter-Bold", size: 32))
                        .foregroundColor(LisnColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .opacity(showTitle ? 1 : 0)
                .scaleEffect(showTitle ? 1 : 0.9)
                .padding(.bottom, LisnSpacing.xxxxl)

                // Staggered setup items
                VStack(alignment: .leading, spacing: LisnSpacing.lg) {
                    setupItem(0, visible: item1)
                    setupItem(1, visible: item2)
                    setupItem(2, visible: item3)
                    setupItem(3, visible: item4)
                }
                .padding(.horizontal, 40)

                Spacer()
                Spacer()

                // Get Started button (appears after all items)
                if showButton {
                    Button {
                        LisnHaptics.medium()
                        onComplete()
                    } label: {
                        Text("Let's Go")
                            .font(.custom("Inter-SemiBold", size: 17))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(
                                LinearGradient(
                                    colors: [LisnColors.orbLight, LisnColors.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: LisnColors.accent.opacity(0.3), radius: 12, y: 4)
                    }
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()
                    .frame(height: 60)
            }
        }
        .onAppear { startSequence() }
    }

    private func setupItem(_ index: Int, visible: Bool) -> some View {
        HStack(spacing: LisnSpacing.md) {
            ZStack {
                Circle()
                    .fill(LisnColors.accent.opacity(visible ? 0.15 : 0))
                    .frame(width: 36, height: 36)

                Image(systemName: visible ? "checkmark" : items[index].icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(visible ? LisnColors.success : LisnColors.textTertiary)
            }

            Text(items[index].text)
                .font(.custom("Inter-Medium", size: 16))
                .foregroundColor(visible ? LisnColors.textPrimary : LisnColors.textTertiary)
        }
        .opacity(visible ? 1 : 0.3)
        .offset(x: visible ? 0 : -20)
    }

    private func startSequence() {
        glowPulse = true

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            showTitle = true
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.6)) {
            item1 = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(1.3)) {
            item2 = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(2.0)) {
            item3 = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(2.8)) {
            item4 = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                showButton = true
            }
            LisnHaptics.success()
        }
    }
}

#Preview {
    OnboardingSetupScreen(onComplete: {})
}

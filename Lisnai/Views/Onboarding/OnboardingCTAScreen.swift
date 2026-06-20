import SwiftUI

/// Screen 5: Final CTA — "Get Started" button (no sign-in, that's in LoginView).
struct OnboardingCTAScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    let demoResult: DemoResult?
    let onComplete: () -> Void

    @State private var showHero = false
    @State private var showSummary = false
    @State private var showButton = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    LisnColors.accent.opacity(glowPulse ? 0.12 : 0.06),
                    Color.clear
                ],
                center: .init(x: 0.5, y: 0.65),
                startRadius: 20,
                endRadius: 300
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: glowPulse)

            VStack(spacing: 0) {
                Spacer()

                // Hero text
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ready to Never")
                        .font(.custom("Inter-Bold", size: 36))
                        .foregroundColor(LisnColors.textPrimary)

                    Text("Forget Again?")
                        .font(.custom("Inter-Bold", size: 36))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LisnColors.orbLight, LisnColors.accent, LisnColors.orbDark],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .opacity(showHero ? 1 : 0)
                .offset(y: showHero ? 0 : 20)

                // Demo summary
                if let result = demoResult {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 16))
                            .foregroundColor(LisnColors.accent)

                        Text("Lisn AI Found \(result.summaryText) in Just One Conversation.")
                            .font(.custom("Inter-Regular", size: 14))
                            .foregroundColor(LisnColors.textSecondary)
                            .lineSpacing(2)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .opacity(showSummary ? 1 : 0)
                }

                Text("Imagine What It Can Do With Your Full Day.")
                    .font(.custom("Inter-Medium", size: 15))
                    .foregroundColor(LisnColors.textTertiary)
                    .padding(.top, 16)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showSummary ? 1 : 0)

                Spacer()

                // Single CTA button — no sign-in (LoginView handles that)
                VStack(spacing: 12) {
                    Button {
                        LisnHaptics.medium()
                        onComplete()
                    } label: {
                        Text("Get Started")
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
                }
                .padding(.horizontal, 28)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 15)

                Spacer()
                    .frame(height: 48)
            }
        }
        .onAppear {
            glowPulse = true
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
                showHero = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                showSummary = true
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.0)) {
                showButton = true
            }
        }
    }
}

#Preview {
    OnboardingCTAScreen(
        demoResult: demoResults[.sales],
        onComplete: {}
    )
    .background(LisnColors.bgPrimary)
}

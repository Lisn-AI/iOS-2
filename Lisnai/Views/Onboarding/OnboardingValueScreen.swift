import SwiftUI

/// Screen 2: Three value propositions with glass morphism cards
struct OnboardingValueScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var showHeader = false
    @State private var cardVisible = [false, false, false]

    private let values: [(lottie: String, icon: String, title: String, desc: String, accent: Color)] = [
        (
            "headphones",
            "waveform",
            "Capture",
            "Record conversations hands-free.\nJust press record and be present.",
            Color(red: 0.90, green: 0.62, blue: 0.30)
        ),
        (
            "bulb",
            "sparkles",
            "Understand",
            "AI extracts people, commitments,\nand key details automatically.",
            Color(red: 0.68, green: 0.52, blue: 0.88)
        ),
        (
            "gears",
            "bell.badge",
            "Act",
            "Get reminders and next steps\nbefore you even ask.",
            Color(red: 0.35, green: 0.78, blue: 0.60)
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Section header
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW IT WORKS")
                    .font(.custom("Inter-SemiBold", size: 12))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [LisnColors.orbLight, LisnColors.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .tracking(3)

                Text("Three Steps.\nZero Effort.")
                    .font(.custom("Inter-Bold", size: 34))
                    .foregroundColor(LisnColors.textPrimary)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .opacity(showHeader ? 1 : 0)
            .offset(y: showHeader ? 0 : 20)

            Spacer()
                .frame(height: 36)

            // Value cards
            VStack(spacing: 16) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    valueCard(
                        lottieName: value.lottie,
                        icon: value.icon,
                        title: value.title,
                        description: value.desc,
                        accent: value.accent,
                        number: index + 1
                    )
                    .opacity(cardVisible[index] ? 1 : 0)
                    .offset(y: cardVisible[index] ? 0 : 30)
                }
            }
            .padding(.horizontal, 20)

            Spacer()
            Spacer()
        }
        .onAppear { animate() }
    }

    // MARK: - Value Card

    private func valueCard(
        lottieName: String,
        icon: String,
        title: String,
        description: String,
        accent: Color,
        number: Int
    ) -> some View {
        HStack(spacing: 16) {
            // Lottie icon with accent glow
            ZStack {
                Circle()
                    .fill(accent.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 56, height: 56)
                    .blur(radius: 8)

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(colorScheme == .dark ? 0.15 : 0.1))
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accent.opacity(colorScheme == .dark ? 0.25 : 0.2), lineWidth: 1)
                    )

                LottieIconView(iconName: lottieName, size: 32)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(number).")
                        .font(.custom("Inter-Bold", size: 14))
                        .foregroundColor(LisnColors.textTertiary)

                    Text(title)
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundColor(LisnColors.textPrimary)
                }

                Text(description)
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundColor(LisnColors.textSecondary)
                    .lineSpacing(3)
            }

            Spacer()
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06),
                    lineWidth: 1
                )
        )
        .shadow(
            color: colorScheme == .dark ? .clear : .black.opacity(0.04),
            radius: 8,
            y: 4
        )
    }

    private func animate() {
        withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
            showHeader = true
        }
        for i in 0..<3 {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(0.5 + Double(i) * 0.18)) {
                cardVisible[i] = true
            }
        }
    }
}

#Preview {
    OnboardingValueScreen()
        .background(LisnColors.bgPrimary)
}

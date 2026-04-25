import SwiftUI

/// Screen 3: Personalization survey with glass morphism cards
struct OnboardingSurveyScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedDomain: UserDomain?

    @State private var showQuestion = false
    @State private var showCards = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(maxHeight: 80)

            // Question header
            VStack(alignment: .leading, spacing: 2) {
                Text("What's Your")
                    .font(.custom("Inter-Bold", size: 32))
                    .foregroundColor(LisnColors.textPrimary)

                Text("Biggest Challenge?")
                    .font(.custom("Inter-Bold", size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [LisnColors.orbLight, LisnColors.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
            .opacity(showQuestion ? 1 : 0)
            .offset(y: showQuestion ? 0 : 20)

            Spacer()
                .frame(height: 28)

            // Domain cards
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(UserDomain.allCases, id: \.self) { domain in
                        domainCard(domain)
                    }
                }
                .padding(.horizontal, 28)
            }
            .frame(maxHeight: 420)
            .opacity(showCards ? 1 : 0)

            Spacer()

            // Selection confirmation
            if selectedDomain != nil {
                Text("Great Choice. Scroll to See Lisn in Action.")
                    .font(.custom("Inter-Medium", size: 13))
                    .foregroundColor(LisnColors.textTertiary)
                    .tracking(0.5)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .padding(.bottom, 48)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(0.2)) {
                showQuestion = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
                showCards = true
            }
        }
    }

    // MARK: - Domain Card

    private func domainCard(_ domain: UserDomain) -> some View {
        let isSelected = selectedDomain == domain

        return Button {
            LisnHaptics.medium()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                selectedDomain = domain
            }
        } label: {
            HStack(spacing: 14) {
                // Icon
                Image(systemName: domain.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .white : LisnColors.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(isSelected ? LisnColors.accent : LisnColors.accent.opacity(0.12))
                    )
                    .shadow(color: isSelected ? LisnColors.accent.opacity(0.4) : .clear, radius: 8)

                // Text
                VStack(alignment: .leading, spacing: 2) {
                    Text(domain.title)
                        .font(.custom("Inter-Medium", size: 15))
                        .foregroundColor(LisnColors.textPrimary)

                    Text(domain.subtitle)
                        .font(.custom("Inter-Regular", size: 12))
                        .foregroundColor(LisnColors.textTertiary)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(LisnColors.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected
                            ? LisnColors.accent.opacity(0.5)
                            : (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .shadow(
                color: isSelected
                    ? LisnColors.accent.opacity(0.15)
                    : (colorScheme == .dark ? .clear : .black.opacity(0.03)),
                radius: isSelected ? 12 : 6,
                y: isSelected ? 0 : 3
            )
            .scaleEffect(isSelected ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Preview: View {
        @State private var domain: UserDomain?
        var body: some View {
            OnboardingSurveyScreen(selectedDomain: $domain)
                .background(LisnColors.bgPrimary)
        }
    }
    return Preview()
}

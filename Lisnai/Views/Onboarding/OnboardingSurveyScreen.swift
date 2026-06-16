import SwiftUI

/// Screen 3: Growth-focused onboarding survey.
/// Three questions — see DESIGN.md Part 5 + Part 6b.
struct OnboardingSurveyScreen: View {
    @Binding var survey: SurveyResponse
    var onContinue: () -> Void

    @State private var showQ1 = false
    @State private var showQ2 = false
    @State private var showQ3 = false
    @State private var showContinue = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LisnSpacing.xxl) {
                heroHeader

                question1
                    .opacity(showQ1 ? 1 : 0)
                    .offset(y: showQ1 ? 0 : 16)

                question2
                    .opacity(showQ2 ? 1 : 0)
                    .offset(y: showQ2 ? 0 : 16)

                question3
                    .opacity(showQ3 ? 1 : 0)
                    .offset(y: showQ3 ? 0 : 16)

                continueButton
                    .opacity(showContinue && survey.isComplete ? 1 : 0)
                    .padding(.bottom, LisnSpacing.xxl)
            }
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.top, LisnSpacing.xxxl)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { showQ1 = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) { showQ2 = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.8)) { showQ3 = true }
            withAnimation(.easeOut(duration: 0.5).delay(1.0)) { showContinue = true }
        }
    }

    // MARK: - Header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
            Text("Help us tailor Lisn")
                .font(.custom("Inter-Bold", size: 32))
                .foregroundStyle(
                    LinearGradient(
                        colors: [LisnColors.orbLight, LisnColors.accent, LisnColors.orbDark],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineLimit(2)

            Text("Three quick questions. We use this to make Lisn better for you.")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Q1: Acquisition

    private var question1: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            sectionLabel("01")
            Text("How did you find Lisn?")
                .font(LisnFont.titleLarge())
                .foregroundColor(LisnColors.textPrimary)

            VStack(spacing: LisnSpacing.xs) {
                ForEach(AcquisitionSource.allCases) { source in
                    OptionRow(
                        title: source.title,
                        icon: source.icon,
                        isSelected: survey.acquisitionSource == source
                    ) {
                        LisnHaptics.medium()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            survey.acquisitionSource = source
                        }
                    }
                }
            }
        }
    }

    // MARK: - Q2: Use case (multi-select)

    private var question2: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            sectionLabel("02 · Choose any")
            Text("What do you want Lisn to remember?")
                .font(LisnFont.titleLarge())
                .foregroundColor(LisnColors.textPrimary)

            VStack(spacing: LisnSpacing.xs) {
                ForEach(UseCaseIntent.allCases) { intent in
                    OptionRow(
                        title: intent.title,
                        subtitle: intent.subtitle,
                        icon: intent.icon,
                        isSelected: survey.useCaseIntents.contains(intent)
                    ) {
                        LisnHaptics.light()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            if survey.useCaseIntents.contains(intent) {
                                survey.useCaseIntents.remove(intent)
                            } else {
                                survey.useCaseIntents.insert(intent)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Q3: Prior tool (multi-select, optional)

    private var question3: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            sectionLabel("03 · Optional")
            Text("What were you using before?")
                .font(LisnFont.titleLarge())
                .foregroundColor(LisnColors.textPrimary)

            // Wrap in chips
            chipsWrap
        }
    }

    private var chipsWrap: some View {
        // Simple wrapping HStack with manual width handling
        let rows = chunked(PriorTool.allCases, into: 2)
        return VStack(alignment: .leading, spacing: LisnSpacing.xs) {
            ForEach(0..<rows.count, id: \.self) { rowIdx in
                HStack(spacing: LisnSpacing.xs) {
                    ForEach(rows[rowIdx]) { tool in
                        ChipOption(
                            title: tool.title,
                            isSelected: survey.priorTools.contains(tool)
                        ) {
                            LisnHaptics.light()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                if survey.priorTools.contains(tool) {
                                    survey.priorTools.remove(tool)
                                } else {
                                    survey.priorTools.insert(tool)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Continue

    private var continueButton: some View {
        Button {
            LisnHaptics.success()
            onContinue()
        } label: {
            HStack {
                Text("Continue")
                    .font(LisnFont.labelLarge())
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [LisnColors.orbLight, LisnColors.orbDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Capsule())
            .shadow(color: LisnColors.accent.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!survey.isComplete)
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(LisnFont.labelSmall())
            .tracking(1.5)
            .foregroundColor(LisnColors.textTertiary)
    }

    private func chunked<T>(_ array: [T], into size: Int) -> [[T]] {
        stride(from: 0, to: array.count, by: size).map {
            Array(array[$0..<min($0 + size, array.count)])
        }
    }
}

// MARK: - Reusable subviews

private struct OptionRow: View {
    let title: String
    var subtitle: String? = nil
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: LisnSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isSelected ? .white : LisnColors.accent)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(isSelected ? LisnColors.accent : LisnColors.accent.opacity(0.10))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(LisnFont.labelLarge())
                        .foregroundColor(LisnColors.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(LisnFont.bodySmall())
                            .foregroundColor(LisnColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? LisnColors.accent : LisnColors.textTertiary.opacity(0.4))
            }
            .padding(.horizontal, LisnSpacing.md)
            .padding(.vertical, LisnSpacing.sm)
            .background(LisnColors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                    .stroke(
                        isSelected ? LisnColors.accent.opacity(0.5) : LisnColors.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
            .scaleEffect(isSelected ? 1.015 : 1.0)
        }
        .buttonStyle(.plain)
    }
}

private struct ChipOption: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(LisnFont.labelMedium())
                .foregroundColor(isSelected ? .white : LisnColors.textPrimary)
                .padding(.horizontal, LisnSpacing.md)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isSelected ? LisnColors.accent : LisnColors.bgElevated)
                )
                .overlay(
                    Capsule().stroke(
                        isSelected ? LisnColors.accent : LisnColors.borderSubtle,
                        lineWidth: isSelected ? 1 : 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Preview: View {
        @State private var survey = SurveyResponse()
        var body: some View {
            OnboardingSurveyScreen(survey: $survey) { print("Continue") }
                .background(LisnColors.bgPrimary)
        }
    }
    return Preview()
}

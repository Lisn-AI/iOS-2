import SwiftUI

/// Screen 3: One-question-per-screen survey (Cal AI style).
/// Swipes horizontally between Q1/Q2/Q3 with auto-advance on selection.
/// Survey data is cached in UserDefaults — submitted after sign-in.
struct OnboardingSurveyScreen: View {
    @Binding var survey: SurveyResponse
    var onContinue: () -> Void

    @State private var currentQuestion = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { idx in
                    Circle()
                        .fill(idx <= currentQuestion ? LisnColors.accent : LisnColors.textTertiary.opacity(0.3))
                        .frame(width: idx == currentQuestion ? 10 : 6, height: idx == currentQuestion ? 10 : 6)
                        .animation(.spring(response: 0.3), value: currentQuestion)
                }
            }
            .padding(.top, LisnSpacing.xxxl)
            .padding(.bottom, LisnSpacing.lg)

            // Question number
            Text("\(currentQuestion + 1) of 3")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)
                .padding(.bottom, LisnSpacing.xxl)

            // Question content — one at a time
            TabView(selection: $currentQuestion) {
                questionView(
                    title: "How did you find Lisn?",
                    content: { question1Content }
                ).tag(0)

                questionView(
                    title: "What do you want\nLisn to remember?",
                    content: { question2Content }
                ).tag(1)

                questionView(
                    title: "What were you\nusing before?",
                    content: { question3Content }
                ).tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentQuestion)

            Spacer()
        }
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
        }
    }

    // MARK: - Question Container

    private func questionView<Content: View>(
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LisnSpacing.xl) {
                Text(title)
                    .font(.custom("Inter-Bold", size: 28))
                    .foregroundColor(LisnColors.textPrimary)
                    .lineSpacing(4)
                    .padding(.horizontal, LisnSpacing.lg)

                content()
                    .padding(.horizontal, LisnSpacing.lg)
            }
            .padding(.top, LisnSpacing.md)
        }
    }

    // MARK: - Q1: Acquisition (single select → auto-advance)

    private var question1Content: some View {
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
                    // Auto-advance after selection
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        withAnimation { currentQuestion = 1 }
                    }
                }
            }
        }
    }

    // MARK: - Q2: Use case (multi-select → manual advance via button)

    private var question2Content: some View {
        VStack(spacing: LisnSpacing.sm) {
            Text("Choose any that apply")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

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

            // Next button (only for multi-select)
            if !survey.useCaseIntents.isEmpty {
                Button {
                    LisnHaptics.medium()
                    withAnimation { currentQuestion = 2 }
                } label: {
                    Text("Next →")
                        .font(LisnFont.labelLarge())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LisnColors.accent)
                        .clipShape(Capsule())
                }
                .padding(.top, LisnSpacing.md)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    // MARK: - Q3: Prior tool (multi-select, optional → Done button)

    private var question3Content: some View {
        VStack(spacing: LisnSpacing.sm) {
            Text("Optional — helps us improve")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            chipsWrap

            // Done button — caches survey + scrolls to next page
            Button {
                LisnHaptics.success()
                cacheSurveyLocally()
                AnalyticsService.shared.track(.surveySubmitted, properties: [
                    "acquisition_source": survey.acquisitionSource?.rawValue ?? "skipped",
                    "use_case_count": survey.useCaseIntents.count,
                    "prior_tool_count": survey.priorTools.count,
                ])
                onContinue()
            } label: {
                Text("Done →")
                    .font(LisnFont.labelLarge())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [LisnColors.orbLight, LisnColors.accent],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
                    .shadow(color: LisnColors.accent.opacity(0.3), radius: 10, y: 4)
            }
            .padding(.top, LisnSpacing.lg)
        }
    }

    private var chipsWrap: some View {
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

    // MARK: - Local cache (user isn't signed in yet)

    private func cacheSurveyLocally() {
        if let source = survey.acquisitionSource?.rawValue {
            UserDefaults.standard.set(source, forKey: "pendingSurvey_acquisitionSource")
        }
        UserDefaults.standard.set(
            survey.useCaseIntents.map { $0.rawValue },
            forKey: "pendingSurvey_useCaseIntents"
        )
        UserDefaults.standard.set(
            survey.priorTools.map { $0.rawValue },
            forKey: "pendingSurvey_priorTools"
        )
        UserDefaults.standard.set(true, forKey: "pendingSurvey_exists")
    }

    // MARK: - Helpers

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
            OnboardingSurveyScreen(survey: $survey) { print("Done") }
                .background(LisnColors.bgPrimary)
        }
    }
    return Preview()
}

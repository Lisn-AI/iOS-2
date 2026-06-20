import SwiftUI

/// Screen 4: Interactive demo — real recording + live transcript + executable actions
struct OnboardingDemoScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    let domain: UserDomain?
    @Binding var result: DemoResult?

    @StateObject private var recorder = OnboardingRecorder()
    @State private var phase: DemoPhase = .prompt
    @State private var progress: CGFloat = 0
    @State private var statusIndex = 0
    @State private var showResults = false
    @State private var showInsights = [Bool]()
    @State private var showActions = [Bool]()
    @State private var celebrate = false
    @State private var actionStates: [UUID: ActionState] = [:]
    @State private var showScrollHint = false
    @State private var statusOpacity: Double = 1.0
    @State private var initialized = false

    private var activeDomain: UserDomain { domain ?? .entrepreneur }
    private var activeResult: DemoResult { demoResults[activeDomain]! }
    private var executableActions: [DemoExecutableAction] {
        demoExecutableActions[activeDomain] ?? []
    }

    private let statusTexts = [
        "Analyzing Your Words...",
        "Extracting Key Details...",
        "Identifying Actions...",
        "Almost Done..."
    ]

    enum DemoPhase {
        case prompt, recording, processing, results
    }

    enum ActionState {
        case idle, loading, success, failed(String)
    }

    // MARK: - Adaptive helpers

    private var cardBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                switch phase {
                case .prompt:
                    promptView
                case .recording:
                    recordingView
                case .processing:
                    processingView
                case .results:
                    resultsView
                }
            }
            .frame(minHeight: UIScreen.main.bounds.height)
        }
        .scrollDisabled(phase != .results)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            showInsights = Array(repeating: false, count: activeResult.insights.count)
            showActions = Array(repeating: false, count: activeResult.actions.count)
            for action in executableActions {
                actionStates[action.id] = .idle
            }
        }
    }

    // MARK: - Phase 1: Prompt

    private var promptView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Try It Yourself")
                .font(.custom("Inter-Bold", size: 32))
                .foregroundColor(LisnColors.textPrimary)

            Text("Read This Aloud and Watch Lisn AI Work")
                .font(.custom("Inter-Medium", size: 15))
                .foregroundColor(LisnColors.textSecondary)

            // Script card
            GlassCard {
                Text(activeResult.paragraph)
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundColor(LisnColors.textPrimary)
                    .lineSpacing(5)
            }
            .padding(.horizontal, 24)

            Spacer().frame(height: 16)

            RecordingOrb(
                isRecording: false,
                audioLevel: 0,
                isPaused: false,
                isCallPaused: false,
                action: { startRecording() }
            )

            Text("Tap to Start")
                .font(.custom("Inter-Medium", size: 14))
                .foregroundColor(LisnColors.textTertiary)

            Spacer()
        }
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    // MARK: - Phase 2: Recording

    private var recordingView: some View {
        ZStack {
            EdgeGlowEffect(isActive: true, audioLevel: recorder.audioLevel)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                GlassCard {
                    Text(activeResult.paragraph)
                        .font(.custom("Inter-Regular", size: 15))
                        .foregroundColor(LisnColors.textPrimary)
                        .lineSpacing(5)
                }
                .padding(.horizontal, 24)
                .opacity(0.25)

                Spacer().frame(height: 8)

                RecordingOrb(
                    isRecording: true,
                    audioLevel: recorder.audioLevel,
                    isPaused: false,
                    isCallPaused: false,
                    action: { stopRecording() }
                )

                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: .red.opacity(0.6), radius: 4)

                    Text(recorder.formattedDuration)
                        .font(.custom("Inter-Medium", size: 16))
                        .foregroundColor(LisnColors.textPrimary)
                        .monospacedDigit()

                    Text("Tap to Stop")
                        .font(.custom("Inter-Medium", size: 14))
                        .foregroundColor(LisnColors.textTertiary)
                }

                if !recorder.liveTranscript.isEmpty {
                    Text(recorder.liveTranscript)
                        .font(.custom("Inter-Regular", size: 14))
                        .foregroundColor(LisnColors.textSecondary)
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .transition(.opacity)
                        .animation(.easeOut(duration: 0.15), value: recorder.liveTranscript)
                }

                Spacer()
            }
        }
        .transition(.opacity)
    }

    // MARK: - Phase 3: Processing

    private var processingView: some View {
        VStack(spacing: 32) {
            Spacer()

            RecordingOrb(
                isRecording: false,
                audioLevel: 0,
                isPaused: false,
                isCallPaused: false,
                action: {}
            )
            .scaleEffect(0.4)
            .frame(height: 60)
            .allowsHitTesting(false)

            // Designed progress ring (no floating numbers — see DESIGN.md Part 5)
            LisnProgressRing(
                progress: Double(progress),
                size: 96,
                caption: statusTexts[min(statusIndex, statusTexts.count - 1)],
                isAnimating: true
            )
            .opacity(statusOpacity)
            .animation(.easeInOut(duration: 0.3), value: statusIndex)

            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Phase 4: Results

    private var resultsView: some View {
        VStack(spacing: 0) {
            // Results card — fills the screen width, bigger text, no thin border
            VStack(alignment: .leading, spacing: 0) {
                // Header — bigger, bolder
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 24))
                        .shadow(color: .green.opacity(0.4), radius: 6)

                    Text("Analysis Complete")
                        .font(.custom("Inter-Bold", size: 20))
                        .foregroundColor(LisnColors.textPrimary)

                    Spacer()

                    Text(activeResult.summaryText)
                        .font(.custom("Inter-SemiBold", size: 14))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [LisnColors.orbLight, LisnColors.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .padding(.bottom, 20)

                // Source text — larger, more readable
                Text("\"\(activeResult.paragraph)\"")
                    .font(.custom("Inter-Regular", size: 15))
                    .foregroundColor(LisnColors.textSecondary)
                    .lineSpacing(4)
                    .italic()
                    .padding(.bottom, 20)
                    .opacity(showResults ? 1 : 0)

                // Insights — larger text, more spacing
                if !activeResult.insights.isEmpty {
                    Text("INSIGHTS")
                        .font(.custom("Inter-Bold", size: 12))
                        .foregroundColor(LisnColors.accent)
                        .tracking(2)
                        .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(activeResult.insights.enumerated()), id: \.offset) { idx, insight in
                            HStack(alignment: .top, spacing: 10) {
                                Circle()
                                    .fill(insight.isCritical ? Color.orange : LisnColors.accent)
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 5)

                                Text(insight.text)
                                    .font(.custom("Inter-Medium", size: 15))
                                    .foregroundColor(LisnColors.textPrimary)
                                    .lineSpacing(2)
                            }
                            .opacity(idx < showInsights.count && showInsights[idx] ? 1 : 0)
                            .offset(x: idx < showInsights.count && showInsights[idx] ? 0 : -10)
                        }
                    }
                    .padding(.bottom, 18)
                }

                // Actions — bigger buttons
                if !executableActions.isEmpty {
                    Text("ACTIONS")
                        .font(.custom("Inter-Bold", size: 12))
                        .foregroundColor(LisnColors.accent)
                        .tracking(2)
                        .padding(.bottom, 10)

                    VStack(spacing: 12) {
                        ForEach(Array(executableActions.enumerated()), id: \.element.id) { idx, action in
                            actionRow(action: action, index: idx)
                                .opacity(idx < showActions.count && showActions[idx] ? 1 : 0)
                                .offset(x: idx < showActions.count && showActions[idx] ? 0 : -10)
                        }
                    }
                }
            }
            .padding(28)
            .background(LisnColors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(
                color: LisnColors.accent.opacity(0.08),
                radius: 20,
                y: 8
            )
            .padding(.horizontal, 16)
            .opacity(showResults ? 1 : 0)
            .offset(y: showResults ? 0 : 40)
            // Celebration shimmer removed — the persistent border was visually
            // distracting. The checkmark + haptic on "Analysis Complete" is enough.

            if showScrollHint {
                Text("SCROLL TO CONTINUE")
                    .font(.custom("Inter-Medium", size: 11))
                    .foregroundColor(LisnColors.textTertiary)
                    .tracking(2)
                    .padding(.top, 20)
                    .padding(.bottom, 48)
                    .transition(.opacity)
            }
        }
        .padding(.top, 24)
        .transition(.opacity)
    }

    // MARK: - Action Row

    @ViewBuilder
    private func actionRow(action: DemoExecutableAction, index: Int) -> some View {
        let state = actionStates[action.id] ?? .idle

        HStack(spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 14))
                .foregroundColor(actionIconColor(for: state))
                .frame(width: 20)

            Text(action.text)
                .font(.custom("Inter-Medium", size: 13))
                .foregroundColor(LisnColors.textPrimary)

            Spacer()

            switch state {
            case .idle:
                Button {
                    executeAction(action)
                } label: {
                    Text("Execute")
                        .font(.custom("Inter-SemiBold", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [LisnColors.orbLight, LisnColors.accent],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        )
                        .shadow(color: LisnColors.accent.opacity(0.25), radius: 6)
                }
            case .loading:
                ProgressView()
                    .tint(LisnColors.accent)
                    .scaleEffect(0.8)
                    .frame(width: 60)
            case .success:
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text("Created!")
                        .font(.custom("Inter-Medium", size: 12))
                        .foregroundColor(.green)
                }
                .transition(.scale.combined(with: .opacity))
            case .failed(let msg):
                Button {
                    if msg.contains("permission") || msg.contains("denied") || msg.contains("access") {
                        openSettings()
                    } else {
                        executeAction(action)
                    }
                } label: {
                    Text(msg.contains("permission") || msg.contains("denied") || msg.contains("access") ? "Open Settings" : "Retry")
                        .font(.custom("Inter-SemiBold", size: 12))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.orange.opacity(0.8)))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func actionIconColor(for state: ActionState) -> Color {
        switch state {
        case .success: return .green
        case .failed: return .orange
        default: return LisnColors.accent
        }
    }

    // MARK: - Actions

    private func startRecording() {
        LisnHaptics.medium()
        recorder.startRecording()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if recorder.permissionDenied {
                AnalyticsService.shared.track(.onboardingDemoSkipped, properties: [
                    "reason": "mic_permission_denied"
                ])
                skipToResults()
            } else {
                withAnimation(.easeInOut(duration: 0.4)) {
                    phase = .recording
                }
            }
        }
    }

    private func stopRecording() {
        LisnHaptics.medium()
        recorder.stopRecording()

        // Cache what the user said during onboarding demo
        let transcript = recorder.liveTranscript
        if !transcript.isEmpty {
            UserDefaults.standard.set(transcript, forKey: "onboardingDemoTranscript")
            AnalyticsService.shared.track(.onboardingDemoRecorded, properties: [
                "transcript_length": transcript.count,
                "word_count": transcript.split(separator: " ").count,
            ])
        } else {
            AnalyticsService.shared.track(.onboardingDemoRecorded, properties: [
                "transcript_length": 0,
                "word_count": 0,
            ])
        }

        beginProcessing()
    }

    private func skipToResults() {
        AnalyticsService.shared.track(.onboardingDemoSkipped, properties: [
            "reason": "skipped_by_user"
        ])
        withAnimation(.easeInOut(duration: 0.4)) { phase = .processing }
        animateProcessing()
    }

    private func beginProcessing() {
        withAnimation(.easeInOut(duration: 0.4)) { phase = .processing }
        animateProcessing()
    }

    private func animateProcessing() {
        withAnimation(.easeIn(duration: 1.5)) { progress = 0.3 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.linear(duration: 2.5)) { progress = 0.7 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            withAnimation(.easeOut(duration: 2.0)) { progress = 1.0 }
        }

        for i in 0..<statusTexts.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 1.5) {
                LisnHaptics.light()
                withAnimation { statusIndex = i }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            withAnimation(.easeOut(duration: 0.3)) { statusOpacity = 0 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { revealResults() }
    }

    private func revealResults() {
        LisnHaptics.success()
        result = activeResult

        withAnimation(.easeInOut(duration: 0.4)) { phase = .results }

        withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.15)) {
            showResults = true
        }

        for i in 0..<activeResult.insights.count {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.5 + Double(i) * 0.15)) {
                if i < showInsights.count { showInsights[i] = true }
            }
        }

        let insightDelay = 0.5 + Double(activeResult.insights.count) * 0.15
        for i in 0..<executableActions.count {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(insightDelay + 0.2 + Double(i) * 0.15)) {
                if i < showActions.count { showActions[i] = true }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation { celebrate = true }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            withAnimation(.easeIn(duration: 0.4)) { showScrollHint = true }
        }
    }

    private func executeAction(_ action: DemoExecutableAction) {
        actionStates[action.id] = .loading

        Task {
            let pendingAction = action.toPendingAction()
            let result = await ActionExecutor.shared.executeAction(pendingAction)

            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if result.success {
                    actionStates[action.id] = .success
                    LisnHaptics.success()
                } else {
                    actionStates[action.id] = .failed(result.message)
                    LisnHaptics.error()
                }
            }

            if result.success && !showScrollHint {
                withAnimation(.easeIn(duration: 0.4)) { showScrollHint = true }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    struct Preview: View {
        @State private var result: DemoResult?
        var body: some View {
            OnboardingDemoScreen(domain: .sales, result: $result)
                .background(LisnColors.bgPrimary)
        }
    }
    return Preview()
}

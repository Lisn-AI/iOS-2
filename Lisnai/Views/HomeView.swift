import SwiftUI
import SwiftData
import MarkdownUI

/// Home view with recording controls and transcription display
struct HomeView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var subscriptionService: SubscriptionService
    @EnvironmentObject var authService: AuthService
    @Environment(\.modelContext) private var modelContext
    @Binding var showSettings: Bool
    @State private var showPaywall = false
    @State private var isRecording = false
    @State private var showPermissionAlert = false
    @State private var showMemorySearch = false
    @State private var showTodayBriefing = false
    @State private var pendingActionsCount = 0
    @State private var pendingSuggestionsCount = 0
    @State private var appeared = false
    @State private var dismissedResults = false
    @State private var showDiscardAlert = false
    @Query(sort: \Recording.createdAt, order: .reverse) private var recentRecordings: [Recording]

    /// Whether we have results to show
    private var hasResults: Bool {
        !recordingManager.transcription.isEmpty && !isRecording && !recordingManager.isProcessing && !dismissedResults
    }

    var body: some View {
        VStack(spacing: 0) {
            // Trial countdown banner
            if subscriptionService.isTrialActive && subscriptionService.trialDaysRemaining <= 7 {
                Button(action: { showPaywall = true }) {
                    HStack(spacing: LisnSpacing.xs) {
                        Image(systemName: "clock")
                            .font(.system(size: 13))
                        Text("\(subscriptionService.trialDaysRemaining) days left in your free trial")
                            .font(LisnFont.captionBold())
                        Spacer()
                        Text("Upgrade")
                            .font(LisnFont.captionBold())
                            .underline()
                    }
                    .foregroundStyle(LisnColors.accent)
                    .padding(.horizontal, LisnSpacing.lg)
                    .padding(.vertical, LisnSpacing.xs)
                    .background(LisnColors.accent.opacity(0.08))
                }
            }

            // Top bar
            topBar
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.top, LisnSpacing.sm)

            // Quick Actions Row
            quickActionsRow
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.top, LisnSpacing.md)

            if hasResults {
                resultsLayout
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                defaultLayout
                    .transition(.opacity)
            }
        }
        .padding(.bottom, 68)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: hasResults)
        .background(LisnColors.bgPrimary)
        .overlay {
            // Apple Intelligence-style edge glow when recording
            EdgeGlowEffect(
                isActive: isRecording && !recordingManager.isPaused,
                audioLevel: recordingManager.audioLevel
            )
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.6), value: isRecording)
        }
        .alert("Microphone Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please enable microphone access in Settings to record audio.")
        }
        .alert("Discard Recording?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                LisnHaptics.error()
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    recordingManager.discardRecording()
                    isRecording = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This recording will be permanently deleted.")
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowDiscardConfirmation"))) { _ in
            showDiscardAlert = true
        }
        .sheet(isPresented: $showMemorySearch) {
            MemorySearchView()
        }
        .sheet(isPresented: $showTodayBriefing) {
            BriefingsView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionService)
        }
        .onAppear {
            locationManager.requestPermissions()
            recordingManager.modelContext = modelContext
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appeared = true
            }
        }
        .task {
            await loadPendingCounts()
        }
    }

    // MARK: - Default Layout

    private var defaultLayout: some View {
        VStack(spacing: 0) {
            Spacer()

            // Hero: Recording Orb (standalone)
            RecordingOrb(
                isRecording: isRecording,
                audioLevel: recordingManager.audioLevel,
                isPaused: recordingManager.isPaused,
                isCallPaused: recordingManager.isPausedForCall,
                action: toggleRecording
            )
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.8)

            // Status Text
            statusLabel
                .padding(.top, LisnSpacing.lg)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)

            // Floating glass control bar (below status label during recording)
            if isRecording {
                floatingControlBar
                    .padding(.top, LisnSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()

            // Processing Status
            if recordingManager.isProcessing {
                processingView
                    .padding(.horizontal, LisnSpacing.lg)
                    .padding(.bottom, LisnSpacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRecording)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: recordingManager.isProcessing)
    }

    // MARK: - Results Layout

    private var resultsLayout: some View {
        VStack(spacing: 0) {
            // Swipe indicator
            Capsule()
                .fill(LisnColors.textTertiary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, LisnSpacing.sm)

            // Compact orb
            RecordingOrb(
                isRecording: isRecording,
                audioLevel: recordingManager.audioLevel,
                isPaused: recordingManager.isPaused,
                isCallPaused: recordingManager.isPausedForCall,
                action: toggleRecording
            )
            .scaleEffect(0.55)
            .frame(height: 72)
            .padding(.top, LisnSpacing.xxs)

            Text("Tap to record again")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)
                .padding(.bottom, LisnSpacing.md)

            // Scrollable results
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: LisnSpacing.md) {
                    TranscriptionCard(
                        transcription: recordingManager.transcription,
                        duration: recordingManager.recordingDuration
                    )

                    if !recordingManager.summary.isEmpty {
                        summaryCard
                    }

                    // Show insight card if the latest recording has one
                    if let latestInsight = recentRecordings.first?.insight {
                        InsightCard(insight: latestInsight)
                    }
                }
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.bottom, LisnSpacing.xxl)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 60)
                .onEnded { value in
                    // Swipe down to dismiss results
                    if value.translation.height > 80 {
                        LisnHaptics.light()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            dismissedResults = true
                        }
                    }
                }
        )
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(alignment: .center) {
            // Menu button (left)
            Button {
                LisnHaptics.light()
                showSettings = true
            } label: {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(LisnColors.textPrimary)
                    .frame(width: 42, height: 42)
                    .background(LisnColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }

            Spacer()

            // Greeting + date (center-right area)
            VStack(alignment: .trailing, spacing: LisnSpacing.xxxs) {
                Text(greetingText)
                    .font(LisnFont.titleSmall())
                    .foregroundColor(LisnColors.textPrimary)

                Text(todayDateString)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textTertiary)
            }
        }
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: LisnSpacing.sm) {
            // Search chip
            Button {
                LisnHaptics.light()
                showMemorySearch = true
            } label: {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Search")
                        .font(LisnFont.labelMedium())
                }
                .foregroundColor(LisnColors.textPrimary)
                .padding(.horizontal, LisnSpacing.md)
                .padding(.vertical, LisnSpacing.xs + 2)
                .background(LisnColors.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            // Briefing chip
            Button {
                LisnHaptics.light()
                showTodayBriefing = true
            } label: {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Briefing")
                        .font(LisnFont.labelMedium())
                }
                .foregroundColor(LisnColors.textPrimary)
                .padding(.horizontal, LisnSpacing.md)
                .padding(.vertical, LisnSpacing.xs + 2)
                .background(LisnColors.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)

            Spacer()

            // Pending Actions Badge — tap to open Actions tab
            if pendingActionsCount > 0 || pendingSuggestionsCount > 0 {
                Button {
                    NotificationCenter.default.post(name: .openActions, object: nil)
                } label: {
                    HStack(spacing: LisnSpacing.xxs) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("\(pendingActionsCount + pendingSuggestionsCount)")
                            .font(LisnFont.captionBold())
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, LisnSpacing.sm)
                    .padding(.vertical, LisnSpacing.xs)
                    .background(LisnColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Status Label

    private var statusLabel: some View {
        VStack(spacing: LisnSpacing.xs) {
            Text(statusText)
                .font(LisnFont.titleSmall())
                .foregroundColor(LisnColors.textPrimary)

            if isRecording {
                Text(recordingManager.recordingDuration)
                    .font(LisnFont.mono())
                    .foregroundColor(LisnColors.accent)
                    .contentTransition(.numericText())

                if recordingManager.isPausedManually {
                    Text("Tap to resume")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.accent)
                        .padding(.top, LisnSpacing.xxs)
                        .transition(.opacity)
                } else if recordingManager.isPausedForCall {
                    HStack(spacing: LisnSpacing.xxs) {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 11))
                        Text("Will resume when call ends")
                            .font(LisnFont.caption())
                    }
                    .foregroundColor(LisnColors.paused)
                    .padding(.top, LisnSpacing.xxs)
                    .transition(.opacity)
                }
            } else if !hasResults {
                Text("Tap the orb to begin")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textTertiary)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isRecording)
        .animation(.easeInOut(duration: 0.3), value: recordingManager.isPausedManually)
    }

    // MARK: - Floating Control Bar

    private var floatingControlBar: some View {
        HStack(spacing: LisnSpacing.md) {
            GlassButton(
                icon: "xmark",
                label: "Discard",
                isDestructive: true
            ) {
                showDiscardAlert = true
            }

            GlassButton(
                icon: recordingManager.isPausedManually ? "play.fill" : "pause.fill",
                label: recordingManager.isPausedManually ? "Resume" : "Pause"
            ) {
                if recordingManager.isPausedManually {
                    recordingManager.resumeRecording()
                } else {
                    recordingManager.pauseRecording()
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isRecording)
    }

    // MARK: - Processing View

    private var processingView: some View {
        HStack(spacing: LisnSpacing.md) {
            ZStack {
                Circle()
                    .fill(LisnColors.accent.opacity(0.1))
                    .frame(width: 40, height: 40)

                ProgressView()
                    .tint(LisnColors.accent)
            }

            VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
                Text("Processing")
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Text("Transcribing and summarizing...")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
            }

            Spacer()
        }
        .padding(LisnSpacing.md)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(
            color: LisnShadow.md.color,
            radius: LisnShadow.md.radius,
            x: LisnShadow.md.x,
            y: LisnShadow.md.y
        )
    }

    // MARK: - Summary Card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LisnColors.accent)

                Text("Summary")
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Spacer()

                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(LisnColors.success)
                    .font(.system(size: 14))
            }

            Markdown(recordingManager.summary)
                .markdownTheme(.lisnContent)
        }
        .padding(LisnSpacing.md)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(
            color: LisnShadow.sm.color,
            radius: LisnShadow.sm.radius,
            x: LisnShadow.sm.x,
            y: LisnShadow.sm.y
        )
    }

    // MARK: - Helpers

    private func loadPendingCounts() async {
        // Load actions (direct API — may fail if backend DB is down)
        do {
            let actionsResponse = try await APIService.shared.getPendingActions()
            pendingActionsCount = actionsResponse.actions.count
        } catch {
            print("[HomeView] Failed to load actions count: \(error.localizedDescription)")
            pendingActionsCount = 0
        }

        // Load suggestions (local-first, never throws user-visible errors)
        do {
            let suggestionsResponse = try await DataService.shared.getSuggestions(context: modelContext)
            pendingSuggestionsCount = suggestionsResponse.suggestions.count
        } catch {
            print("[HomeView] Failed to load suggestions count: \(error.localizedDescription)")
            pendingSuggestionsCount = 0
        }
    }

    private var statusText: String {
        if recordingManager.isPausedManually {
            return "Paused"
        } else if recordingManager.isPausedForCall {
            return "Paused for Call"
        } else if isRecording {
            return "Recording"
        } else {
            return "Ready"
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let firstName = authService.user?.displayName?.components(separatedBy: " ").first
        let name = (firstName?.isEmpty == true) ? nil : firstName
        let base: String
        if hour < 12 {
            base = "Good morning"
        } else if hour < 17 {
            base = "Good afternoon"
        } else {
            base = "Good evening"
        }
        if let name {
            return "\(base), \(name)"
        }
        return base
    }

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }

    // MARK: - Actions

    private func toggleRecording() {
        if isRecording {
            LisnHaptics.success()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                recordingManager.stopRecording()
                isRecording = false
            }
        } else {
            Task {
                let granted = await recordingManager.requestMicrophonePermission()
                if granted {
                    LisnHaptics.medium()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dismissedResults = false
                        recordingManager.startRecording()
                        isRecording = true
                    }
                } else {
                    showPermissionAlert = true
                }
            }
        }
    }
}

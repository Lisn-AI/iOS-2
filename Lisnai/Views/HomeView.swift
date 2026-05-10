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
    @State private var expandedRecordingId: UUID? // tracks which card is expanded
    @State private var sessionRecordingIds: [UUID] = [] // recordings made THIS app session
    @Query(sort: \Recording.createdAt, order: .reverse) private var recentRecordings: [Recording]

    /// Recordings made in this app session only (not from history)
    private var sessionRecordings: [Recording] {
        recentRecordings.filter { sessionRecordingIds.contains($0.id) }
    }

    /// Whether we have results to show (single recording result OR concurrent session recordings)
    private var hasResults: Bool {
        !recordingManager.transcription.isEmpty && !isRecording && !recordingManager.isProcessing && !dismissedResults
    }

    /// Whether to show stacked cards (multiple concurrent recordings in this session)
    private var showStackedCards: Bool {
        sessionRecordings.count > 1
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
        // Track recordings made in this session for stacked card display
        .onReceive(NotificationCenter.default.publisher(for: .recordingSaved)) { notification in
            if let idString = notification.userInfo?["recordingId"] as? String,
               let id = UUID(uuidString: idString) {
                sessionRecordingIds.append(id)
            }
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

    @State private var pullOffset: CGFloat = 0
    private let dismissThreshold: CGFloat = 120

    private var resultsLayout: some View {
        VStack(spacing: 0) {
            // Pull-to-dismiss handle — wide touch target
            VStack(spacing: LisnSpacing.xs) {
                Capsule()
                    .fill(LisnColors.textTertiary.opacity(0.4))
                    .frame(width: 40, height: 5)

                Text("Pull down to dismiss")
                    .font(.system(size: 10))
                    .foregroundColor(LisnColors.textTertiary.opacity(pullOffset > 20 ? 1 : 0))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            pullOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > dismissThreshold {
                            LisnHaptics.light()
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                dismissedResults = true
                            }
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            pullOffset = 0
                        }
                    }
            )
            .padding(.top, LisnSpacing.xs)

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

            // Processing pill (shows when recordings are being processed in background)
            if recordingManager.isProcessing || recordingManager.backgroundProcessingCount > 0 {
                processingPill
                    .padding(.horizontal, LisnSpacing.lg)
                    .padding(.bottom, LisnSpacing.sm)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Scrollable results
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: LisnSpacing.md) {
                    if showStackedCards {
                        // Multiple concurrent recordings — show stacked cards
                        ForEach(sessionRecordings) { recording in
                            let isExpanded = expandedRecordingId == recording.id || (expandedRecordingId == nil && recording.id == sessionRecordings.first?.id)

                            recordingCard(recording: recording, isExpanded: isExpanded)
                                .onTapGesture {
                                    guard !isExpanded else { return }
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        expandedRecordingId = recording.id
                                    }
                                    LisnHaptics.light()
                                }
                        }
                    } else {
                        // Single recording — show classic layout (transcript + summary + insight)
                        TranscriptionCard(
                            transcription: recordingManager.transcription,
                            duration: recordingManager.recordingDuration
                        )

                        if !recordingManager.summary.isEmpty {
                            summaryCard
                        }

                        if let latestInsight = recentRecordings.first?.insight {
                            InsightCard(insight: latestInsight)
                        }
                    }
                }
                .padding(.horizontal, LisnSpacing.lg)
                .padding(.bottom, LisnSpacing.xxl)
            }
        }
        .offset(y: pullOffset * 0.3) // Rubber-band effect while pulling
    }

    // MARK: - Recording Card (expanded/collapsed)

    @ViewBuilder
    private func recordingCard(recording: Recording, isExpanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: isExpanded ? LisnSpacing.md : 0) {
            // Header (always visible)
            HStack(spacing: LisnSpacing.sm) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(LisnColors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.title ?? "Recording at \(recording.date.formatted(date: .omitted, time: .shortened))")
                        .font(LisnFont.labelLarge())
                        .foregroundColor(LisnColors.textPrimary)
                        .lineLimit(isExpanded ? nil : 1)

                    HStack(spacing: LisnSpacing.xs) {
                        Text(formatDuration(recording.duration))
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textTertiary)

                        if recording.title == nil {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                Text("Processing...")
                                    .font(LisnFont.caption())
                                    .foregroundColor(LisnColors.accent)
                            }
                        }
                    }
                }

                Spacer()

                if !isExpanded {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(LisnColors.textTertiary)
                }
            }

            // Expanded content
            if isExpanded {
                if let transcript = recording.transcription?.text, !transcript.isEmpty {
                    TranscriptionCard(transcription: transcript, duration: formatDuration(recording.duration))
                }

                if let summaryText = recording.summary?.text, !summaryText.isEmpty {
                    VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                        HStack(spacing: LisnSpacing.xs) {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(LisnColors.accent)
                            Text("Summary")
                                .font(LisnFont.labelLarge())
                                .foregroundColor(LisnColors.textPrimary)
                        }
                        Markdown(summaryText)
                            .markdownTheme(.lisnContent)
                    }
                    .padding(LisnSpacing.md)
                    .background(LisnColors.bgElevated)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
                }

                if let insight = recording.insight {
                    InsightCard(insight: insight)
                }
            }
        }
        .padding(isExpanded ? LisnSpacing.md : LisnSpacing.sm)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(
            color: isExpanded ? LisnShadow.md.color : LisnShadow.sm.color,
            radius: isExpanded ? LisnShadow.md.radius : LisnShadow.sm.radius,
            x: 0, y: isExpanded ? LisnShadow.md.y : LisnShadow.sm.y
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isExpanded)
    }

    // MARK: - Processing Pill

    private var processingPill: some View {
        let count = recordingManager.backgroundProcessingCount
        return HStack(spacing: LisnSpacing.xs) {
            ProgressView()
                .scaleEffect(0.7)
            Text(count > 1 ? "\(count) recordings processing..." : "Processing recording...")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textSecondary)
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, LisnSpacing.xs)
        .background(LisnColors.accent.opacity(0.08))
        .clipShape(Capsule())
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
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

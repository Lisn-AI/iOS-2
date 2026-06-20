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
    @State private var showAIConsent = false
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
    @State private var scrollOffset: CGFloat = 0 // drives collapsing hero
    @Query(sort: \Recording.createdAt, order: .reverse) private var recentRecordings: [Recording]

    /// Recordings made in this app session only (not from history)
    private var sessionRecordings: [Recording] {
        recentRecordings.filter { sessionRecordingIds.contains($0.id) }
    }

    /// Whether we have results to show
    private var hasResults: Bool {
        guard !isRecording && !dismissedResults else { return false }
        // Show results if: session has recordings OR there's an active transcript OR background sessions exist
        return !sessionRecordings.isEmpty
            || !recordingManager.transcription.isEmpty
            || recordingManager.backgroundProcessingCount > 0
    }

    /// Whether to show stacked cards (multiple recordings in this session)
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
        .sheet(isPresented: $showAIConsent) {
            AIConsentView {
                recordingManager.startRecording()
            }
            .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAIConsent)) { _ in
            showAIConsent = true
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

    /// Progress 0...1 mapping scroll offset over the hero height — drives hero collapse.
    /// Threshold matches the expanded hero region so it fully disappears as the user
    /// scrolls past it.
    private var heroProgress: CGFloat {
        let threshold: CGFloat = 140
        return min(max(scrollOffset / threshold, 0), 1)
    }

    private var resultsLayout: some View {
        VStack(spacing: 0) {
            // Pull-to-dismiss handle — wide touch target, stays outside scroll
            pullToDismissHandle
                .padding(.top, LisnSpacing.xs)

            // Processing pill stays above the scroll for visibility
            if recordingManager.isProcessing || recordingManager.backgroundProcessingCount > 0 {
                processingPill
                    .padding(.horizontal, LisnSpacing.lg)
                    .padding(.bottom, LisnSpacing.xs)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Scrollable area — hero is INSIDE the scroll so it scrolls away naturally,
            // with extra scale/opacity for a Spotify-style parallax-collapse feel.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Invisible scroll-offset tracker — first child of scroll content
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: HomeScrollOffsetKey.self,
                            value: -geo.frame(in: .named("homeScroll")).minY
                        )
                    }
                    .frame(height: 0)

                    // Collapsing hero — scrolls away with content
                    collapsingHero

                    VStack(spacing: LisnSpacing.md) {
                        if showStackedCards {
                            // Multiple concurrent recordings queued up — stacked header cards,
                            // one expanded with its section cards beneath.
                            ForEach(sessionRecordings) { recording in
                                let isExpanded = expandedRecordingId == recording.id || (expandedRecordingId == nil && recording.id == sessionRecordings.first?.id)

                                recordingGroup(recording: recording, isExpanded: isExpanded)
                            }
                        } else if let recording = sessionRecordings.first {
                            // Single session recording — show from SwiftData
                            recordingGroup(recording: recording, isExpanded: true)
                        } else if !recordingManager.transcription.isEmpty {
                            // Fallback: show from recordingManager (still processing, not yet in SwiftData)
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
                        } else if recordingManager.backgroundProcessingCount > 0 {
                            // Background sessions processing but nothing in SwiftData yet
                            VStack(spacing: LisnSpacing.sm) {
                                ProgressView()
                                Text("Processing your recording...")
                                    .font(LisnFont.bodyMedium())
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LisnSpacing.xxl)
                        }
                    }
                    .padding(.horizontal, LisnSpacing.sm) // 12pt — near-edge with breathing room
                    .padding(.bottom, LisnSpacing.xxl)
                }
            }
            .coordinateSpace(name: "homeScroll")
            .onPreferenceChange(HomeScrollOffsetKey.self) { newOffset in
                scrollOffset = max(0, newOffset)
            }
        }
        .offset(y: pullOffset * 0.3) // Rubber-band effect while pulling
    }

    // MARK: - Collapsing Hero
    //
    // Sits as the first item inside the ScrollView so it scrolls away naturally.
    // Additionally scales/fades based on scroll progress for a parallax-collapse feel.
    // Fully disappears (scale 0, opacity 0, height 0) once the user has scrolled past
    // the hero region — content takes over the entire screen.

    private var collapsingHero: some View {
        let orbScale = max(0, 0.55 * (1 - heroProgress))       // 0.55 → 0
        let containerHeight = max(0, 100 * (1 - heroProgress)) // 100 → 0
        let captionOpacity = max(0, 1 - heroProgress * 2.2)    // fades faster than orb

        return VStack(spacing: 0) {
            RecordingOrb(
                isRecording: isRecording,
                audioLevel: recordingManager.audioLevel,
                isPaused: recordingManager.isPaused,
                isCallPaused: recordingManager.isPausedForCall,
                action: toggleRecording
            )
            .scaleEffect(orbScale, anchor: .center)
            .opacity(1 - heroProgress)
            .frame(height: containerHeight)
            .allowsHitTesting(heroProgress < 0.5)

            Text("Tap to record again")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)
                .opacity(captionOpacity)
                .frame(height: max(0, 20 * (1 - heroProgress)))
        }
        .clipped()
        .padding(.top, max(0, LisnSpacing.xxs * (1 - heroProgress)))
        .padding(.bottom, max(0, LisnSpacing.md * (1 - heroProgress)))
    }

    private var pullToDismissHandle: some View {
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
    }

    // MARK: - Recording Group (header + section cards)
    //
    // Each recording renders as a vertical group of glass cards:
    //   - Header card (always shown) — icon, title, meta, processing badge
    //   - Transcript card (when expanded, transcript exists)
    //   - Summary card (when expanded, summary exists)
    //   - Insight card (when expanded, insight exists)
    //
    // Multiple concurrent recordings queue up as stacked header cards; tapping
    // a collapsed header expands that recording (and collapses the previously
    // expanded one).

    @ViewBuilder
    private func recordingGroup(recording: Recording, isExpanded: Bool) -> some View {
        VStack(spacing: LisnSpacing.sm) {
            recordingHeaderCard(recording: recording, isExpanded: isExpanded)
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        expandedRecordingId = isExpanded ? nil : recording.id
                    }
                    LisnHaptics.light()
                }

            if isExpanded {
                if let transcript = recording.transcription?.text, !transcript.isEmpty {
                    transcriptSectionCard(transcript: transcript, duration: recording.duration)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let summaryText = recording.summary?.text, !summaryText.isEmpty {
                    summarySectionCard(summary: summaryText)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                if let insight = recording.insight {
                    insightSectionCard(insight: insight)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isExpanded)
    }

    // MARK: - Section Cards (glass surfaces)

    @ViewBuilder
    private func recordingHeaderCard(recording: Recording, isExpanded: Bool) -> some View {
        HStack(spacing: LisnSpacing.sm) {
            // Animated Lottie icon or fallback
            RecordingIconView(recording: recording, size: 38)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title ?? "Recording at \(recording.date.formatted(date: .omitted, time: .shortened))")
                    .font(LisnFont.titleSmall())
                    .foregroundColor(LisnColors.textPrimary)
                    .lineLimit(isExpanded ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: LisnSpacing.xs) {
                    Text(formatDuration(recording.duration))
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)

                    Text("\u{2022}")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)

                    Text(recording.date.formatted(date: .omitted, time: .shortened))
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)

                    if recording.title == nil {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.55)
                            Text("Processing")
                                .font(LisnFont.caption())
                                .foregroundColor(LisnColors.accent)
                        }
                    }
                }
            }

            Spacer()

            // Chevron in circular touch target, rotates when expanded
            ZStack {
                Circle()
                    .fill(LisnColors.bgSecondary.opacity(0.6))
                    .frame(width: 26, height: 26)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(LisnColors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(LisnSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisnGlassSurface(cornerRadius: LisnRadius.xl)
    }

    @ViewBuilder
    private func transcriptSectionCard(transcript: String, duration: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            sectionHeader(icon: "text.quote", title: "Transcript", accessory: formatDuration(duration))

            FormattedTranscriptionView(text: transcript)
        }
        .padding(LisnSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisnGlassSurface(cornerRadius: LisnRadius.xl)
    }

    @ViewBuilder
    private func summarySectionCard(summary: String) -> some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            sectionHeader(icon: "sparkles", title: "Summary")

            Markdown(summary.lisnNormalizedMarkdown)
                .markdownTheme(.lisnContent)
        }
        .padding(LisnSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lisnGlassSurface(cornerRadius: LisnRadius.xl)
    }

    @ViewBuilder
    private func insightSectionCard(insight: Insight) -> some View {
        InsightCard(insight: insight)
    }

    @ViewBuilder
    private func sectionHeader(icon: String, title: String, accessory: String? = nil) -> some View {
        HStack(spacing: LisnSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(LisnColors.accent)

            Text(title)
                .font(LisnFont.labelLarge())
                .foregroundColor(LisnColors.textPrimary)

            Spacer()

            if let accessory {
                Text(accessory)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textTertiary)
            }
        }
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

    // Original processing view (kept for fallback)
    // private var processingViewOriginal: some View {
    //     HStack(spacing: LisnSpacing.md) {
    //         ZStack {
    //             Circle()
    //                 .fill(LisnColors.accent.opacity(0.1))
    //                 .frame(width: 40, height: 40)
    //             ProgressView()
    //                 .tint(LisnColors.accent)
    //         }
    //         VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
    //             Text("Processing")
    //                 .font(LisnFont.labelLarge())
    //                 .foregroundColor(LisnColors.textPrimary)
    //             Text("Transcribing and summarizing...")
    //                 .font(LisnFont.caption())
    //                 .foregroundColor(LisnColors.textSecondary)
    //         }
    //         Spacer()
    //     }
    //     .padding(LisnSpacing.md)
    //     .background(LisnColors.bgElevated)
    //     .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
    //     .shadow(color: LisnShadow.md.color, radius: LisnShadow.md.radius, x: LisnShadow.md.x, y: LisnShadow.md.y)
    // }

    private var processingView: some View {
        ProcessingAnimationCard()
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

            Markdown(recordingManager.summary.lisnNormalizedMarkdown)
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

// MARK: - Scroll Offset Tracking

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

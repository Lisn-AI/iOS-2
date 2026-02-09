import SwiftUI
import SwiftData

/// Home view with recording controls
struct HomeView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @Binding var showSettings: Bool
    @State private var isRecording = false
    @State private var showPermissionAlert = false
    @State private var showMemorySearch = false
    @State private var showTodayBriefing = false
    @State private var pendingActionsCount = 0
    @State private var pendingSuggestionsCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Custom top bar
            topBar
                .padding(.horizontal, LisnSpacing.md)
                .padding(.top, LisnSpacing.sm)

            // Quick Actions Row
            quickActionsRow
                .padding(.horizontal, LisnSpacing.md)
                .padding(.top, LisnSpacing.md)

            Spacer()

            // Hero: Recording Orb
            RecordingOrb(
                isRecording: isRecording,
                audioLevel: recordingManager.audioLevel,
                isPaused: recordingManager.isPausedForCall,
                action: toggleRecording
            )

            // Status Text (below orb)
            statusLabel
                .padding(.top, LisnSpacing.lg)

            Spacer()

            // Processing Status
            if recordingManager.isProcessing {
                processingView
                    .padding(.horizontal, LisnSpacing.md)
                    .padding(.bottom, LisnSpacing.lg)
            }

            // Recent Result Preview
            if !recordingManager.summary.isEmpty && !recordingManager.isProcessing {
                recentResultPreview
                    .padding(.horizontal, LisnSpacing.md)
                    .padding(.bottom, LisnSpacing.lg)
            }

            // Bottom Stats
            bottomStats
                .padding(.horizontal, LisnSpacing.md)
                .padding(.bottom, LisnSpacing.md)
        }
        .background(LisnColors.bgPrimary)
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
        .sheet(isPresented: $showMemorySearch) {
            MemorySearchView()
        }
        .sheet(isPresented: $showTodayBriefing) {
            BriefingsView()
        }
        .onAppear {
            locationManager.requestPermissions()
            recordingManager.modelContext = modelContext
        }
        .task {
            await loadPendingCounts()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        ZStack {
            // Centered logo
            Text("Lisnai")
                .font(LisnFont.titleLarge())
                .fontWeight(.bold)
                .foregroundColor(LisnColors.textPrimary)

            // Menu button pinned left
            HStack {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(LisnColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(LisnColors.bgSecondary)
                        .clipShape(Circle())
                }

                Spacer()
            }
        }
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: LisnSpacing.sm) {
            LisnChip(
                text: "Search",
                icon: "magnifyingglass",
                color: LisnColors.accent,
                action: { showMemorySearch = true }
            )

            LisnChip(
                text: "Briefing",
                icon: "sun.haze",
                color: LisnColors.accent,
                action: { showTodayBriefing = true }
            )

            Spacer()

            // Pending Actions Badge
            if pendingActionsCount > 0 || pendingSuggestionsCount > 0 {
                HStack(spacing: LisnSpacing.xxs) {
                    Image(systemName: "bolt")
                        .font(LisnFont.caption())
                    Text("\(pendingActionsCount + pendingSuggestionsCount)")
                        .font(LisnFont.captionBold())
                }
                .foregroundColor(.white)
                .padding(.horizontal, LisnSpacing.xs + 2)
                .padding(.vertical, LisnSpacing.xxs + 2)
                .background(LisnColors.error)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
        }
    }

    // MARK: - Status Label

    private var statusLabel: some View {
        VStack(spacing: LisnSpacing.xxs) {
            Text(statusText)
                .font(LisnFont.titleSmall())
                .foregroundColor(LisnColors.textPrimary)

            if isRecording {
                Text(recordingManager.recordingDuration)
                    .font(LisnFont.mono())
                    .foregroundColor(LisnColors.textSecondary)

                if recordingManager.isPausedForCall {
                    Text("Will resume when call ends")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.paused)
                        .padding(.top, LisnSpacing.xxs)
                }
            }
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        GlassCard {
            HStack(spacing: LisnSpacing.sm) {
                ProgressView()
                    .tint(LisnColors.accent)

                VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
                    Text("Processing recording...")
                        .font(LisnFont.labelLarge())
                        .foregroundColor(LisnColors.textPrimary)

                    Text("Transcribing and generating summary")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Recent Result Preview

    private var recentResultPreview: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(LisnColors.success)
                    Text("Recording saved")
                        .font(LisnFont.labelLarge())
                        .foregroundColor(LisnColors.textPrimary)
                    Spacer()
                }

                Text(recordingManager.summary)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - Bottom Stats

    private var bottomStats: some View {
        HStack(spacing: LisnSpacing.lg) {
            if pendingActionsCount > 0 {
                Label("\(pendingActionsCount) actions", systemImage: "bolt")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
            }

            if pendingSuggestionsCount > 0 {
                Label("\(pendingSuggestionsCount) suggestions", systemImage: "lightbulb")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
            }

            if pendingActionsCount == 0 && pendingSuggestionsCount == 0 {
                Label("All caught up!", systemImage: "checkmark.circle")
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.success)
            }
        }
    }

    // MARK: - Helpers

    private func loadPendingCounts() async {
        do {
            async let actionsTask = APIService.shared.getPendingActions()
            async let suggestionsTask = APIService.shared.getSuggestions(status: "pending")

            let (actionsResponse, suggestionsResponse) = try await (actionsTask, suggestionsTask)
            pendingActionsCount = actionsResponse.actions.count
            pendingSuggestionsCount = suggestionsResponse.suggestions.count
        } catch {
            print("Failed to load pending counts: \(error)")
        }
    }

    // MARK: - Computed Properties

    private var statusText: String {
        if recordingManager.isPausedForCall {
            return "Paused for Call"
        } else if isRecording {
            return "Recording..."
        } else {
            return "Ready to Record"
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if isRecording {
            LisnHaptics.success()
            recordingManager.stopRecording()
            isRecording = false
        } else {
            Task {
                let granted = await recordingManager.requestMicrophonePermission()
                if granted {
                    LisnHaptics.medium()
                    recordingManager.startRecording()
                    isRecording = true
                } else {
                    showPermissionAlert = true
                }
            }
        }
    }
}

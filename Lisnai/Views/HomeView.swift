import SwiftUI
import SwiftData

/// Home view with recording controls
struct HomeView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @State private var isRecording = false
    @State private var showPermissionAlert = false
    @State private var showMemorySearch = false
    @State private var showTodayBriefing = false
    @State private var pendingActionsCount = 0
    @State private var pendingSuggestionsCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Quick Actions Row
            quickActionsRow
                .padding(.horizontal)
                .padding(.top, 8)

            // Status Card
            statusCard
                .padding()

            Spacer()

            // Recording Button
            recordingButton
                .padding(.bottom, 40)

            // Processing Status
            if recordingManager.isProcessing {
                processingView
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }

            // Recent Result Preview
            if !recordingManager.summary.isEmpty && !recordingManager.isProcessing {
                recentResultPreview
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }

            Spacer()

            // Bottom Stats
            bottomStats
                .padding(.horizontal)
                .padding(.bottom, 16)
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
        .sheet(isPresented: $showMemorySearch) {
            MemorySearchView()
        }
        .sheet(isPresented: $showTodayBriefing) {
            BriefingsView()
        }
        .onAppear {
            locationManager.requestPermissions()
            // Pass modelContext to RecordingManager for SwiftData persistence
            recordingManager.modelContext = modelContext
        }
        .task {
            await loadPendingCounts()
        }
    }

    // MARK: - Quick Actions Row

    private var quickActionsRow: some View {
        HStack(spacing: 12) {
            // Search Button
            Button(action: { showMemorySearch = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text("Search")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            }

            // Today's Briefing Button
            Button(action: { showTodayBriefing = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "sun.haze")
                    Text("Briefing")
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(20)
            }

            Spacer()

            // Pending Actions Badge
            if pendingActionsCount > 0 || pendingSuggestionsCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                    Text("\(pendingActionsCount + pendingSuggestionsCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Bottom Stats

    private var bottomStats: some View {
        HStack(spacing: 20) {
            if pendingActionsCount > 0 {
                Label("\(pendingActionsCount) actions", systemImage: "bolt.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if pendingSuggestionsCount > 0 {
                Label("\(pendingSuggestionsCount) suggestions", systemImage: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if pendingActionsCount == 0 && pendingSuggestionsCount == 0 {
                Label("All caught up!", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private func loadPendingCounts() async {
        do {
            async let actionsTask = APIService.shared.getPendingActions()
            async let suggestionsTask = APIService.shared.getSuggestions(status: "pending")

            let (actionsResponse, suggestionsResponse) = try await (actionsTask, suggestionsTask)
            pendingActionsCount = actionsResponse.actions.count
            pendingSuggestionsCount = suggestionsResponse.suggestions.count
        } catch {
            // Silently fail - not critical
            print("Failed to load pending counts: \(error)")
        }
    }

    // MARK: - Subviews

    private var statusCard: some View {
        VStack(spacing: 16) {
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 100, height: 100)

                Circle()
                    .fill(statusColor)
                    .frame(width: 80, height: 80)

                Image(systemName: statusIcon)
                    .font(.system(size: 35))
                    .foregroundColor(.white)
            }

            // Status Text
            VStack(spacing: 4) {
                Text(statusText)
                    .font(.title2)
                    .fontWeight(.semibold)

                if isRecording {
                    Text(recordingManager.recordingDuration)
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.secondary)

                    if recordingManager.isPausedForCall {
                        Text("Will resume when call ends")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color(.systemGray6))
        .cornerRadius(20)
    }

    private var recordingButton: some View {
        Button(action: toggleRecording) {
            HStack(spacing: 12) {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.title2)

                Text(isRecording ? "Stop Recording" : "Start Recording")
                    .font(.headline)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .background(isRecording ? Color.red : Color.blue)
            .cornerRadius(16)
        }
        .padding(.horizontal, 30)
        .shadow(color: (isRecording ? Color.red : Color.blue).opacity(0.3), radius: 10, y: 5)
    }

    private var processingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Processing recording...")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("Transcribing and generating summary")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }

    private var recentResultPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Recording saved")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            Text(recordingManager.summary)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Computed Properties

    private var statusColor: Color {
        if recordingManager.isPausedForCall {
            return .orange
        } else if isRecording {
            return .red
        } else {
            return .gray
        }
    }

    private var statusIcon: String {
        if recordingManager.isPausedForCall {
            return "phone.fill"
        } else if isRecording {
            return "waveform"
        } else {
            return "mic.slash.fill"
        }
    }

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
            recordingManager.stopRecording()
            isRecording = false

            // Save to SwiftData after processing completes
            // This will be handled in RecordingManager
        } else {
            Task {
                let granted = await recordingManager.requestMicrophonePermission()
                if granted {
                    recordingManager.startRecording()
                    isRecording = true
                } else {
                    showPermissionAlert = true
                }
            }
        }
    }
}

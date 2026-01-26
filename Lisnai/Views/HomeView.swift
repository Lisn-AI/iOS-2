import SwiftUI
import SwiftData

/// Home view with recording controls
struct HomeView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @Environment(\.modelContext) private var modelContext
    @State private var isRecording = false
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
            }
            .navigationTitle("Lisnai")
            .navigationBarTitleDisplayMode(.large)
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
            .onAppear {
                locationManager.requestPermissions()
                // Pass modelContext to RecordingManager for SwiftData persistence
                recordingManager.modelContext = modelContext
            }
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

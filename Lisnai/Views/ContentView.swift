import SwiftUI

struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var isRecording = false
    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Recording Status
                VStack(spacing: 12) {
                    Circle()
                        .fill(recordingManager.isPausedForCall ? Color.orange : (isRecording ? Color.red : Color.gray))
                        .frame(width: 80, height: 80)
                        .overlay(
                            Image(systemName: recordingManager.isPausedForCall ? "phone.fill" : (isRecording ? "mic.fill" : "mic.slash.fill"))
                                .font(.system(size: 35))
                                .foregroundColor(.white)
                        )

                    Text(recordingManager.isPausedForCall ? "Paused for Call" : (isRecording ? "Recording..." : "Not Recording"))
                        .font(.title2)
                        .fontWeight(.semibold)

                    if isRecording {
                        Text(recordingManager.recordingDuration)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if recordingManager.isPausedForCall {
                            Text("Will resume when call ends")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.top, 60)

                Spacer()

                // Main Action Button
                Button(action: {
                    toggleRecording()
                }) {
                    Text(isRecording ? "Stop Recording" : "Start Recording Your Day")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(isRecording ? Color.red : Color.blue)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 30)

                // Transcription and Summary Results
                if recordingManager.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Transcribing & identifying speakers...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(20)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .padding(.horizontal, 30)
                }

                if !recordingManager.transcription.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Summary
                            if !recordingManager.summary.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Summary")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text(recordingManager.summary)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }

                            // Transcription with Speaker Labels
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Transcription")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    Image(systemName: "person.2.fill")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }

                                Text(recordingManager.transcription)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal, 30)
                    }
                    .frame(maxHeight: 300)
                }

                Spacer()
            }
            .navigationTitle("Lisnai")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {}) {
                        Image(systemName: "gear")
                    }
                }
            }
            .alert("Microphone Permission Required", isPresented: $showPermissionAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enable microphone access in Settings to record audio.")
            }
            .onAppear {
                // Request location permissions when view appears
                locationManager.requestPermissions()
            }
        }
    }

    private func toggleRecording() {
        if isRecording {
            recordingManager.stopRecording()
            isRecording = false
        } else {
            // Request permission and start recording
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

#Preview {
    ContentView()
        .environmentObject(RecordingManager())
        .environmentObject(LocationManager())
}

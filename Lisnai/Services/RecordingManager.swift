import Foundation
import AVFoundation
import Speech

@MainActor
class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration = "00:00:00"
    @Published var transcription = ""
    @Published var summary = ""
    @Published var isProcessing = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingSession: AVAudioSession?
    private var recordingStartTime: Date?
    private var durationTimer: Timer?
    private var isAudioSessionSetup = false
    private var lastRecordingURL: URL?

    // Services
    // FluidAudio (on-device, free, but less accurate on short phrases)
    private let transcriptionService = TranscriptionService()
    private let diarizationService = DiarizationService()

    // Deepgram (cloud API, costs money, but better accuracy)
    private let deepgramService = DeepgramService()

    private let summarizationService = SummarizationService()

    // Toggle between FluidAudio and Deepgram
    private let useDeepgram = true

    override init() {
        super.init()
        // Audio session setup moved to lazy initialization (Apple best practice)
        // This avoids blocking operations during app launch
    }

    private func setupAudioSessionIfNeeded() throws {
        // Only setup once
        guard !isAudioSessionSetup else { return }

        recordingSession = AVAudioSession.sharedInstance()

        // iOS 26: Use new bluetoothHighQualityRecording for AirPods
        if #available(iOS 26.0, *) {
            try recordingSession?.setCategory(.record, mode: .default, options: [.bluetoothHighQualityRecording])
        } else {
            try recordingSession?.setCategory(.record, mode: .default)
        }

        try recordingSession?.setActive(true)

        isAudioSessionSetup = true
        print("Audio session setup complete")
    }

    func requestMicrophonePermission() async -> Bool {
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    func startRecording() {
        // Setup audio session before first recording
        do {
            try setupAudioSessionIfNeeded()
        } catch {
            print("Failed to setup audio session: \(error.localizedDescription)")
            return
        }
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")

        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()

            isRecording = true
            recordingStartTime = Date()
            startDurationTimer()

            print("Recording started: \(audioFilename.lastPathComponent)")
        } catch {
            print("Could not start recording: \(error.localizedDescription)")
        }
    }

    func stopRecording() {
        // Save the recording URL before stopping
        lastRecordingURL = audioRecorder?.url

        audioRecorder?.stop()
        audioRecorder = nil

        isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil

        print("Recording stopped")

        // Start transcription and summarization
        if let recordingURL = lastRecordingURL {
            Task {
                await processRecording(fileURL: recordingURL)
            }
        }
    }

    private func processRecording(fileURL: URL) async {
        isProcessing = true
        transcription = "Transcribing and identifying speakers..."
        summary = ""

        do {
            let labeledTranscript: String

            if useDeepgram {
                // Use Deepgram (transcription + diarization in one API call)
                print("Using Deepgram API...")
                let (fullTranscript, segments) = try await deepgramService.transcribeAndDiarize(fileURL: fileURL)

                // Format with speaker labels
                labeledTranscript = formatDeepgramTranscript(segments: segments)

                print("Deepgram complete: \(segments.count) segments, \(Set(segments.map(\.speaker)).count) speakers")

            } else {
                // Use FluidAudio (on-device, free)
                print("Using FluidAudio (on-device)...")

                // Step 1: Transcribe audio to text (Apple SpeechAnalyzer)
                print("Starting transcription...")
                let transcribedText = try await transcriptionService.transcribe(fileURL: fileURL)

                print("Transcription complete: \(transcribedText.count) characters")

                // Step 2: Identify speakers (FluidAudio)
                print("Starting speaker diarization...")
                let speakerSegments = try await diarizationService.diarize(fileURL: fileURL)

                print("Diarization complete: \(speakerSegments.count) segments, \(Set(speakerSegments.map(\.speaker)).count) speakers detected")

                // Step 3: Combine transcript with speaker labels
                labeledTranscript = createLabeledTranscript(text: transcribedText, segments: speakerSegments)
            }

            transcription = labeledTranscript

            // Step 4: Summarize with speaker context
            if !labeledTranscript.isEmpty {
                print("Starting summarization...")
                let summaryText = try await summarizationService.summarize(labeledTranscript)
                summary = summaryText

                print("Summary complete!")
            }

        } catch {
            print("Processing error: \(error.localizedDescription)")
            transcription = "Error: \(error.localizedDescription)"
            summary = ""
        }

        isProcessing = false
    }

    /// Format Deepgram segments into labeled transcript
    private func formatDeepgramTranscript(segments: [DeepgramService.SpeakerSegment]) -> String {
        var result = ""

        for (index, segment) in segments.enumerated() {
            if index > 0 {
                result += "\n\n"
            }

            result += "[Speaker \(segment.speaker + 1)] (\(formatTime(segment.startTime)) - \(formatTime(segment.endTime))):\n"
            result += segment.transcript
        }

        return result
    }

    /// Combine plain transcript with speaker segments to create labeled output (FluidAudio)
    private func createLabeledTranscript(text: String, segments: [DiarizationService.SpeakerSegment]) -> String {
        guard !segments.isEmpty else {
            return text
        }

        // Calculate total duration
        let totalDuration = segments.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
        guard totalDuration > 0 else { return text }

        // Split text into words
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }

        var result = ""
        var wordIndex = 0

        // Distribute words across speaker segments based on duration
        for (index, segment) in segments.enumerated() {
            // Calculate how many words belong to this segment
            let segmentDuration = segment.endTime - segment.startTime
            let segmentRatio = segmentDuration / totalDuration
            let wordsInSegment = index == segments.count - 1
                ? words.count - wordIndex  // Last segment gets remaining words
                : Int(round(Double(words.count) * segmentRatio))

            // Skip empty segments
            guard wordsInSegment > 0 else { continue }

            // Add speaker label
            if index > 0 {
                result += "\n\n"
            }
            result += "[Speaker \(segment.speaker + 1)] (\(formatTime(segment.startTime)) - \(formatTime(segment.endTime))):\n"

            // Add words for this segment
            let endIndex = min(wordIndex + wordsInSegment, words.count)
            let segmentText = words[wordIndex..<endIndex].joined(separator: " ")
            result += segmentText

            wordIndex = endIndex
        }

        return result
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                let duration = Date().timeIntervalSince(startTime)
                self.updateDurationDisplay(duration: duration)
            }
        }
    }

    private func updateDurationDisplay(duration: TimeInterval) {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        recordingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // TODO: Implement iOS 26 SpeechAnalyzer transcription
    // private func transcribeRecording() {
    //     // Use SpeechAnalyzer + SpeechTranscriber
    // }
}

// MARK: - AVAudioRecorderDelegate
extension RecordingManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if flag {
                print("Recording finished successfully")
            } else {
                print("Recording failed")
            }
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            print("Encoding error: \(error?.localizedDescription ?? "Unknown error")")
        }
    }
}

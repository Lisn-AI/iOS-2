import AVFoundation
import Speech

/// Lightweight recorder for the onboarding demo.
/// Captures audio level (for orb animation) and live transcript (for display).
/// Does NOT save files, create SwiftData entities, or contact the backend.
@MainActor
class OnboardingRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var audioLevel: CGFloat = 0
    @Published var liveTranscript: String = ""
    @Published var recordingDuration: TimeInterval = 0
    @Published var permissionDenied = false
    @Published var speechUnavailable = false

    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var durationTimer: Timer?
    private var lastAudioLevelUpdate: CFAbsoluteTime = 0
    private let audioLevelUpdateInterval: TimeInterval = 1.0 / 15.0 // ~15fps

    // MARK: - Start

    func startRecording() {
        Task {
            // Check mic permission
            let micGranted = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    cont.resume(returning: granted)
                }
            }
            guard micGranted else {
                permissionDenied = true
                return
            }

            // Check speech recognition permission
            let speechStatus = await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in
                    cont.resume(returning: status)
                }
            }

            let speechAvailable = speechStatus == .authorized

            if !speechAvailable {
                speechUnavailable = true
                // Still allow recording for audio-reactive orb, just no transcript
            }

            // Configure audio session
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker])
                try session.setActive(true)
            } catch {
                permissionDenied = true
                return
            }

            // Set up audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            // Set up speech recognition (if available)
            if speechAvailable {
                let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true

                self.speechRecognizer = recognizer
                self.recognitionRequest = request

                self.recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    if let result {
                        Task { @MainActor in
                            self.liveTranscript = result.bestTranscription.formattedString
                        }
                    }
                    if error != nil || (result?.isFinal ?? false) {
                        // Recognition ended — don't restart during onboarding
                    }
                }
            }

            // Install audio tap — feeds both level meter and speech recognizer
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self else { return }

                // Feed speech recognizer
                self.recognitionRequest?.append(buffer)

                // Compute audio level (throttled)
                let now = CFAbsoluteTimeGetCurrent()
                if now - self.lastAudioLevelUpdate >= self.audioLevelUpdateInterval {
                    self.lastAudioLevelUpdate = now
                    if let channelData = buffer.floatChannelData?[0] {
                        let frameCount = Int(buffer.frameLength)
                        var sumOfSquares: Float = 0
                        for i in 0..<frameCount {
                            let sample = channelData[i]
                            sumOfSquares += sample * sample
                        }
                        let rms = sqrt(sumOfSquares / Float(max(frameCount, 1)))
                        let normalized = CGFloat(min(rms * 10, 1.0))

                        Task { @MainActor in
                            self.audioLevel = self.audioLevel * 0.7 + normalized * 0.3
                        }
                    }
                }
            }

            do {
                try engine.start()
            } catch {
                permissionDenied = true
                return
            }

            self.audioEngine = engine
            self.isRecording = true
            self.recordingDuration = 0

            // Duration timer
            self.durationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.recordingDuration += 1
                }
            }
        }
    }

    // MARK: - Stop

    func stopRecording() {
        durationTimer?.invalidate()
        durationTimer = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        speechRecognizer = nil

        isRecording = false
        audioLevel = 0
    }

    // MARK: - Helpers

    var formattedDuration: String {
        let mins = Int(recordingDuration) / 60
        let secs = Int(recordingDuration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

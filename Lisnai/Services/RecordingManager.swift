import Foundation
import AVFoundation
import Speech
import UIKit
import CallKit
import ActivityKit
import SwiftData
import FirebaseAuth

@MainActor
class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPausedForCall = false  // Tracks if recording is paused due to phone call
    @Published var isPausedManually = false // Tracks if user manually paused recording
    @Published var recordingDuration = "00:00:00"
    @Published var transcription = ""
    @Published var summary = ""
    @Published var isProcessing = false
    @Published var audioLevel: CGFloat = 0

    /// Whether recording is paused (either manually or for a call)
    var isPaused: Bool { isPausedForCall || isPausedManually }

    /// ModelContext for saving to SwiftData (set from the view)
    var modelContext: ModelContext?

    // AVAudioEngine-based recording (supports background restart after interruptions)
    private var audioEngine: AVAudioEngine?
    private var currentAudioFile: AVAudioFile?
    private let audioWriteQueue = DispatchQueue(label: "com.lisnai.audiowrite", qos: .userInitiated)

    private var recordingSession: AVAudioSession?
    private var recordingStartTime: Date?
    private var recordingDate: Date?  // The date when recording started
    private var durationTimer: Timer?
    private var isAudioSessionSetup = false
    private var lastRecordingURL: URL?

    // Track elapsed time before pause (for accurate duration display across interruptions)
    private var elapsedTimeBeforePause: TimeInterval = 0

    // Segment-based recording: store URLs of all recording segments
    // On interruption, we close the current file and open a new one on resume
    // All segments are merged at the end
    private var recordingSegments: [URL] = []
    private var currentSegmentIndex = 0

    // Guard flag: prevents config change handler from restarting engine during active interruption
    private var isSuspendedForInterruption = false

    // Throttle audio level updates to ~15fps instead of ~60fps (reduces main thread pressure)
    private var lastAudioLevelUpdate: CFAbsoluteTime = 0
    private let audioLevelUpdateInterval: CFAbsoluteTime = 1.0 / 15.0

    // CallKit observer for detecting phone calls (more reliable than audio session interruption notifications)
    private let callObserver = CXCallObserver()

    // Live Activity for showing pause/resume UI in Dynamic Island
    private var recordingActivity: Activity<RecordingActivityAttributes>?

    // Chunk processing state
    private var chunkTimer: Timer?
    private var currentChunkIndex: Int = 0
    private var currentChunkStartTime: TimeInterval = 0
    private var recordingSessionId: String = ""
    private var accumulatedTranscript: String = ""
    private let chunkIntervalSeconds: TimeInterval = 300 // 5 minutes
    private var isProcessingChunk = false
    private var chunkRetryQueue: [(index: Int, cafURL: URL, startTime: TimeInterval, endTime: TimeInterval)] = []

    // Live suggestion state
    private var activeSuggestion: LiveSuggestion?
    private var suggestionDismissTimer: Timer?

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

        // Register for audio interruption notifications (phone calls, alarms, etc.)
        setupInterruptionObserver()

        // Set up CallKit observer for direct phone call detection
        // This is MORE RELIABLE than audio session interruption notifications
        callObserver.setDelegate(self, queue: nil)
        print("CallKit call observer set up")

        // Listen for resume request from Live Activity button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLiveActivityResumeRequest),
            name: Notification.Name("ResumeRecordingFromLiveActivity"),
            object: nil
        )

        // Listen for pause request from Live Activity
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePauseRequest),
            name: Notification.Name("PauseRecordingFromLiveActivity"),
            object: nil
        )

        // Listen for discard request from Live Activity
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDiscardRequest),
            name: Notification.Name("DiscardRecordingFromLiveActivity"),
            object: nil
        )

        // Listen for suggestion dismiss from Live Activity
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissSuggestion),
            name: Notification.Name("DismissSuggestionFromLiveActivity"),
            object: nil
        )

        // Listen for suggestion action execution from Live Activity
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExecuteSuggestionAction),
            name: Notification.Name("ExecuteSuggestionFromLiveActivity"),
            object: nil
        )

        print("Live Activity resume/pause/discard/suggestion observers set up")

        // Kill any zombie Live Activities from previous sessions (crash, force-quit, etc.)
        Task {
            await Self.endAllRecordingActivities()
            print("Live Activity: Cleaned up stale activities on launch")
        }
    }

    /// Handle resume request from Live Activity button tap (fallback manual resume)
    @objc private func handleLiveActivityResumeRequest() {
        print("Live Activity: Resume button tapped!")

        if isRecording, isPausedManually {
            resumeRecording()
            return
        }

        guard isRecording, isPausedForCall else {
            print("Live Activity: Cannot resume - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall)")
            return
        }

        // Request background execution time and attempt to resume
        // The resume flow will update the Live Activity to show "resumed" feedback
        resumeRecordingAfterCall()
    }

    /// Handle pause request from Live Activity
    @objc private func handlePauseRequest() {
        print("Live Activity: Pause button tapped!")
        pauseRecording()
    }

    /// Handle discard request from Live Activity (app will open for confirmation)
    @objc private func handleDiscardRequest() {
        print("Live Activity: Discard button tapped!")
        // Post a notification that HomeView listens for to show the confirmation alert
        NotificationCenter.default.post(name: Notification.Name("ShowDiscardConfirmation"), object: nil)
    }

    // MARK: - Live Suggestion Handling

    /// Handle a live suggestion received from the backend during recording
    private func handleLiveSuggestion(_ suggestion: LiveSuggestion) {
        activeSuggestion = suggestion

        // Update Live Activity to show suggestion banner (Swiggy-style expanding)
        updateLiveActivityToSuggestion(suggestion)

        // Auto-dismiss after expiresIn seconds (default 120)
        suggestionDismissTimer?.invalidate()
        suggestionDismissTimer = Timer.scheduledTimer(
            timeInterval: TimeInterval(suggestion.expiresIn),
            target: self,
            selector: #selector(autoDismissSuggestion),
            userInfo: nil,
            repeats: false
        )

        print("[LiveSuggestion] Surfaced: \(suggestion.title)")
    }

    /// Dismiss the current suggestion and revert Live Activity to recording state
    private func dismissSuggestion() {
        suggestionDismissTimer?.invalidate()
        suggestionDismissTimer = nil
        activeSuggestion = nil

        // Revert Live Activity back to recording state
        guard let activity = recordingActivity else { return }
        let state = RecordingActivityAttributes.ContentState(
            state: .recording,
            pausedAtDuration: "",
            message: "Recording"
        )
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil),
                alertConfiguration: nil
            )
        }
        print("[LiveSuggestion] Dismissed, reverted to recording")
    }

    /// Auto-dismiss timer handler
    @objc private func autoDismissSuggestion() {
        dismissSuggestion()
    }

    /// Handle dismiss from Live Activity intent
    @objc private func handleDismissSuggestion() {
        print("Live Activity: Suggestion dismiss tapped!")
        dismissSuggestion()
    }

    /// Handle execute action from Live Activity intent
    @objc private func handleExecuteSuggestionAction() {
        print("Live Activity: Suggestion action tapped!")
        guard let suggestion = activeSuggestion else { return }

        // Dismiss the suggestion UI first
        dismissSuggestion()

        // If it has an action skill, post notification for the app to handle
        if let skill = suggestion.actionSkill {
            var userInfo: [String: Any] = [
                "skill": skill,
                "title": suggestion.title,
                "body": suggestion.body,
            ]
            if let actionParams = suggestion.actionParams {
                userInfo["actionParams"] = actionParams
            }
            NotificationCenter.default.post(
                name: Notification.Name("ExecuteSuggestionAction"),
                object: nil,
                userInfo: userInfo
            )
        }
    }

    /// Update Live Activity to show a suggestion banner with alert configuration
    private func updateLiveActivityToSuggestion(_ suggestion: LiveSuggestion) {
        guard let activity = recordingActivity else { return }

        let state = RecordingActivityAttributes.ContentState(
            state: .suggestion,
            pausedAtDuration: "",
            message: "Recording",
            suggestionTitle: suggestion.title,
            suggestionBody: suggestion.body,
            suggestionType: suggestion.type
        )

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil),
                alertConfiguration: AlertConfiguration(
                    title: LocalizedStringResource(stringLiteral: suggestion.title),
                    body: LocalizedStringResource(stringLiteral: suggestion.body),
                    sound: .default
                )
            )
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupInterruptionObserver() {
        // Primary: Audio session interruption notification
        // Using object: nil to ensure we receive ALL interruption notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioInterruption),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )

        // Engine configuration change (fires AFTER interruption when hardware config changes)
        // Must handle both this AND interruptionNotification for robust recovery
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEngineConfigurationChange),
            name: NSNotification.Name.AVAudioEngineConfigurationChange,
            object: nil
        )

        // Fallback: App became active notification
        // This catches cases where interruptionTypeEnded notification is NOT fired (known iOS bug)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppBecameActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        print("Audio interruption, engine config change, and app lifecycle observers registered")
    }

    /// Handle AVAudioEngine configuration change (e.g., sample rate or route change after interruption)
    /// This can fire AFTER the interruption ended notification
    @objc nonisolated private func handleEngineConfigurationChange(notification: Notification) {
        Task { @MainActor in
            // Only act if we're NOT in an active interruption and were recording
            guard !isSuspendedForInterruption, isRecording, isPausedForCall else { return }
            print("AVAudioEngine: Configuration changed, attempting resume")
            autoResumeRecording()
        }
    }

    /// Fallback handler when app becomes active
    /// Used to resume recording if interruptionEnded notification was never received (known iOS bug)
    @objc nonisolated private func handleAppBecameActive(notification: Notification) {
        Task { @MainActor in
            // Only try to resume if we're paused for a call
            guard isRecording, isPausedForCall else {
                return
            }

            print("App became active while recording was paused - attempting auto-resume")

            // Use the same auto-resume flow as call ended
            autoResumeRecording()
        }
    }

    /// Handles audio session interruptions (e.g., incoming phone calls)
    /// Pauses recording when call comes in, resumes after call ends
    @objc nonisolated private func handleAudioInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let interruptionTypeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let interruptionType = AVAudioSession.InterruptionType(rawValue: interruptionTypeValue) else {
            return
        }

        // Extract options value before entering Task to avoid data race
        let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt

        Task { @MainActor in
            switch interruptionType {
            case .began:
                handleInterruptionBegan()

            case .ended:
                // Check if we should resume
                if let optionsValue = optionsValue {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    handleInterruptionEnded(shouldResume: options.contains(.shouldResume))
                } else {
                    // No options provided, attempt to resume anyway
                    handleInterruptionEnded(shouldResume: true)
                }

            @unknown default:
                print("Unknown audio interruption type")
            }
        }
    }

    /// Called when an interruption begins (e.g., phone call received)
    /// With AVAudioEngine: system already stopped the engine — do NOT call engine.stop() or deactivate session
    /// Just close the current audio file to finalize the segment
    private func handleInterruptionBegan() {
        print("AVAudioSession: Interruption BEGAN - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall)")

        guard isRecording else {
            print("AVAudioSession: Skipping - not recording")
            return
        }

        // Check if already paused (by CallKit or previous interruption)
        if isPausedForCall {
            print("AVAudioSession: Already paused, skipping")
            return
        }

        // Update Live Activity to show "Paused for call" state
        updateLiveActivityToPaused(pausedAtDuration: recordingDuration)

        // Save elapsed time
        if let startTime = recordingStartTime {
            elapsedTimeBeforePause += Date().timeIntervalSince(startTime)
        }

        isSuspendedForInterruption = true
        isPausedForCall = true
        durationTimer?.invalidate()
        durationTimer = nil

        // Close current audio file to finalize this segment
        // Do NOT stop the engine — system already stopped it
        // Do NOT deactivate audio session — this prevents background restart
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        print("AVAudioSession: Audio file closed, segment \(currentSegmentIndex) saved (engine suspended by system)")
    }

    /// Called when an interruption ends (e.g., phone call ended)
    private func handleInterruptionEnded(shouldResume: Bool) {
        guard isRecording, isPausedForCall else {
            print("AVAudioSession: Cannot resume - isRecording=\(isRecording), isPausedForCall=\(isPausedForCall)")
            return
        }

        print("AVAudioSession: Interruption ended (shouldResume hint: \(shouldResume))")

        if shouldResume {
            // Auto-resume recording (YapNote-style seamless experience)
            autoResumeRecording()
        } else {
            // System says don't auto-resume — fall back to manual
            handleCallEnded()
        }
    }

    private func setupAudioSessionIfNeeded() throws {
        // Only setup once
        guard !isAudioSessionSetup else { return }

        recordingSession = AVAudioSession.sharedInstance()

        // Use .playAndRecord instead of .record for better background handling
        // .mixWithOthers is CRITICAL - allows app to resume recording in background after phone call
        // .allowBluetoothA2DP enables Bluetooth audio devices
        // .defaultToSpeaker routes playback to speaker (not used for recording, but required for playAndRecord)
        if #available(iOS 26.0, *) {
            try recordingSession?.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker, .bluetoothHighQualityRecording]
            )
        } else {
            try recordingSession?.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
            )
        }

        try recordingSession?.setActive(true)

        isAudioSessionSetup = true
        print("Audio session setup complete with playAndRecord category")
    }

    func requestMicrophonePermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: - Manual Pause / Resume / Discard

    /// Manually pause recording — keeps engine alive, closes audio file, freezes timer
    func pauseRecording() {
        guard isRecording, !isPausedManually, !isPausedForCall else {
            print("PauseRecording: Cannot pause - isRecording: \(isRecording), isPausedManually: \(isPausedManually), isPausedForCall: \(isPausedForCall)")
            return
        }

        // Save elapsed time
        if let startTime = recordingStartTime {
            elapsedTimeBeforePause += Date().timeIntervalSince(startTime)
        }

        // Stop timer
        durationTimer?.invalidate()
        durationTimer = nil

        // Close current audio file to finalize this segment
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        isPausedManually = true

        // Update Live Activity to manual pause state
        updateLiveActivityToManualPause()

        print("PauseRecording: Recording paused manually (segment \(currentSegmentIndex) saved)")
    }

    /// Resume recording after manual pause
    func resumeRecording() {
        guard isRecording, isPausedManually else {
            print("ResumeRecording: Cannot resume - isRecording: \(isRecording), isPausedManually: \(isPausedManually)")
            return
        }

        print("ResumeRecording: Resuming from manual pause...")

        Task {
            let success = await attemptStartNewSegmentAfterManualPause()

            if success {
                isPausedManually = false
                recordingStartTime = Date()
                startDurationTimer()
                updateLiveActivityToRecording()
                print("ResumeRecording: Recording resumed successfully")
            } else {
                print("ResumeRecording: Failed to resume recording")
            }
        }
    }

    /// Discard recording — tear down everything without processing
    func discardRecording() {
        print("DiscardRecording: Discarding recording...")

        // Stop chunk timer
        chunkTimer?.invalidate()
        chunkTimer = nil

        // Stop engine and remove tap
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Close audio file
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        // Reset all state
        isRecording = false
        SuggestionMonitor.shared.isRecordingActive = false
        isPausedManually = false
        isPausedForCall = false
        isSuspendedForInterruption = false
        audioLevel = 0
        durationTimer?.invalidate()
        durationTimer = nil

        // Delete all segment files
        for segmentURL in recordingSegments {
            try? FileManager.default.removeItem(at: segmentURL)
        }
        print("DiscardRecording: Deleted \(recordingSegments.count) segment file(s)")

        // Reset segment state
        recordingSegments = []
        currentSegmentIndex = 0
        elapsedTimeBeforePause = 0
        recordingStartTime = nil
        recordingDuration = "00:00:00"

        // End Live Activity
        endRecordingLiveActivity()

        // If chunks were already sent to backend, send discard signal
        if currentChunkIndex > 0 {
            let sessionId = recordingSessionId
            Task {
                await sendDiscardSignal(sessionId: sessionId)
            }
        }

        print("DiscardRecording: Recording discarded")
    }

    /// Attempt to start a new audio segment after manual pause (no retry loop needed since engine is still alive)
    private func attemptStartNewSegmentAfterManualPause() async -> Bool {
        guard let engine = audioEngine else {
            print("ManualResume: No engine available")
            return false
        }

        do {
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            try openNewSegmentFile(format: format)

            // Engine may still be running — try to start it (no-op if already running)
            if !engine.isRunning {
                try engine.start()
            }

            return true
        } catch {
            print("ManualResume: Failed to start new segment: \(error.localizedDescription)")
            return false
        }
    }

    /// Send discard signal to backend to clean up any chunks already sent
    private func sendDiscardSignal(sessionId: String) async {
        let request = ProcessChunkRequest(
            recordingSessionId: sessionId,
            chunkIndex: -1,
            transcript: "",
            isFinal: true,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            chunkStartTime: nil,
            chunkEndTime: nil
        )

        do {
            let _ = try await APIService.shared.processChunk(request)
            print("[Discard] Backend notified for session \(sessionId)")
        } catch {
            print("[Discard] Failed to notify backend: \(error.localizedDescription)")
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

        // Reset pause tracking and segments for new recording session
        elapsedTimeBeforePause = 0
        isPausedForCall = false
        isPausedManually = false
        isSuspendedForInterruption = false
        recordingSegments = []
        currentSegmentIndex = 0

        // Capture the recording start date
        recordingDate = Date()

        do {
            // Create engine (persists across interruptions — just restart, don't recreate)
            let engine = AVAudioEngine()
            self.audioEngine = engine

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            // Open first audio file for this segment
            try openNewSegmentFile(format: recordingFormat)

            // Install tap on input node — writes audio buffers to the current file
            // The tap persists across engine stop/start cycles (interruptions)
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
                guard let self else { return }

                // Compute RMS audio level for orb visualization (throttled to ~15fps)
                let now = CFAbsoluteTimeGetCurrent()
                if now - self.lastAudioLevelUpdate >= self.audioLevelUpdateInterval,
                   let channelData = buffer.floatChannelData?[0] {
                    self.lastAudioLevelUpdate = now
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

                self.audioWriteQueue.async {
                    try? self.currentAudioFile?.write(from: buffer)
                }
            }

            try engine.start()

            isRecording = true
            SuggestionMonitor.shared.isRecordingActive = true
            recordingStartTime = Date()
            startDurationTimer()

            print("AVAudioEngine: Recording started with format \(recordingFormat)")
        } catch {
            print("AVAudioEngine: Failed to start recording: \(error.localizedDescription)")
            return
        }

        // Start Live Activity while app is in foreground (minimal UI during recording)
        // This MUST be done here so we can UPDATE it later when a call comes in
        startRecordingLiveActivity()

        // Initialize chunk processing for long recordings
        recordingSessionId = UUID().uuidString
        currentChunkIndex = 0
        currentChunkStartTime = 0
        accumulatedTranscript = ""
        chunkRetryQueue = []

        // Start chunk timer — fires every 5 minutes to export and process a chunk
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.exportCurrentChunk()
            }
        }
        print("Chunk timer started (interval: \(chunkIntervalSeconds)s, sessionId: \(recordingSessionId))")
    }

    /// Opens a new audio file for the next recording segment
    /// Called at start and after each interruption resume
    private func openNewSegmentFile(format: AVAudioFormat) throws {
        let timestamp = Date().timeIntervalSince1970
        let audioFilename = getDocumentsDirectory().appendingPathComponent("recording_\(timestamp)_segment\(currentSegmentIndex).caf")

        let file = try AVAudioFile(forWriting: audioFilename, settings: format.settings)

        audioWriteQueue.sync {
            self.currentAudioFile = file
        }

        recordingSegments.append(audioFilename)
        currentSegmentIndex += 1

        print("AVAudioEngine: Opened segment file \(currentSegmentIndex): \(audioFilename.lastPathComponent)")
    }

    func stopRecording() {
        // Stop chunk timer
        chunkTimer?.invalidate()
        chunkTimer = nil

        // Stop engine and remove tap
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Close current audio file
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        isRecording = false
        SuggestionMonitor.shared.isRecordingActive = false
        isPausedForCall = false
        isPausedManually = false
        isSuspendedForInterruption = false
        audioLevel = 0
        durationTimer?.invalidate()
        durationTimer = nil

        print("Recording stopped with \(recordingSegments.count) segment(s)")

        // Capture final duration before resetting (include current segment time)
        if let startTime = recordingStartTime {
            elapsedTimeBeforePause += Date().timeIntervalSince(startTime)
        }
        let capturedDuration = elapsedTimeBeforePause

        // Reset for next recording
        elapsedTimeBeforePause = 0
        recordingStartTime = nil

        let hadChunks = currentChunkIndex > 0
        let capturedSessionId = recordingSessionId
        let capturedChunkIndex = currentChunkIndex

        // Process recording
        if !recordingSegments.isEmpty {
            Task {
                if hadChunks {
                    // Multi-chunk: process the final segment then send finalization
                    await processRemainingSegmentAsChunk(
                        sessionId: capturedSessionId,
                        chunkIndex: capturedChunkIndex,
                        duration: capturedDuration
                    )
                } else {
                    // Single segment: use existing flow (backward compatible)
                    await processRecordingSegments(duration: capturedDuration)
                }
            }
        }

        // End Live Activity
        endRecordingLiveActivity()
    }

    /// Merges recording segments and exports to compressed M4A
    /// Even single segments are exported to M4A to compress from raw PCM (CAF) to AAC
    private func mergeAudioSegments() async -> URL? {
        guard !recordingSegments.isEmpty else { return nil }

        print("Exporting \(recordingSegments.count) audio segment(s) to M4A...")

        // Create composition for merging
        let composition = AVMutableComposition()

        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)
        ) else {
            print("Failed to create composition track")
            return recordingSegments[0] // Fallback to first segment
        }

        var currentTime = CMTime.zero

        for (index, segmentURL) in recordingSegments.enumerated() {
            do {
                let asset = AVURLAsset(url: segmentURL)
                let duration = try await asset.load(.duration)

                guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
                    print("No audio track in segment \(index)")
                    continue
                }

                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: currentTime
                )

                currentTime = CMTimeAdd(currentTime, duration)
                print("Added segment \(index + 1) to composition")
            } catch {
                print("Failed to add segment \(index): \(error.localizedDescription)")
            }
        }

        // Export merged audio
        let mergedURL = getDocumentsDirectory().appendingPathComponent("recording_merged_\(Date().timeIntervalSince1970).m4a")

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            print("Failed to create export session")
            return recordingSegments[0]
        }

        exportSession.outputURL = mergedURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            print("Audio segments merged successfully: \(mergedURL.lastPathComponent)")

            // Clean up individual segment files
            for segmentURL in recordingSegments {
                try? FileManager.default.removeItem(at: segmentURL)
            }

            return mergedURL
        } else {
            print("Export failed: \(exportSession.error?.localizedDescription ?? "Unknown error")")
            return recordingSegments[0]
        }
    }

    /// Process recording segments - merge if needed, then transcribe
    private func processRecordingSegments(duration: TimeInterval) async {
        isProcessing = true
        transcription = "Processing recording segments..."

        // Merge segments if there are multiple
        guard let finalURL = await mergeAudioSegments() else {
            transcription = "Error: No recording segments found"
            isProcessing = false
            return
        }

        lastRecordingURL = finalURL
        await processRecording(fileURL: finalURL, duration: duration)
    }

    private func processRecording(fileURL: URL, duration: TimeInterval) async {
        isProcessing = true
        transcription = "Transcribing and identifying speakers..."
        summary = ""

        let totalDuration = duration
        let date = recordingDate ?? Date()

        do {
            let labeledTranscript: String

            if useDeepgram {
                // Use Deepgram (transcription + diarization in one API call)
                print("Using Deepgram API...")
                let (_, segments) = try await deepgramService.transcribeAndDiarize(fileURL: fileURL)

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

            // Step 4: Send through chunk endpoint for unified processing (includes insight generation)
            let chunkRequest = ProcessChunkRequest(
                recordingSessionId: recordingSessionId,
                chunkIndex: 0,
                transcript: labeledTranscript,
                isFinal: true,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                chunkStartTime: 0,
                chunkEndTime: totalDuration
            )

            var summaryText = ""
            var chunkResult: ChunkProcessResult?
            do {
                let result = try await DataService.shared.processChunk(
                    chunkRequest,
                    transcript: labeledTranscript,
                    context: modelContext!
                )
                summaryText = result.summary ?? ""
                summary = summaryText
                chunkResult = result
                print("[SingleChunk] Backend processed: title=\(result.title ?? "nil"), hasInsight=\(result.insight != nil)")
            } catch {
                print("[SingleChunk] Backend processing failed: \(error.localizedDescription)")
            }

            // Step 5: Save to SwiftData directly (don't use saveToSwiftData which double-sends to backend)
            if let context = modelContext {
                let recording = Recording(date: date, duration: totalDuration, title: chunkResult?.title)

                let transcriptionModel = Transcription(date: date, text: labeledTranscript, recording: recording)
                recording.transcription = transcriptionModel

                if !summaryText.isEmpty {
                    let summaryModel = Summary(date: date, text: summaryText, recording: recording)
                    recording.summary = summaryModel
                }

                // Attach insight if available
                if let insightData = chunkResult?.insight {
                    let insight = Insight(
                        date: date,
                        setting: insightData.setting,
                        settingEmoji: insightData.settingEmoji,
                        mood: insightData.mood,
                        thirdPersonTake: insightData.thirdPersonTake,
                        correlations: insightData.correlations?.map { InsightCorrelation(memoryDate: $0.memoryDate, connection: $0.connection) } ?? [],
                        actionableIdeas: insightData.actionableIdeas ?? []
                    )
                    recording.insight = insight
                    insight.recording = recording
                    print("[SingleChunk] Insight attached to recording")
                }

                context.insert(recording)
                do {
                    try context.save()
                    print("[SingleChunk] SwiftData saved: title=\(recording.title ?? "nil"), hasInsight=\(recording.insight != nil)")
                } catch {
                    print("[SingleChunk] SwiftData save failed: \(error.localizedDescription)")
                }
            }

            // Step 6: Delete the audio file (we don't need it anymore)
            deleteAudioFile(at: fileURL)

        } catch {
            print("Processing error: \(error.localizedDescription)")
            transcription = "Error: \(error.localizedDescription)"
            summary = ""
        }

        isProcessing = false
    }

    // MARK: - Chunk Processing

    /// Export the current audio segment as a chunk without stopping recording
    /// Same pattern as phone call interruption: close file, open new one
    private func exportCurrentChunk() {
        guard isRecording, !isPausedForCall, !isPausedManually, !isProcessingChunk else {
            print("[Chunk] Skipping export - isRecording:\(isRecording) isPausedForCall:\(isPausedForCall) isPausedManually:\(isPausedManually) isProcessing:\(isProcessingChunk)")
            return
        }

        guard let engine = audioEngine else {
            print("[Chunk] No audio engine available")
            return
        }

        let chunkIndex = currentChunkIndex
        let chunkStartTime = currentChunkStartTime
        let chunkEndTime = elapsedTimeBeforePause + (recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0)

        // Close current audio file (finalize this segment)
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        // Grab the last segment URL (the chunk we just closed)
        guard let chunkCAFURL = recordingSegments.last else {
            print("[Chunk] No segment file available")
            return
        }

        // Open a new segment file immediately (microsecond gap)
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        do {
            try openNewSegmentFile(format: format)
        } catch {
            print("[Chunk] Failed to open new segment: \(error.localizedDescription)")
            return
        }

        // Update chunk state for next interval
        currentChunkIndex += 1
        currentChunkStartTime = chunkEndTime

        print("[Chunk] Exported chunk \(chunkIndex) (segments: \(recordingSegments.count))")

        // Process chunk asynchronously (doesn't block recording)
        Task {
            await processChunkAsync(
                index: chunkIndex,
                cafURL: chunkCAFURL,
                startTime: chunkStartTime,
                endTime: chunkEndTime
            )
        }
    }

    /// Process a single chunk: export to M4A, transcribe, send to backend
    private func processChunkAsync(index: Int, cafURL: URL, startTime: TimeInterval, endTime: TimeInterval) async {
        isProcessingChunk = true
        defer { isProcessingChunk = false }

        print("[Chunk] Processing chunk \(index)...")

        // Step 1: Export CAF to M4A
        guard let m4aURL = await exportCAFToM4A(cafURL: cafURL) else {
            print("[Chunk] Failed to export chunk \(index) to M4A, queuing for retry")
            chunkRetryQueue.append((index: index, cafURL: cafURL, startTime: startTime, endTime: endTime))
            return
        }

        // Step 2: Transcribe with Deepgram
        let transcript: String
        do {
            let (fullText, segments) = try await deepgramService.transcribeAndDiarize(fileURL: m4aURL)
            transcript = formatDeepgramTranscript(segments: segments)
            print("[Chunk] Transcribed chunk \(index): \(transcript.count) chars")
        } catch {
            print("[Chunk] Transcription failed for chunk \(index): \(error.localizedDescription)")
            // Clean up M4A
            try? FileManager.default.removeItem(at: m4aURL)
            chunkRetryQueue.append((index: index, cafURL: cafURL, startTime: startTime, endTime: endTime))
            return
        }

        // Step 3: Append to accumulated transcript (for UI display)
        if !accumulatedTranscript.isEmpty {
            accumulatedTranscript += "\n\n"
        }
        accumulatedTranscript += transcript
        transcription = accumulatedTranscript

        // Step 4: Send to backend
        await sendChunkToBackend(
            chunkIndex: index,
            transcript: transcript,
            isFinal: false,
            startTime: startTime,
            endTime: endTime
        )

        // Step 5: Clean up audio files
        try? FileManager.default.removeItem(at: m4aURL)
        try? FileManager.default.removeItem(at: cafURL)

        print("[Chunk] Chunk \(index) processed successfully")
    }

    /// Process the remaining (final) audio segment when recording stops in multi-chunk mode
    private func processRemainingSegmentAsChunk(sessionId: String, chunkIndex: Int, duration: TimeInterval) async {
        isProcessing = true

        // The last segment is the one that was being recorded when stop was called
        guard let lastSegmentURL = recordingSegments.last else {
            print("[Chunk] No final segment to process")
            await sendFinalizationSignal(sessionId: sessionId)
            isProcessing = false
            return
        }

        // Export and transcribe the final segment
        guard let m4aURL = await exportCAFToM4A(cafURL: lastSegmentURL) else {
            print("[Chunk] Failed to export final segment")
            await sendFinalizationSignal(sessionId: sessionId)
            isProcessing = false
            return
        }

        let transcript: String
        do {
            let (_, segments) = try await deepgramService.transcribeAndDiarize(fileURL: m4aURL)
            transcript = formatDeepgramTranscript(segments: segments)
        } catch {
            print("[Chunk] Final segment transcription failed: \(error.localizedDescription)")
            transcript = ""
        }

        // Append final transcript
        if !transcript.isEmpty {
            if !accumulatedTranscript.isEmpty {
                accumulatedTranscript += "\n\n"
            }
            accumulatedTranscript += transcript
            transcription = accumulatedTranscript
        }

        // Send final chunk to backend
        if !transcript.isEmpty {
            await sendChunkToBackend(
                chunkIndex: chunkIndex,
                transcript: transcript,
                isFinal: false,
                startTime: currentChunkStartTime,
                endTime: duration
            )
        }

        // Send finalization signal
        let finalizationResult = await sendFinalizationSignal(sessionId: sessionId)

        // Save to SwiftData directly (don't use saveToSwiftData which double-sends to backend)
        let date = recordingDate ?? Date()
        if let context = modelContext {
            let recording = Recording(date: date, duration: duration, title: finalizationResult?.title)

            let transcriptionModel = Transcription(date: date, text: accumulatedTranscript, recording: recording)
            recording.transcription = transcriptionModel

            let summaryText = finalizationResult?.summary ?? ""
            if !summaryText.isEmpty {
                let summaryModel = Summary(date: date, text: summaryText, recording: recording)
                recording.summary = summaryModel
            }

            // Attach insight if available
            if let insightData = finalizationResult?.insight {
                let insight = Insight(
                    date: date,
                    setting: insightData.setting,
                    settingEmoji: insightData.settingEmoji,
                    mood: insightData.mood,
                    thirdPersonTake: insightData.thirdPersonTake,
                    correlations: insightData.correlations?.map { InsightCorrelation(memoryDate: $0.memoryDate, connection: $0.connection) } ?? [],
                    actionableIdeas: insightData.actionableIdeas ?? []
                )
                recording.insight = insight
                insight.recording = recording
                print("[Chunk] Insight saved to recording")
            }

            context.insert(recording)
            do {
                try context.save()
                print("[Chunk] Recording saved to SwiftData")
            } catch {
                print("[Chunk] SwiftData save failed: \(error.localizedDescription)")
            }
        }

        // Clean up all segment files
        for segmentURL in recordingSegments {
            try? FileManager.default.removeItem(at: segmentURL)
        }
        try? FileManager.default.removeItem(at: m4aURL)

        isProcessing = false
        print("[Chunk] Multi-chunk recording finalized (\(chunkIndex + 1) chunks)")
    }

    /// Export a CAF file to M4A format
    private func exportCAFToM4A(cafURL: URL) async -> URL? {
        let m4aURL = cafURL.deletingPathExtension().appendingPathExtension("m4a")

        let asset = AVURLAsset(url: cafURL)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            print("[Chunk] Failed to create export session")
            return nil
        }

        exportSession.outputURL = m4aURL
        exportSession.outputFileType = .m4a

        await exportSession.export()

        if exportSession.status == .completed {
            return m4aURL
        } else {
            print("[Chunk] Export failed: \(exportSession.error?.localizedDescription ?? "unknown")")
            return nil
        }
    }

    /// Send a chunk to the backend API
    private func sendChunkToBackend(
        chunkIndex: Int,
        transcript: String,
        isFinal: Bool,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async {
        let request = ProcessChunkRequest(
            recordingSessionId: recordingSessionId,
            chunkIndex: chunkIndex,
            transcript: transcript,
            isFinal: isFinal,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            chunkStartTime: startTime,
            chunkEndTime: endTime
        )

        // Retry up to 3 times with exponential backoff
        for attempt in 1...3 {
            do {
                let result: ChunkProcessResult
                if let ctx = modelContext {
                    result = try await DataService.shared.processChunk(request, transcript: transcript, context: ctx)
                } else {
                    result = try await APIService.shared.processChunk(request)
                }
                print("[Chunk] Backend processed chunk \(chunkIndex): status=\(result.status)")

                // Check for live suggestion from backend
                if let suggestion = result.liveSuggestion {
                    handleLiveSuggestion(suggestion)
                }
                return
            } catch {
                print("[Chunk] Backend failed for chunk \(chunkIndex), attempt \(attempt): \(error.localizedDescription)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 5_000_000_000) // 5s, 10s
                }
            }
        }
        print("[Chunk] Backend permanently failed for chunk \(chunkIndex)")
    }

    /// Send finalization signal to consolidate the recording
    private func sendFinalizationSignal(sessionId: String) async -> ChunkProcessResult? {
        let request = ProcessChunkRequest(
            recordingSessionId: sessionId,
            chunkIndex: -1,
            transcript: "",
            isFinal: true,
            timestamp: ISO8601DateFormatter().string(from: Date()),
            chunkStartTime: nil,
            chunkEndTime: nil
        )

        do {
            let result: ChunkProcessResult
            if let ctx = modelContext {
                result = try await DataService.shared.processChunk(request, transcript: "", context: ctx)
            } else {
                result = try await APIService.shared.processChunk(request)
            }
            print("[Chunk] Finalization complete: title=\(result.title ?? "nil")")
            return result
        } catch {
            print("[Chunk] Finalization failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Save recording data to SwiftData and send to backend
    private func saveToSwiftData(date: Date, duration: TimeInterval, transcriptionText: String, summaryText: String) async {
        guard let context = modelContext else {
            print("SwiftData: No model context available, skipping save")
            return
        }

        // Create Recording
        let recording = Recording(date: date, duration: duration)

        // Create Transcription
        let transcriptionModel = Transcription(date: date, text: transcriptionText, recording: recording)
        recording.transcription = transcriptionModel

        // Create Summary (if not empty)
        if !summaryText.isEmpty {
            let summaryModel = Summary(date: date, text: summaryText, recording: recording)
            recording.summary = summaryModel
        }

        // Insert into context
        context.insert(recording)

        do {
            try context.save()
            print("SwiftData: Recording saved successfully")
        } catch {
            print("SwiftData: Failed to save - \(error.localizedDescription)")
        }

        // Send transcript to backend for AI processing
        // This runs in parallel with local save - non-blocking
        await sendTranscriptToBackend(transcriptionText, recording: recording)
    }

    /// Send transcript to the backend for AI processing
    /// Handles entity extraction, memory storage, intent classification, and action execution
    private func sendTranscriptToBackend(_ transcript: String, recording: Recording? = nil) async {
        guard !transcript.isEmpty else {
            print("Backend: Skipping empty transcript")
            return
        }

        print("[Backend] Sending transcript (\(transcript.count) chars)...")
        print("[Backend] Auth check: currentUser=\(Auth.auth().currentUser?.uid ?? "NIL")")

        do {
            let result = try await APIService.shared.processTranscript(transcript)

            print("[Backend] Processing complete")
            print("  - Memory ID: \(result.memoryId)")
            print("  - Intent: \(result.intent.intent) (\(result.intent.confidence))")
            print("  - Summary: \(result.summary ?? "nil")")

            // Update recording title and summary from backend
            if let recording = recording {
                if let title = result.title {
                    recording.title = title
                    print("[Backend] Title set to '\(title)'")
                }
                if let summaryText = result.summary, !summaryText.isEmpty {
                    let summaryModel = Summary(date: recording.date, text: summaryText, recording: recording)
                    recording.summary = summaryModel
                    summary = summaryText
                    print("[Backend] Summary set: \(summaryText.prefix(80))...")
                }
                try? modelContext?.save()
            }

            // Handle action results
            if let actionResult = result.actionResult {
                await handleActionResult(actionResult)
            }

            // If there's a chat response from the AI, we could show it
            // This happens when the intent is 'query' or 'action'
            if let chatResponse = result.chatResponse {
                print("Backend: AI Response - \(chatResponse)")
                // Could trigger a local notification or update UI
                await showAIResponse(chatResponse)
            }

        } catch {
            print("[Backend] FAILED to process transcript: \(error)")
            print("[Backend] Error description: \(error.localizedDescription)")
        }
    }

    /// Handle action result from backend processing
    private func handleActionResult(_ actionResult: ActionResult) async {
        if actionResult.permissionRequired {
            // Permission is needed - send a local notification
            print("[RecordingManager] Permission required for action")
            if let permissionId = actionResult.pendingPermissionId,
               let message = actionResult.permissionMessage {
                await requestPermissionNotification(permissionId: permissionId, message: message)
            }
        } else if actionResult.executed, let toolResult = actionResult.toolResult {
            print("[RecordingManager] Action executed - \(toolResult.message)")

            // Auto-execute the action on-device via deep link
            if let deepLink = toolResult.iosDeepLink,
               let url = URL(string: deepLink) {
                let result = await ActionExecutor.shared.handleDeepLink(url)
                if let result = result {
                    print("[RecordingManager] Auto-executed action: success=\(result.success), \(result.message)")
                } else {
                    print("[RecordingManager] Deep link returned nil result for: \(deepLink)")
                }
            }
        } else if let error = actionResult.error {
            print("[RecordingManager] Action failed - \(error)")
        }
    }

    /// Show AI response (e.g., as a local notification or update chat)
    private func showAIResponse(_ response: String) async {
        // For now, just log it
        // Could integrate with NotificationService to show as local notification
        print("AI Response: \(response)")
    }

    /// Request permission via local notification
    private func requestPermissionNotification(permissionId: String, message: String) async {
        // Will be implemented with NotificationService
        print("Permission Request: \(message) (ID: \(permissionId))")
    }

    /// Delete the audio file after processing
    private func deleteAudioFile(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print("Audio file deleted: \(url.lastPathComponent)")
        } catch {
            print("Failed to delete audio file: \(error.localizedDescription)")
        }
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
        // Add any elapsed time from before a pause (for accurate total duration)
        let totalDuration = duration + elapsedTimeBeforePause
        let hours = Int(totalDuration) / 3600
        let minutes = (Int(totalDuration) % 3600) / 60
        let seconds = Int(totalDuration) % 60
        recordingDuration = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // TODO: Implement iOS 26 SpeechAnalyzer transcription
    // private func transcribeRecording() {
    //     // Use SpeechAnalyzer + SpeechTranscriber
    // }

    // MARK: - Live Activity Management

    /// Start a Live Activity when recording begins (minimal UI, almost invisible)
    /// This MUST be called while app is in foreground
    private func startRecordingLiveActivity() {
        // Check if Live Activities are supported
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activity: Not supported or not enabled")
            return
        }

        // Don't start if already active
        guard recordingActivity == nil else {
            print("Live Activity: Already active")
            return
        }

        let attributes = RecordingActivityAttributes(startDate: Date())
        let initialState = RecordingActivityAttributes.ContentState(
            state: .recording,  // Start with minimal "recording" state
            pausedAtDuration: "",
            message: "Recording"
        )

        // Stale date: auto-dismiss after 4 hours if app crashes and can't clean up
        let staleDate = Date().addingTimeInterval(4 * 60 * 60)

        do {
            recordingActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: staleDate),
                pushType: nil
            )
            print("Live Activity: Started in recording state (minimal, stale in 4h)")
        } catch {
            print("Live Activity: Failed to start - \(error.localizedDescription)")
        }
    }

    /// Update Live Activity to show "Paused for call" state
    private func updateLiveActivityToPaused(pausedAtDuration: String) {
        guard let activity = recordingActivity else {
            print("Live Activity: No active activity to update to paused")
            return
        }

        let updatedState = RecordingActivityAttributes.ContentState(
            state: .paused,
            pausedAtDuration: pausedAtDuration,
            message: "Recording paused for call"
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil),
                alertConfiguration: AlertConfiguration(
                    title: "Recording Paused",
                    body: "Paused for phone call",
                    sound: .default
                )
            )
            print("Live Activity: Updated to paused state")
        }
    }

    /// Update Live Activity to show "Manual Pause" state
    private func updateLiveActivityToManualPause() {
        guard let activity = recordingActivity else {
            print("Live Activity: No active activity to update to manual pause")
            return
        }

        let updatedState = RecordingActivityAttributes.ContentState(
            state: .manualPause,
            pausedAtDuration: recordingDuration,
            message: "Recording paused"
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
            print("Live Activity: Updated to manual pause state")
        }
    }

    /// Update Live Activity to show "Mic Resumed" state (brief visual feedback after auto-resume)
    private func updateLiveActivityToResumed() {
        guard let activity = recordingActivity else {
            print("Live Activity: No active activity to update to resumed")
            return
        }

        let updatedState = RecordingActivityAttributes.ContentState(
            state: .resumed,
            pausedAtDuration: "",
            message: "Mic resumed - Listening"
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil),
                alertConfiguration: AlertConfiguration(
                    title: "Recording Resumed",
                    body: "Mic is active again",
                    sound: .default
                )
            )
            print("Live Activity: Updated to resumed state (brief feedback)")
        }
    }

    /// Update Live Activity back to normal recording state (minimal)
    private func updateLiveActivityToRecording() {
        guard let activity = recordingActivity else { return }

        let updatedState = RecordingActivityAttributes.ContentState(
            state: .recording,
            pausedAtDuration: "",
            message: "Recording"
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil)
            )
            print("Live Activity: Reverted to recording state")
        }
    }

    /// Update Live Activity to show "Ready to Resume" state with button (fallback when auto-resume fails)
    private func updateLiveActivityToReadyToResume() {
        guard let activity = recordingActivity else {
            print("Live Activity: No active activity to update")
            return
        }

        let updatedState = RecordingActivityAttributes.ContentState(
            state: .readyToResume,
            pausedAtDuration: recordingDuration,
            message: "Call ended - Tap to resume"
        )

        Task {
            await activity.update(
                ActivityContent(state: updatedState, staleDate: nil),
                alertConfiguration: AlertConfiguration(
                    title: "Call Ended",
                    body: "Tap to resume recording",
                    sound: .default
                )
            )
            print("Live Activity: Updated to ready-to-resume state with alert")
        }
    }

    /// End the Live Activity
    private func endRecordingLiveActivity() {
        // End our tracked activity
        if let activity = recordingActivity {
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                print("Live Activity: Ended tracked activity")
            }
            recordingActivity = nil
        }

        // Safety net: end ALL recording Live Activities (catches zombies from crashes/force-quits)
        Task {
            await Self.endAllRecordingActivities()
        }
    }

    /// Kill ALL recording Live Activities system-wide — catches zombies from crashes, force-quits, etc.
    /// Called on app launch and when stopping/discarding recordings as a safety net.
    static func endAllRecordingActivities() async {
        for activity in Activity<RecordingActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("Live Activity: Ended zombie activity \(activity.id)")
        }
    }
}

// MARK: - CXCallObserverDelegate
extension RecordingManager: CXCallObserverDelegate {
    /// Called when any call state changes on the device
    /// This is MORE RELIABLE than AVAudioSession interruption notifications
    nonisolated func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        // Extract call properties BEFORE entering Task to avoid data races
        let hasEnded = call.hasEnded
        let isOutgoing = call.isOutgoing
        let hasConnected = call.hasConnected
        let isOnHold = call.isOnHold

        // Count active calls before entering Task
        let activeCallsCount = callObserver.calls.filter { !$0.hasEnded }.count

        Task { @MainActor in
            print("CallKit: Call state changed - hasEnded: \(hasEnded), isOutgoing: \(isOutgoing), hasConnected: \(hasConnected), isOnHold: \(isOnHold)")
            print("CallKit: Active calls count: \(activeCallsCount)")

            if hasEnded {
                // Call ended - check if all calls are done
                if activeCallsCount == 0 {
                    print("CallKit: All calls ended")
                    handleCallEnded()
                }
            } else if !hasEnded && (isOutgoing || hasConnected || !isOnHold) {
                // Call is active (incoming answered, outgoing, or connected)
                print("CallKit: Active call detected, pausing recording")
                pauseRecordingForCall()
            }
        }
    }

    /// Close current audio file when a phone call is detected
    /// With AVAudioEngine: do NOT stop engine or deactivate session — system handles engine suspension
    /// Just close the file to finalize the segment; engine will be restarted on resume
    private func pauseRecordingForCall() {
        guard isRecording, !isPausedForCall, !isPausedManually else {
            print("CallKit: Cannot pause - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall), isPausedManually: \(isPausedManually)")
            return
        }

        // Update Live Activity to show "Paused for call" state
        updateLiveActivityToPaused(pausedAtDuration: recordingDuration)

        // Save elapsed time
        if let startTime = recordingStartTime {
            elapsedTimeBeforePause += Date().timeIntervalSince(startTime)
        }

        isSuspendedForInterruption = true
        isPausedForCall = true
        durationTimer?.invalidate()
        durationTimer = nil

        // Close current audio file to finalize this segment
        // Do NOT stop engine or deactivate session — this is critical for background restart
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        print("CallKit: Audio file closed for phone call (segment \(currentSegmentIndex) saved, engine suspended by system)")
    }

    /// Called when call ends - attempt auto-resume first, fall back to manual
    private func handleCallEnded() {
        guard isRecording, isPausedForCall else {
            print("CallKit: Call ended but not in paused recording state")
            return
        }

        print("CallKit: Call ended, attempting auto-resume")

        // Auto-resume recording (YapNote-style seamless experience)
        autoResumeRecording()
    }

    /// Automatically resume recording after a call ends (YapNote-style)
    /// Updates Live Activity to show brief "resumed" feedback, then reverts to recording state
    /// Falls back to manual "Tap to Resume" if auto-resume fails after all retries
    private func autoResumeRecording() {
        guard isRecording, isPausedForCall else {
            print("AutoResume: Cannot resume - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall)")
            return
        }

        print("AutoResume: Starting automatic resume with background task...")

        // Request background execution time
        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "AutoResumeRecording") {
            print("AutoResume: Background task expired")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        Task {
            let success = await attemptStartNewSegmentWithRetry()

            if success {
                // Recording resumed — show brief "resumed" feedback in Live Activity
                updateLiveActivityToResumed()

                // After a few seconds, revert to normal minimal recording state
                try? await Task.sleep(nanoseconds: 3_500_000_000) // 3.5 seconds
                if isRecording, !isPausedForCall {
                    updateLiveActivityToRecording()
                }
            } else {
                // Auto-resume failed — fall back to manual "Tap to Resume"
                print("AutoResume: Failed, falling back to manual resume")
                updateLiveActivityToReadyToResume()
            }

            // End background task
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                print("AutoResume: Background task ended")
            }
        }
    }

    /// Start a NEW recording segment after phone call ends (manual resume from Live Activity button)
    /// This is the fallback path when auto-resume fails
    private func resumeRecordingAfterCall() {
        guard isRecording, isPausedForCall else {
            print("ManualResume: Cannot resume - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall)")
            return
        }

        print("ManualResume: Attempting to start new recording segment...")

        var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "ResumeRecording") {
            print("ManualResume: Background task expired")
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }

        Task {
            let success = await attemptStartNewSegmentWithRetry()

            if success {
                // Show brief "resumed" feedback then revert to recording
                updateLiveActivityToResumed()
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if isRecording, !isPausedForCall {
                    updateLiveActivityToRecording()
                }
            }

            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                print("ManualResume: Background task ended")
            }
        }
    }

    /// Attempts to restart the AVAudioEngine and open a new segment file
    /// With AVAudioEngine this is much more reliable than AVAudioRecorder — engine.start() works from background
    /// Returns true if recording was successfully resumed
    @discardableResult
    private func attemptStartNewSegmentWithRetry() async -> Bool {
        let maxRetries = 10
        let delayBetweenRetries: UInt64 = 300_000_000 // 0.3 seconds

        for attempt in 1...maxRetries {
            guard isRecording, isPausedForCall else {
                print("Retry: Cancelled - state changed")
                return false
            }

            guard let engine = audioEngine else {
                print("Retry: No engine available")
                return false
            }

            print("Retry: Engine restart attempt \(attempt)/\(maxRetries)")

            do {
                // Reactivate audio session
                try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

                // Check if input format changed (e.g., Bluetooth disconnected during call)
                let inputNode = engine.inputNode
                let currentFormat = inputNode.outputFormat(forBus: 0)

                // Open new file for this segment
                try openNewSegmentFile(format: currentFormat)

                // Restart engine — nodes and tap are still configured from startRecording()
                // This is the key advantage over AVAudioRecorder: engine.start() works from background
                try engine.start()

                isSuspendedForInterruption = false
                isPausedForCall = false
                recordingStartTime = Date()
                startDurationTimer()

                print("Retry: Engine restarted on attempt \(attempt), recording resumed!")
                return true
            } catch {
                print("Retry: Attempt \(attempt) failed: \(error.localizedDescription)")
            }

            if attempt < maxRetries {
                try? await Task.sleep(nanoseconds: delayBetweenRetries)
            }
        }

        print("Retry: Failed to restart engine after \(maxRetries) attempts")
        return false
    }
}

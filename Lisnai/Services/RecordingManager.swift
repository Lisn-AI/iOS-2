import Foundation
import AVFoundation
import Speech
import UIKit
import CallKit
import ActivityKit
import SwiftData

@MainActor
class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPausedForCall = false  // Tracks if recording is paused due to phone call
    @Published var recordingDuration = "00:00:00"
    @Published var transcription = ""
    @Published var summary = ""
    @Published var isProcessing = false

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

    // CallKit observer for detecting phone calls (more reliable than audio session interruption notifications)
    private let callObserver = CXCallObserver()

    // Live Activity for showing pause/resume UI in Dynamic Island
    private var recordingActivity: Activity<RecordingActivityAttributes>?

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
        print("Live Activity resume observer set up")
    }

    /// Handle resume request from Live Activity button tap (fallback manual resume)
    @objc private func handleLiveActivityResumeRequest() {
        print("Live Activity: Resume button tapped!")

        guard isRecording, isPausedForCall else {
            print("Live Activity: Cannot resume - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall)")
            return
        }

        // Request background execution time and attempt to resume
        // The resume flow will update the Live Activity to show "resumed" feedback
        resumeRecordingAfterCall()
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
                self?.audioWriteQueue.async {
                    try? self?.currentAudioFile?.write(from: buffer)
                }
            }

            try engine.start()

            isRecording = true
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
        // Stop engine and remove tap
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Close current audio file
        audioWriteQueue.sync {
            self.currentAudioFile = nil
        }

        isRecording = false
        isPausedForCall = false
        isSuspendedForInterruption = false
        durationTimer?.invalidate()
        durationTimer = nil

        print("Recording stopped with \(recordingSegments.count) segment(s)")

        // Process all segments
        if !recordingSegments.isEmpty {
            Task {
                await processRecordingSegments()
            }
        }

        // Reset for next recording
        elapsedTimeBeforePause = 0
        recordingStartTime = nil

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
    private func processRecordingSegments() async {
        isProcessing = true
        transcription = "Processing recording segments..."

        // Merge segments if there are multiple
        guard let finalURL = await mergeAudioSegments() else {
            transcription = "Error: No recording segments found"
            isProcessing = false
            return
        }

        lastRecordingURL = finalURL
        await processRecording(fileURL: finalURL)
    }

    private func processRecording(fileURL: URL) async {
        isProcessing = true
        transcription = "Transcribing and identifying speakers..."
        summary = ""

        // Calculate duration from elapsed time
        let totalDuration = elapsedTimeBeforePause
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

            // Step 4: Summarize with speaker context (disabled - requires iOS 26)
            // Apple Intelligence summarization is not available on iOS < 26
            // For now, we skip summarization and rely on backend processing
            var summaryText = ""
            // Summarization disabled - requires iOS 26 (Apple Intelligence)
            // if !labeledTranscript.isEmpty {
            //     print("Starting summarization...")
            //     summaryText = try await summarizationService.summarize(labeledTranscript)
            //     summary = summaryText
            //     print("Summary complete!")
            // }
            print("Summarization skipped (requires iOS 26)")

            // Step 5: Save to SwiftData
            await saveToSwiftData(
                date: date,
                duration: totalDuration,
                transcriptionText: labeledTranscript,
                summaryText: summaryText
            )

            // Step 6: Delete the audio file (we don't need it anymore)
            deleteAudioFile(at: fileURL)

        } catch {
            print("Processing error: \(error.localizedDescription)")
            transcription = "Error: \(error.localizedDescription)"
            summary = ""
        }

        isProcessing = false
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
        await sendTranscriptToBackend(transcriptionText)
    }

    /// Send transcript to the backend for AI processing
    /// Handles entity extraction, memory storage, intent classification, and action execution
    private func sendTranscriptToBackend(_ transcript: String) async {
        guard !transcript.isEmpty else {
            print("Backend: Skipping empty transcript")
            return
        }

        print("Backend: Sending transcript for processing...")

        do {
            let result = try await APIService.shared.processTranscript(transcript)

            print("Backend: Processing complete")
            print("  - Memory ID: \(result.memoryId)")
            print("  - Intent: \(result.intent.intent) (\(result.intent.confidence))")

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
            print("Backend: Failed to process transcript - \(error.localizedDescription)")
            // Non-critical error - local data is already saved
            // Could queue for retry when network is available
        }
    }

    /// Handle action result from backend processing
    private func handleActionResult(_ actionResult: ActionResult) async {
        if actionResult.permissionRequired {
            // Permission is needed - send a local notification
            print("Backend: Permission required for action")
            if let permissionId = actionResult.pendingPermissionId,
               let message = actionResult.permissionMessage {
                await requestPermissionNotification(permissionId: permissionId, message: message)
            }
        } else if actionResult.executed, let toolResult = actionResult.toolResult {
            // Action was executed successfully
            print("Backend: Action executed - \(toolResult.message)")

            // If there's an iOS deep link, we could open it
            if let deepLink = toolResult.iosDeepLink {
                print("Backend: iOS action available - \(deepLink)")
                // Store for later execution via ActionsView
            }
        } else if let error = actionResult.error {
            print("Backend: Action failed - \(error)")
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

        let attributes = RecordingActivityAttributes()
        let initialState = RecordingActivityAttributes.ContentState(
            state: .recording,  // Start with minimal "recording" state
            pausedAtDuration: "",
            message: "Recording"
        )

        do {
            recordingActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            print("Live Activity: Started in recording state (minimal)")
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
        guard let activity = recordingActivity else {
            return
        }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            print("Live Activity: Ended")
        }
        recordingActivity = nil
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
        guard isRecording, !isPausedForCall else {
            print("CallKit: Cannot pause - isRecording: \(isRecording), isPausedForCall: \(isPausedForCall)")
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

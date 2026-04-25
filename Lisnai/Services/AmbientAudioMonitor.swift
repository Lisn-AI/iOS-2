import Foundation
import AVFoundation
import BackgroundTasks
import UserNotifications

/// Monitors ambient audio levels via periodic BGTask samples.
/// When conversation-level sound is detected, prompts the user to start recording.
@MainActor
class AmbientAudioMonitor: ObservableObject {
    static let shared = AmbientAudioMonitor()

    static let taskIdentifier = "com.lisnai.ambient-audio-check"

    /// User toggle — persisted
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "ambientDetectionEnabled")
            if isEnabled {
                scheduleNextCheck()
            } else {
                cancelScheduledChecks()
            }
        }
    }

    /// dB threshold for "sounds like conversation" (AVAudioRecorder averagePower is negative, -160 = silence, 0 = max)
    private let conversationThresholdDB: Float = -30.0

    /// How long to sample audio (seconds)
    private let sampleDuration: TimeInterval = 4.0

    /// Minimum time between notifications (30 minutes)
    private let notificationCooldown: TimeInterval = 30 * 60

    /// Rotating notification copy — keeps prompts feeling fresh
    private let promptVariants: [(title: String, body: String)] = [
        ("Hear that? Sounds like a great conversation", "Tap to capture it with Lisn"),
        ("People talking nearby", "Don't miss this — tap to start recording"),
        ("Conversation detected", "Let Lisn remember this for you"),
        ("Something worth remembering?", "Lisn heard voices — tap to record"),
        ("Sounds lively around you", "Tap to start recording with Lisn"),
    ]

    /// Last time we sent a notification
    private var lastNotificationDate: Date? {
        get { UserDefaults.standard.object(forKey: "ambientLastNotification") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "ambientLastNotification") }
    }

    /// Track which prompt variant to use next
    private var promptIndex: Int {
        get { UserDefaults.standard.integer(forKey: "ambientPromptIndex") }
        set { UserDefaults.standard.set(newValue, forKey: "ambientPromptIndex") }
    }

    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "ambientDetectionEnabled")
    }

    // MARK: - BGTask Scheduling

    /// Register the background task handler. Call from AppDelegate didFinishLaunching.
    nonisolated func registerBGTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: true)
                return
            }
            Task { @MainActor in
                await AmbientAudioMonitor.shared.handleAmbientAudioCheck(processingTask)
            }
        }
    }

    /// Schedule the next background audio check
    func scheduleNextCheck() {
        let request = BGProcessingTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 min minimum
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[AmbientAudio] Scheduled next check in ~15 min")
        } catch {
            print("[AmbientAudio] Failed to schedule BGTask: \(error)")
        }
    }

    private func cancelScheduledChecks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.taskIdentifier)
        print("[AmbientAudio] Cancelled scheduled checks")
    }

    // MARK: - Audio Check

    /// Handle the background task
    func handleAmbientAudioCheck(_ task: BGProcessingTask) async {
        // Early exit if feature was disabled while task was pending
        guard isEnabled else {
            task.setTaskCompleted(success: true)
            return
        }

        // Set up expiration handler FIRST
        var expired = false
        task.expirationHandler = {
            expired = true
            task.setTaskCompleted(success: true) // Always report success to avoid iOS throttling
        }

        // Perform the check
        if !expired {
            _ = await performAudioCheck()
        }

        // Reschedule for next run AFTER work completes
        if isEnabled {
            scheduleNextCheck()
        }

        // Always report success — iOS throttles tasks that "fail"
        if !expired {
            task.setTaskCompleted(success: true)
        }
    }

    /// Perform a brief audio sample and check if conversation-level sound is present
    func performAudioCheck() async -> Bool {
        guard isEnabled else { return false }

        // Cooldown check
        if let last = lastNotificationDate,
           Date().timeIntervalSince(last) < notificationCooldown {
            print("[AmbientAudio] Within cooldown, skipping")
            return false
        }

        // Don't check if user is already recording — avoid audio session conflict
        if UserDefaults.standard.bool(forKey: "isCurrentlyRecording") {
            print("[AmbientAudio] Already recording, skipping")
            return false
        }

        // Sample audio
        let avgDB = await sampleAudioLevel()
        print("[AmbientAudio] Average dB: \(avgDB)")

        if avgDB > conversationThresholdDB {
            await sendRecordingPromptNotification()
            lastNotificationDate = Date()
            return true
        }

        return false
    }

    /// Record briefly and measure average power level
    private func sampleAudioLevel() async -> Float {
        // Double-check recording state right before touching audio session
        guard !UserDefaults.standard.bool(forKey: "isCurrentlyRecording") else {
            return -160.0
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ambient_check_\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.low.rawValue,
        ]

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true)
        } catch {
            print("[AmbientAudio] Audio session setup failed: \(error)")
            return -160.0
        }

        defer {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: tempURL)
        }

        guard let recorder = try? AVAudioRecorder(url: tempURL, settings: settings) else {
            print("[AmbientAudio] Failed to create recorder")
            return -160.0
        }

        recorder.isMeteringEnabled = true
        recorder.record()

        // Sample every 0.5s for sampleDuration
        let sampleCount = Int(sampleDuration / 0.5)
        var totalDB: Float = 0

        for _ in 0..<sampleCount {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            totalDB += power
        }

        recorder.stop()

        return sampleCount > 0 ? totalDB / Float(sampleCount) : -160.0
    }

    // MARK: - Notification

    private func sendRecordingPromptNotification() async {
        let variant = promptVariants[promptIndex % promptVariants.count]
        promptIndex += 1

        let content = UNMutableNotificationContent()
        content.title = variant.title
        content.body = variant.body
        content.sound = .default
        content.categoryIdentifier = NotificationService.Category.suggestion.rawValue

        let request = UNNotificationRequest(
            identifier: "ambient-recording-prompt",
            content: content,
            trigger: nil // immediate
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            print("[AmbientAudio] Sent recording prompt: \(variant.title)")
        } catch {
            print("[AmbientAudio] Failed to send notification: \(error)")
        }
    }
}

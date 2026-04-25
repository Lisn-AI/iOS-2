import UserNotifications

class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    private let sharedDefaults = UserDefaults(suiteName: "group.com.lisnai.shared")

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        let userInfo = request.content.userInfo

        // Queue data payloads for the main app to process on next launch
        if let syncType = userInfo["syncType"] as? String,
           let syncData = userInfo["syncData"] as? String {
            queuePayload(syncType: syncType, syncData: syncData)
        }

        // Deliver the notification content as-is
        if let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        // Deliver best attempt before system kills us
        if let contentHandler = contentHandler, let content = bestAttemptContent {
            contentHandler(content)
        }
    }

    // MARK: - Payload Queueing

    private func queuePayload(syncType: String, syncData: String) {
        guard let defaults = sharedDefaults else { return }

        let payload: [String: String] = [
            "syncType": syncType,
            "syncData": syncData,
            "queuedAt": ISO8601DateFormatter().string(from: Date()),
        ]

        var pending = defaults.array(forKey: "pendingSyncPayloads") as? [[String: String]] ?? []
        pending.append(payload)

        // Cap queue size to prevent unbounded growth
        if pending.count > 50 {
            pending = Array(pending.suffix(50))
        }

        defaults.set(pending, forKey: "pendingSyncPayloads")
    }
}

import Foundation
import EventKit
import UIKit
import MessageUI

/// Executes iOS native actions like creating reminders, calendar events, and email drafts
/// Uses EventKit for Reminders and Calendar, MFMailComposeViewController for email
@MainActor
class ActionExecutor: ObservableObject {
    static let shared = ActionExecutor()

    @Published var hasReminderAccess = false
    @Published var hasCalendarAccess = false
    @Published var canSendEmail = false
    @Published var error: String?
    @Published var pendingEmailAction: PendingAction?

    private let eventStore = EKEventStore()
    private let api = APIService.shared

    init() {
        checkPermissions()
    }

    // MARK: - Permission Handling

    /// Check current EventKit permissions and email capability
    func checkPermissions() {
        // Reminders permission
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        hasReminderAccess = reminderStatus == .fullAccess

        // Calendar permission
        let calendarStatus = EKEventStore.authorizationStatus(for: .event)
        hasCalendarAccess = calendarStatus == .fullAccess

        // Email capability (check if device can send email)
        canSendEmail = MFMailComposeViewController.canSendMail()
    }

    /// Request reminder access
    func requestReminderAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToReminders()
                hasReminderAccess = granted
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .reminder)
                hasReminderAccess = granted
                return granted
            }
        } catch {
            self.error = "Failed to request reminder access: \(error.localizedDescription)"
            return false
        }
    }

    /// Request calendar access
    func requestCalendarAccess() async -> Bool {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                hasCalendarAccess = granted
                return granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                hasCalendarAccess = granted
                return granted
            }
        } catch {
            self.error = "Failed to request calendar access: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Execute Actions

    /// Execute a suggested action directly (from accepted suggestions)
    func executeSuggestedAction(_ suggestedAction: SuggestedAction, suggestionId: String) async -> ActionExecutionResult {
        // Convert SuggestedAction to PendingAction format for unified execution
        let pendingAction = PendingAction(
            id: suggestionId,
            skill: suggestedAction.skill,
            tool: suggestedAction.tool,
            type: suggestedAction.tool,
            params: suggestedAction.params,
            status: "pending",
            createdAt: ISO8601DateFormatter().string(from: Date())
        )

        return await executeAction(pendingAction)
    }

    /// Execute an action from an approved permission
    func executePermissionAction(_ permission: PendingPermission) async -> ActionExecutionResult {
        print("[ActionExecutor] Executing permission action: \(permission.skill):\(permission.tool)")
        print("[ActionExecutor] Permission params: \(String(describing: permission.params))")

        // Convert PendingPermission to PendingAction format
        let params: [String: AnyCodable] = (permission.params ?? [:]).merging([
            "skill": AnyCodable(permission.skill),
            "tool": AnyCodable(permission.tool)
        ]) { _, new in new }

        let pendingAction = PendingAction(
            id: permission.id,
            skill: permission.skill,
            tool: permission.tool,
            type: permission.tool,
            params: params,
            status: "approved",
            createdAt: permission.createdAt
        )

        return await executeAction(pendingAction)
    }

    /// Normalize hallucinated skill names to registered ones
    nonisolated static func normalizeSkill(_ skill: String) -> String {
        switch skill {
        case "organization", "notes", "apple-notes":
            return "apple-notes"
        case "communication", "phone", "calls":
            return "messaging"
        case "reminder", "reminders", "apple-reminders":
            return "apple-reminders"
        case "calendar", "apple-calendar", "scheduling":
            return "apple-calendar"
        case "email-draft", "email":
            return "email-draft"
        default:
            return skill
        }
    }

    /// Normalize hallucinated tool names to registered ones
    nonisolated static func normalizeTool(_ tool: String, skill: String) -> String {
        switch tool {
        case "note", "create_note", "add_note", "write_note":
            return "create_note"
        case "phone", "call", "make_call", "phone_call", "dial":
            return "make_call"
        case "reminder", "create_reminder", "add_reminder", "set_reminder":
            return "create_reminder"
        case "calendar", "create_event", "add_event", "schedule_event", "create_calendar_event":
            return "create_event"
        case "email", "send_email", "compose_email", "draft_email",
             "create_email_draft", "intelligent_email_draft":
            return "send_email"
        case "message", "send_message", "sms", "text":
            return "send_message"
        default:
            return tool
        }
    }

    /// Execute an action based on its type
    func executeAction(_ action: PendingAction) async -> ActionExecutionResult {
        // Get tool type from params if available (broken into steps for Swift type-checker)
        let toolFromAction: String = action.tool?.lowercased() ?? ""
        let toolFromParams: String = action.params?["tool"]?.stringValue?.lowercased() ?? ""
        let toolFromType: String = (action.type ?? "").lowercased()
        let rawTool: String = !toolFromAction.isEmpty ? toolFromAction : (!toolFromParams.isEmpty ? toolFromParams : toolFromType)

        let skillFromAction: String = action.skill?.lowercased() ?? ""
        let skillFromParams: String = action.params?["skill"]?.stringValue?.lowercased() ?? ""
        let rawSkill: String = !skillFromAction.isEmpty ? skillFromAction : skillFromParams

        // Normalize hallucinated names to registered ones
        let skill = Self.normalizeSkill(rawSkill)
        let tool = Self.normalizeTool(rawTool, skill: skill)

        print("[ActionExecutor] Routing action — raw: \(rawSkill):\(rawTool) → normalized: \(skill):\(tool)")

        // Skill-based routing (using normalized names)
        switch skill {
        case "apple-reminders":
            return await createReminder(from: action)
        case "apple-calendar":
            return await createCalendarEvent(from: action)
        case "apple-notes":
            return await createNote(from: action)
        case "email-draft":
            return await prepareEmailDraft(from: action)
        case "messaging":
            switch tool {
            case "send_email":
                return await prepareEmailDraft(from: action)
            case "make_call":
                return await makePhoneCall(from: action)
            default:
                return await prepareMessage(from: action)
            }
        default:
            break
        }

        // Tool-based routing fallback (using normalized names)
        switch tool {
        case "create_reminder":
            return await createReminder(from: action)
        case "create_event":
            return await createCalendarEvent(from: action)
        case "create_note":
            return await createNote(from: action)
        case "make_call":
            return await makePhoneCall(from: action)
        case "send_email":
            return await prepareEmailDraft(from: action)
        case "send_message":
            return await prepareMessage(from: action)
        default:
            break
        }

        // Finally try to infer from action type
        switch (action.type ?? "").lowercased() {
        case "reminder", "task_reminder", "call_reminder":
            return await createReminder(from: action)
        case "calendar", "event", "event_reminder":
            return await createCalendarEvent(from: action)
        case "email", "follow_up":
            return await prepareEmailDraft(from: action)
        case "message":
            return await prepareMessage(from: action)
        case "call", "phone", "phone_call":
            return await makePhoneCall(from: action)
        case "note", "create_note":
            return await createNote(from: action)
        default:
            return ActionExecutionResult(
                success: false,
                message: "Unknown action type: \(action.displayType) (skill: \(skill), tool: \(tool))",
                nativeItemId: nil
            )
        }
    }

    // MARK: - Reminders

    /// Create a reminder from a pending action
    func createReminder(from action: PendingAction) async -> ActionExecutionResult {
        print("[ActionExecutor] Creating reminder from action: \(action.id)")
        print("[ActionExecutor] Params: \(action.params ?? [:])")

        // Check/request permission
        var hasAccess = hasReminderAccess
        if !hasAccess {
            print("[ActionExecutor] Requesting reminder access...")
            hasAccess = await requestReminderAccess()
        }
        guard hasAccess else {
            print("[ActionExecutor] Reminder access denied")
            return ActionExecutionResult(
                success: false,
                message: "Reminder access not granted. Please enable in Settings.",
                nativeItemId: nil
            )
        }
        print("[ActionExecutor] Reminder access granted")

        // Extract parameters - try multiple possible keys
        let title = extractParam(from: action, keys: ["title", "reminderTitle", "text", "name", "content"])

        guard let title = title, !title.isEmpty else {
            print("[ActionExecutor] Missing reminder title. Available params: \(action.params?.keys.joined(separator: ", ") ?? "none")")
            return ActionExecutionResult(
                success: false,
                message: "Missing reminder title",
                nativeItemId: nil
            )
        }
        print("[ActionExecutor] Creating reminder with title: \(title)")

        // Create reminder
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        // Set due date if provided (try both dueDateTime and dueDate)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var dueDate: Date?
        if let dueDateString = action.params?["dueDateTime"]?.stringValue {
            dueDate = dateFormatter.date(from: dueDateString)
            if dueDate == nil {
                // Try without fractional seconds
                dateFormatter.formatOptions = [.withInternetDateTime]
                dueDate = dateFormatter.date(from: dueDateString)
            }
        }
        if dueDate == nil, let dueDateString = action.params?["dueDate"]?.stringValue {
            dueDate = dateFormatter.date(from: dueDateString)
            if dueDate == nil {
                dateFormatter.formatOptions = [.withInternetDateTime]
                dueDate = dateFormatter.date(from: dueDateString)
            }
        }

        if let dueDate = dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )

            // Add alarm
            let alarm = EKAlarm(absoluteDate: dueDate)
            reminder.addAlarm(alarm)
        }

        // Set priority if provided
        if let priorityString = action.params?["priority"]?.stringValue {
            switch priorityString.lowercased() {
            case "high": reminder.priority = 1
            case "medium": reminder.priority = 5
            case "low": reminder.priority = 9
            default: break
            }
        }

        // Set notes if provided
        var notes = action.params?["notes"]?.stringValue ?? ""

        // Add person info to notes if available
        if let person = action.params?["person"]?.stringValue {
            if !notes.isEmpty {
                notes += "\n\n"
            }
            notes += "Related to: \(person)"
        }

        if !notes.isEmpty {
            reminder.notes = notes
        }

        // Handle recurrence if specified
        if let recurrence = action.params?["recurrence"]?.stringValue {
            let recurrenceRule: EKRecurrenceRule?
            switch recurrence.lowercased() {
            case "daily":
                recurrenceRule = EKRecurrenceRule(
                    recurrenceWith: .daily,
                    interval: 1,
                    end: nil
                )
            case "weekly":
                recurrenceRule = EKRecurrenceRule(
                    recurrenceWith: .weekly,
                    interval: 1,
                    end: nil
                )
            case "monthly":
                recurrenceRule = EKRecurrenceRule(
                    recurrenceWith: .monthly,
                    interval: 1,
                    end: nil
                )
            case "yearly":
                recurrenceRule = EKRecurrenceRule(
                    recurrenceWith: .yearly,
                    interval: 1,
                    end: nil
                )
            default:
                recurrenceRule = nil
            }

            if let rule = recurrenceRule {
                reminder.recurrenceRules = [rule]
            }
        }

        // Save reminder
        do {
            try eventStore.save(reminder, commit: true)

            // Mark action as completed on backend
            await completeActionOnBackend(action)

            return ActionExecutionResult(
                success: true,
                message: "Reminder '\(title)' created",
                nativeItemId: reminder.calendarItemIdentifier
            )
        } catch {
            return ActionExecutionResult(
                success: false,
                message: "Failed to create reminder: \(error.localizedDescription)",
                nativeItemId: nil
            )
        }
    }

    // MARK: - Calendar Events

    /// Create a calendar event from a pending action
    func createCalendarEvent(from action: PendingAction) async -> ActionExecutionResult {
        print("[ActionExecutor] Creating calendar event from action: \(action.id)")
        print("[ActionExecutor] Params: \(action.params ?? [:])")

        // Check/request permission
        var hasAccess = hasCalendarAccess
        if !hasAccess {
            print("[ActionExecutor] Requesting calendar access...")
            hasAccess = await requestCalendarAccess()
        }
        guard hasAccess else {
            print("[ActionExecutor] Calendar access denied")
            return ActionExecutionResult(
                success: false,
                message: "Calendar access not granted. Please enable in Settings.",
                nativeItemId: nil
            )
        }
        print("[ActionExecutor] Calendar access granted")

        // Extract title - try multiple possible keys
        let title = extractParam(from: action, keys: ["title", "eventTitle", "name", "summary"])

        guard let title = title, !title.isEmpty else {
            print("[ActionExecutor] Missing event title. Available params: \(action.params?.keys.joined(separator: ", ") ?? "none")")
            return ActionExecutionResult(
                success: false,
                message: "Missing event title",
                nativeItemId: nil
            )
        }

        // Extract start time - try multiple possible keys
        let startTimeString = extractParam(from: action, keys: ["startTime", "start", "startDate", "dateTime", "date"])

        // Parse the start date
        var startDate: Date?
        if let startTimeString = startTimeString {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            startDate = formatter.date(from: startTimeString)
            if startDate == nil {
                formatter.formatOptions = [.withInternetDateTime]
                startDate = formatter.date(from: startTimeString)
            }
        }

        // If no start time, default to 1 hour from now
        if startDate == nil {
            startDate = Date().addingTimeInterval(3600)
            print("[ActionExecutor] No start time provided, defaulting to 1 hour from now")
        }

        guard let startDate = startDate else {
            print("[ActionExecutor] Failed to parse start time")
            return ActionExecutionResult(
                success: false,
                message: "Missing or invalid start time",
                nativeItemId: nil
            )
        }
        print("[ActionExecutor] Creating event '\(title)' at \(startDate)")

        // Create event
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Set end date
        if let endTimeString = action.params?["endTime"]?.stringValue,
           let endDate = ISO8601DateFormatter().date(from: endTimeString) {
            event.endDate = endDate
        } else if let durationMinutes = action.params?["duration"]?.intValue {
            event.endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
        } else {
            // Default 1 hour duration
            event.endDate = startDate.addingTimeInterval(3600)
        }

        // Set location if provided
        if let location = action.params?["location"]?.stringValue {
            event.location = location
        }

        // Set notes if provided
        if let notes = action.params?["notes"]?.stringValue {
            event.notes = notes
        }

        // Add default alarm (15 minutes before)
        let alarm = EKAlarm(relativeOffset: -900)
        event.addAlarm(alarm)

        // Save event
        do {
            try eventStore.save(event, span: .thisEvent)

            // Mark action as completed on backend
            await completeActionOnBackend(action)

            return ActionExecutionResult(
                success: true,
                message: "Event '\(title)' created",
                nativeItemId: event.eventIdentifier
            )
        } catch {
            return ActionExecutionResult(
                success: false,
                message: "Failed to create event: \(error.localizedDescription)",
                nativeItemId: nil
            )
        }
    }

    // MARK: - Email Drafts

    /// Prepare an email draft - stores action and returns instructions to show mail composer
    func prepareEmailDraft(from action: PendingAction) async -> ActionExecutionResult {
        guard canSendEmail else {
            return ActionExecutionResult(
                success: false,
                message: "Email is not configured on this device. Please set up an email account in Settings.",
                nativeItemId: nil
            )
        }

        // Check if email address is missing
        if action.params?["needsEmail"]?.boolValue == true ||
           action.params?["needsEmail"]?.stringValue == "true" {
            // Store the action for later completion with email address
            self.pendingEmailAction = action
            return ActionExecutionResult(
                success: true,
                message: "Email address needed for \(action.params?["recipientName"]?.stringValue ?? "recipient")",
                nativeItemId: nil,
                requiresUserInput: .emailAddress
            )
        }

        // Get recipients
        var recipients: [String] = []
        if let toArray = action.params?["to"]?.value as? [Any] {
            recipients = toArray.compactMap { ($0 as? String) ?? (($0 as? AnyCodable)?.stringValue) }
        } else if let toEmail = action.params?["to"]?.stringValue {
            recipients = [toEmail]
        }

        guard !recipients.isEmpty else {
            return ActionExecutionResult(
                success: false,
                message: "No email recipient specified",
                nativeItemId: nil
            )
        }

        // Store the email details for the mail composer
        self.pendingEmailAction = action

        // Return success - the UI will show the mail composer
        return ActionExecutionResult(
            success: true,
            message: "Email draft ready - opening mail composer",
            nativeItemId: action.id,
            requiresUserInput: .mailComposer
        )
    }

    /// Get email draft details for showing mail composer
    func getEmailDraftDetails(from action: PendingAction) -> EmailDraftDetails? {
        var recipients: [String] = []
        if let toArray = action.params?["to"]?.value as? [Any] {
            recipients = toArray.compactMap { ($0 as? String) ?? (($0 as? AnyCodable)?.stringValue) }
        } else if let toEmail = action.params?["to"]?.stringValue {
            recipients = [toEmail]
        }

        let subject = action.params?["subject"]?.stringValue ?? ""
        let body = action.params?["body"]?.stringValue ?? ""

        var ccRecipients: [String] = []
        if let ccArray = action.params?["cc"]?.value as? [Any] {
            ccRecipients = ccArray.compactMap { ($0 as? String) ?? (($0 as? AnyCodable)?.stringValue) }
        }

        return EmailDraftDetails(
            recipients: recipients,
            ccRecipients: ccRecipients,
            subject: subject,
            body: body
        )
    }

    /// Complete email action after mail composer is dismissed
    func completeEmailAction(_ action: PendingAction, sent: Bool) async {
        if sent {
            await completeActionOnBackend(action)
        } else {
            // User cancelled - mark as cancelled on backend
            do {
                let result = ActionCompletionResult(
                    status: "cancelled",
                    result: "User cancelled email",
                    error: nil
                )
                _ = try await api.completeAction(actionId: action.id, result: result)
            } catch {
                print("Failed to mark email action as cancelled: \(error)")
            }
        }
        self.pendingEmailAction = nil
    }

    /// Add email address to pending action and execute
    func addEmailAndExecute(_ email: String) async -> ActionExecutionResult {
        guard let action = pendingEmailAction else {
            return ActionExecutionResult(
                success: false,
                message: "No pending email action",
                nativeItemId: nil
            )
        }

        // Create updated action with email
        var updatedParams = action.params ?? [:]
        updatedParams["to"] = AnyCodable([email])
        updatedParams["needsEmail"] = AnyCodable(false)

        let updatedAction = PendingAction(
            id: action.id,
            skill: action.skill,
            tool: action.tool,
            type: action.type,
            params: updatedParams,
            status: action.status,
            createdAt: action.createdAt
        )

        self.pendingEmailAction = updatedAction
        return ActionExecutionResult(
            success: true,
            message: "Email address added - ready to compose",
            nativeItemId: action.id,
            requiresUserInput: .mailComposer
        )
    }

    // MARK: - Messages

    /// Prepare a message - opens Messages app with pre-filled content
    func prepareMessage(from action: PendingAction) async -> ActionExecutionResult {
        guard let recipient = action.params?["recipient"]?.stringValue else {
            return ActionExecutionResult(
                success: false,
                message: "No message recipient specified",
                nativeItemId: nil
            )
        }

        let content = action.params?["content"]?.stringValue ?? ""

        // Create SMS URL
        var urlString = "sms:\(recipient)"
        if !content.isEmpty {
            if let encodedContent = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                urlString += "&body=\(encodedContent)"
            }
        }

        guard let url = URL(string: urlString) else {
            return ActionExecutionResult(
                success: false,
                message: "Could not create message URL",
                nativeItemId: nil
            )
        }

        // Open Messages app
        await UIApplication.shared.open(url)
        await completeActionOnBackend(action)

        return ActionExecutionResult(
            success: true,
            message: "Opening Messages to \(recipient)",
            nativeItemId: nil
        )
    }

    // MARK: - Phone Calls

    /// Initiate a phone call via tel:// URL scheme
    func makePhoneCall(from action: PendingAction) async -> ActionExecutionResult {
        let contact = extractParam(from: action, keys: ["contact", "phoneNumber", "number", "recipient", "person", "name"])

        guard let contact = contact, !contact.isEmpty else {
            return ActionExecutionResult(
                success: false,
                message: "No phone number or contact specified",
                nativeItemId: nil,
                requiresUserInput: .phoneNumber
            )
        }

        // Determine the call type
        let app = action.params?["app"]?.stringValue?.lowercased() ?? "phone"

        let urlScheme: String
        switch app {
        case "facetime":
            urlScheme = "facetime://\(contact)"
        case "facetime-audio":
            urlScheme = "facetime-audio://\(contact)"
        default:
            // Sanitize phone number for tel:// — keep digits, +, and *
            let sanitized = contact.filter { $0.isNumber || $0 == "+" || $0 == "*" || $0 == "#" }
            if sanitized.isEmpty {
                // Contact name rather than number — can't use tel://
                // Try to open Contacts search instead
                return ActionExecutionResult(
                    success: false,
                    message: "Cannot call '\(contact)' — please provide a phone number. You can find their number in Contacts and call from there.",
                    nativeItemId: nil
                )
            }
            urlScheme = "tel://\(sanitized)"
        }

        guard let url = URL(string: urlScheme) else {
            return ActionExecutionResult(
                success: false,
                message: "Could not create call URL",
                nativeItemId: nil
            )
        }

        guard UIApplication.shared.canOpenURL(url) else {
            return ActionExecutionResult(
                success: false,
                message: "This device cannot make phone calls",
                nativeItemId: nil
            )
        }

        await UIApplication.shared.open(url)
        await completeActionOnBackend(action)

        return ActionExecutionResult(
            success: true,
            message: "Calling \(contact)",
            nativeItemId: nil
        )
    }

    // MARK: - Notes

    /// Create a note and save directly to Apple Notes via UIActivityViewController.
    /// Shares a .txt file (more reliable with Notes than raw String).
    /// Presented from the top UIKit view controller to bypass SwiftUI sheet-nesting issues.
    func createNote(from action: PendingAction) async -> ActionExecutionResult {
        let title = action.params?["title"]?.stringValue ?? ""
        let content = extractParam(from: action, keys: ["content", "text", "body", "notes"]) ?? ""

        guard !title.isEmpty || !content.isEmpty else {
            return ActionExecutionResult(
                success: false,
                message: "Missing note content",
                nativeItemId: nil
            )
        }

        // Build note text — title on first line, blank line, then body
        var noteText = ""
        if !title.isEmpty { noteText += title + "\n\n" }
        noteText += content

        // Write to a .txt temp file — Notes imports .txt files directly into Quick Notes
        // This is more reliable than passing a raw String to UIActivityViewController
        let safeName = title.isEmpty ? "Note" : String(
            title
                .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
                .joined(separator: "_")
                .prefix(50)
        )
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension("txt")

        do {
            try noteText.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            // Fallback: present with raw string if file write fails
            print("[ActionExecutor] Could not write temp note file: \(error)")
        }

        // Wait for any sheet dismissal animations to complete before presenting UIKit VC.
        // Without this, topVC.present() silently fails when called mid-animation.
        try? await Task.sleep(nanoseconds: 600_000_000) // 600ms

        let presented = await MainActor.run { [tempURL, noteText] () -> Bool in
            guard let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive }),
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }),
                  let rootVC = window.rootViewController else {
                return false
            }

            // Walk to topmost non-dismissing view controller
            var topVC: UIViewController = rootVC
            while let next = topVC.presentedViewController, !next.isBeingDismissed {
                topVC = next
            }

            // Use the .txt file if it exists, fall back to raw string
            let activityItems: [Any]
            if FileManager.default.fileExists(atPath: tempURL.path) {
                activityItems = [tempURL]
            } else {
                activityItems = [noteText]
            }

            let activityVC = UIActivityViewController(
                activityItems: activityItems,
                applicationActivities: nil
            )

            activityVC.completionWithItemsHandler = { [weak self] _, completed, _, _ in
                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
                if completed {
                    Task { await self?.completeActionOnBackend(action) }
                }
            }

            // iPad popover source (prevents crash on iPad)
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(
                    x: topVC.view.bounds.midX,
                    y: topVC.view.bounds.midY,
                    width: 0, height: 0
                )
                popover.permittedArrowDirections = []
            }

            topVC.present(activityVC, animated: true)
            return true
        }

        guard presented else {
            return ActionExecutionResult(
                success: false,
                message: "Could not open share sheet",
                nativeItemId: nil
            )
        }

        return ActionExecutionResult(
            success: true,
            message: "Tap 'Notes' in the share sheet to save",
            nativeItemId: nil
        )
    }

    // MARK: - Deep Link Handling

    /// Handle a deep link from the backend
    /// Format: lisnai://action/{type}/{actionId}
    func handleDeepLink(_ url: URL) async -> ActionExecutionResult? {
        guard url.scheme == "lisnai",
              url.host == "action",
              url.pathComponents.count >= 3 else {
            return nil
        }

        let _ = url.pathComponents[1]
        let actionId = url.pathComponents[2]

        // Fetch action details from backend
        do {
            let response = try await api.getPendingActions()
            guard let action = response.actions.first(where: { $0.id == actionId }) else {
                return ActionExecutionResult(
                    success: false,
                    message: "Action not found: \(actionId)",
                    nativeItemId: nil
                )
            }

            return await executeAction(action)
        } catch {
            return ActionExecutionResult(
                success: false,
                message: "Failed to fetch action: \(error.localizedDescription)",
                nativeItemId: nil
            )
        }
    }

    // MARK: - Helpers

    /// Helper to extract the first non-nil, non-empty string param from a list of keys
    private func extractParam(from action: PendingAction, keys: [String]) -> String? {
        for key in keys {
            if let value = action.params?[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func completeActionOnBackend(_ action: PendingAction) async {
        do {
            let result = ActionCompletionResult(
                status: "completed",
                result: "Created via iOS EventKit",
                error: nil
            )
            _ = try await api.completeAction(actionId: action.id, result: result)
            // Notify Actions page to refresh (removes completed actions)
            NotificationCenter.default.post(name: .actionCompleted, object: nil, userInfo: ["actionId": action.id])
        } catch {
            print("Failed to mark action as completed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Result Types

/// What kind of user input is required
enum UserInputRequired {
    case none
    case emailAddress      // Need to ask for email address
    case mailComposer      // Need to show mail composer
    case phoneNumber       // Need to ask for phone number
}

struct ActionExecutionResult {
    let success: Bool
    let message: String
    let nativeItemId: String?
    var requiresUserInput: UserInputRequired = .none

    init(success: Bool, message: String, nativeItemId: String?, requiresUserInput: UserInputRequired = .none) {
        self.success = success
        self.message = message
        self.nativeItemId = nativeItemId
        self.requiresUserInput = requiresUserInput
    }
}

/// Details for email draft composition
struct EmailDraftDetails {
    let recipients: [String]
    let ccRecipients: [String]
    let subject: String
    let body: String
}

// MARK: - Deep Link Registration

extension ActionExecutor {
    /// Register URL scheme handler in SceneDelegate or App
    static func registerURLHandler() {
        // This would be called from the App's onOpenURL modifier
        // Example usage in LisnaiApp.swift:
        // .onOpenURL { url in
        //     Task {
        //         await ActionExecutor.shared.handleDeepLink(url)
        //     }
        // }
    }
}

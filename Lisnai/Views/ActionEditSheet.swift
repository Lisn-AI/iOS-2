import SwiftUI

// MARK: - Action Form Type

enum ActionFormType {
    case reminder, calendar, message, call, email, note

    static func from(_ action: PendingAction) -> ActionFormType {
        let rawSkill = (action.skill ?? action.params?["skill"]?.stringValue ?? "").lowercased()
        let rawTool = (action.tool ?? action.params?["tool"]?.stringValue ?? action.type ?? "").lowercased()

        let skill = ActionExecutor.normalizeSkill(rawSkill)
        let tool = ActionExecutor.normalizeTool(rawTool, skill: skill)

        // Skill-based routing first
        switch skill {
        case "apple-reminders":
            return .reminder
        case "apple-calendar":
            return .calendar
        case "apple-notes":
            return .note
        case "email-draft":
            return .email
        case "messaging":
            switch tool {
            case "send_email": return .email
            case "make_call": return .call
            default: return .message
            }
        default:
            break
        }

        // Tool-based routing fallback
        switch tool {
        case "create_reminder": return .reminder
        case "create_event": return .calendar
        case "create_note": return .note
        case "make_call": return .call
        case "send_email": return .email
        case "send_message": return .message
        default: break
        }

        // Infer from type
        switch (action.type ?? "").lowercased() {
        case "reminder", "task_reminder", "call_reminder": return .reminder
        case "calendar", "event", "event_reminder": return .calendar
        case "email", "follow_up": return .email
        case "message": return .message
        case "call", "phone", "phone_call": return .call
        case "note", "create_note": return .note
        default: return .reminder
        }
    }

    var icon: String {
        switch self {
        case .reminder: return "bell.fill"
        case .calendar: return "calendar"
        case .message: return "message.fill"
        case .call: return "phone.fill"
        case .email: return "envelope.fill"
        case .note: return "note.text"
        }
    }

    var title: String {
        switch self {
        case .reminder: return "Edit Reminder"
        case .calendar: return "Edit Event"
        case .message: return "Edit Message"
        case .call: return "Edit Call"
        case .email: return "Edit Email"
        case .note: return "Edit Note"
        }
    }

    var accentColor: Color {
        switch self {
        case .reminder: return LisnColors.warning
        case .calendar: return .cyan
        case .message: return LisnColors.success
        case .call: return LisnColors.success
        case .email: return LisnColors.accent
        case .note: return .orange
        }
    }
}

// MARK: - Action Edit Model

@MainActor
class ActionEditModel: ObservableObject {
    let formType: ActionFormType
    let originalAction: PendingAction

    // Reminder fields
    @Published var title: String = ""
    @Published var hasDueDate: Bool = false
    @Published var dueDate: Date = Date().addingTimeInterval(3600)
    @Published var priority: String = "None"
    @Published var notes: String = ""
    @Published var person: String = ""
    @Published var recurrence: String = "None"

    // Calendar fields
    @Published var startDate: Date = Date().addingTimeInterval(3600)
    @Published var endDate: Date = Date().addingTimeInterval(7200)
    @Published var location: String = ""

    // Message / Call fields
    @Published var recipient: String = ""
    @Published var content: String = ""
    @Published var originalContactName: String = ""
    @Published var callApp: String = "Phone"

    // Email fields
    @Published var emailTo: String = ""
    @Published var emailCc: String = ""
    @Published var emailSubject: String = ""
    @Published var emailBody: String = ""

    static let priorities = ["None", "Low", "Medium", "High"]
    static let recurrences = ["None", "Daily", "Weekly", "Monthly", "Yearly"]
    static let callApps = ["Phone", "FaceTime", "FaceTime Audio"]

    init(action: PendingAction) {
        self.originalAction = action
        self.formType = ActionFormType.from(action)

        let params = action.params ?? [:]

        switch formType {
        case .reminder:
            title = Self.firstParam(params, keys: ["title", "reminderTitle", "text", "name", "content"])
            notes = params["notes"]?.stringValue ?? ""
            person = params["person"]?.stringValue ?? ""

            if let p = params["priority"]?.stringValue?.capitalized,
               Self.priorities.contains(p) {
                priority = p
            }

            if let r = params["recurrence"]?.stringValue?.capitalized,
               Self.recurrences.contains(r) {
                recurrence = r
            }

            // Parse due date
            let dueDateStr = Self.firstParam(params, keys: ["dueDateTime", "dueDate"])
            if !dueDateStr.isEmpty, let date = Self.parseISO8601(dueDateStr) {
                hasDueDate = true
                dueDate = date
            }

        case .calendar:
            title = Self.firstParam(params, keys: ["title", "eventTitle", "name", "summary"])
            location = params["location"]?.stringValue ?? ""
            notes = params["notes"]?.stringValue ?? ""

            let startStr = Self.firstParam(params, keys: ["startTime", "start", "startDate", "dateTime", "date"])
            if !startStr.isEmpty, let date = Self.parseISO8601(startStr) {
                startDate = date
            }

            let endStr = Self.firstParam(params, keys: ["endTime", "end", "endDate"])
            if !endStr.isEmpty, let date = Self.parseISO8601(endStr) {
                endDate = date
            } else if let durationMinutes = params["duration"]?.intValue {
                endDate = startDate.addingTimeInterval(TimeInterval(durationMinutes * 60))
            } else {
                endDate = startDate.addingTimeInterval(3600)
            }

        case .message:
            let raw: String = params["recipient"]?.stringValue ?? ""
            if Self.hasDigits(raw) {
                recipient = raw
            } else if !raw.isEmpty {
                originalContactName = raw
                recipient = ""
            }
            content = params["content"]?.stringValue ?? ""

        case .call:
            let raw = Self.firstParam(params, keys: ["contact", "phoneNumber", "number", "recipient", "person", "name"])
            if Self.hasDigits(raw) {
                recipient = raw
            } else if !raw.isEmpty {
                originalContactName = raw
                recipient = ""
            }

            if let app = params["app"]?.stringValue {
                switch app.lowercased() {
                case "facetime": callApp = "FaceTime"
                case "facetime-audio": callApp = "FaceTime Audio"
                default: callApp = "Phone"
                }
            }

        case .email:
            if let toArray = params["to"]?.value as? [Any] {
                let mapped: [String] = toArray.compactMap { item in
                    (item as? String) ?? (item as? AnyCodable)?.stringValue
                }
                emailTo = mapped.joined(separator: ", ")
            } else {
                emailTo = params["to"]?.stringValue ?? ""
            }
            if let ccArray = params["cc"]?.value as? [Any] {
                let mapped: [String] = ccArray.compactMap { item in
                    (item as? String) ?? (item as? AnyCodable)?.stringValue
                }
                emailCc = mapped.joined(separator: ", ")
            } else {
                emailCc = params["cc"]?.stringValue ?? ""
            }
            emailSubject = params["subject"]?.stringValue ?? ""
            emailBody = params["body"]?.stringValue ?? ""

        case .note:
            title = params["title"]?.stringValue ?? ""
            content = Self.firstParam(params, keys: ["content", "text", "body", "notes"])
        }
    }

    // MARK: - Validation

    var canConfirm: Bool {
        switch formType {
        case .reminder:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .calendar:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
        case .message:
            return Self.hasDigits(recipient)
        case .call:
            return Self.hasDigits(recipient)
        case .email:
            return Self.isValidEmail(emailTo.trimmingCharacters(in: .whitespaces))
        case .note:
            return !title.trimmingCharacters(in: .whitespaces).isEmpty
                || !content.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var contactWarning: String? {
        guard !originalContactName.isEmpty else { return nil }
        switch formType {
        case .message:
            if !Self.hasDigits(recipient) {
                return "Enter a phone number for \(originalContactName)"
            }
        case .call:
            if !Self.hasDigits(recipient) {
                return "Enter a phone number for \(originalContactName)"
            }
        default:
            break
        }
        return nil
    }

    // MARK: - Build Updated Action

    func buildUpdatedAction() -> PendingAction {
        var params = originalAction.params ?? [:]

        switch formType {
        case .reminder:
            params["title"] = AnyCodable(title)
            if hasDueDate {
                params["dueDateTime"] = AnyCodable(Self.formatISO8601(dueDate))
            } else {
                params.removeValue(forKey: "dueDateTime")
                params.removeValue(forKey: "dueDate")
            }
            params["priority"] = priority == "None" ? nil : AnyCodable(priority.lowercased())
            params["notes"] = notes.isEmpty ? nil : AnyCodable(notes)
            params["person"] = person.isEmpty ? nil : AnyCodable(person)
            params["recurrence"] = recurrence == "None" ? nil : AnyCodable(recurrence.lowercased())

        case .calendar:
            params["title"] = AnyCodable(title)
            params["startTime"] = AnyCodable(Self.formatISO8601(startDate))
            params["endTime"] = AnyCodable(Self.formatISO8601(endDate))
            params["location"] = location.isEmpty ? nil : AnyCodable(location)
            params["notes"] = notes.isEmpty ? nil : AnyCodable(notes)

        case .message:
            params["recipient"] = AnyCodable(recipient)
            params["content"] = content.isEmpty ? nil : AnyCodable(content)

        case .call:
            params["contact"] = AnyCodable(recipient)
            let appValue: String
            switch callApp {
            case "FaceTime": appValue = "facetime"
            case "FaceTime Audio": appValue = "facetime-audio"
            default: appValue = "phone"
            }
            params["app"] = AnyCodable(appValue)

        case .email:
            let toList = emailTo.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            params["to"] = AnyCodable(toList)
            let ccList = emailCc.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            params["cc"] = ccList.isEmpty ? nil : AnyCodable(ccList)
            params["subject"] = emailSubject.isEmpty ? nil : AnyCodable(emailSubject)
            params["body"] = emailBody.isEmpty ? nil : AnyCodable(emailBody)
            params["needsEmail"] = AnyCodable(false)

        case .note:
            params["title"] = title.isEmpty ? nil : AnyCodable(title)
            params["content"] = content.isEmpty ? nil : AnyCodable(content)
        }

        // Remove nil values
        params = params.compactMapValues { $0 }

        return PendingAction(
            id: originalAction.id,
            skill: originalAction.skill,
            tool: originalAction.tool,
            type: originalAction.type,
            params: params,
            status: originalAction.status,
            createdAt: originalAction.createdAt
        )
    }

    // MARK: - Helpers

    /// Returns the first non-empty string value from params matching any of the given keys
    private static func firstParam(_ params: [String: AnyCodable], keys: [String]) -> String {
        for key in keys {
            if let value = params[key]?.stringValue, !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func hasDigits(_ string: String) -> Bool {
        string.contains(where: { $0.isNumber })
    }

    private static func isValidEmail(_ email: String) -> Bool {
        let regex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let predicate = NSPredicate(format: "SELF MATCHES %@", regex)
        return predicate.evaluate(with: email)
    }
}

// MARK: - Action Edit Sheet

struct ActionEditSheet: View {
    let action: PendingAction
    let onConfirm: (PendingAction) -> Void
    let onCancel: () -> Void

    @StateObject private var model: ActionEditModel
    @Environment(\.dismiss) private var dismiss

    init(action: PendingAction, onConfirm: @escaping (PendingAction) -> Void, onCancel: @escaping () -> Void) {
        self.action = action
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._model = StateObject(wrappedValue: ActionEditModel(action: action))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LisnSpacing.xl) {
                    // Header
                    headerSection

                    // Form fields
                    GlassCard {
                        formFields
                    }

                    // Buttons
                    buttonSection
                }
                .padding()
            }
            .background(LisnColors.bgPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: LisnSpacing.sm) {
            Circle()
                .fill(model.formType.accentColor.opacity(0.12))
                .frame(width: 64, height: 64)
                .overlay {
                    Image(systemName: model.formType.icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(model.formType.accentColor)
                }

            Text(model.formType.title)
                .font(LisnFont.titleLarge())
                .fontWeight(.semibold)
                .foregroundColor(LisnColors.textPrimary)

            Text("Review and edit before executing")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
        }
        .padding(.top, LisnSpacing.sm)
    }

    // MARK: - Form Fields

    @ViewBuilder
    private var formFields: some View {
        switch model.formType {
        case .reminder:
            ReminderFormFields(model: model)
        case .calendar:
            CalendarFormFields(model: model)
        case .message:
            MessageFormFields(model: model)
        case .call:
            CallFormFields(model: model)
        case .email:
            EmailFormFields(model: model)
        case .note:
            NoteFormFields(model: model)
        }
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: LisnSpacing.sm) {
            Button(action: {
                let edited = model.buildUpdatedAction()
                onConfirm(edited)
            }) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Confirm")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(model.canConfirm ? LisnColors.accent : Color.gray)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
            .disabled(!model.canConfirm)

            Button(action: {
                onCancel()
            }) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(LisnColors.bgSecondary)
                    .foregroundColor(LisnColors.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
        }
    }
}

// MARK: - Reminder Form Fields

private struct ReminderFormFields: View {
    @ObservedObject var model: ActionEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            FormField(label: "Title") {
                TextField("Reminder title", text: $model.title)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Due Date", isOn: $model.hasDueDate)
                .font(LisnFont.bodyMedium())
                .fontWeight(.medium)
                .tint(LisnColors.accent)

            if model.hasDueDate {
                DatePicker("Due", selection: $model.dueDate)
                    .font(LisnFont.bodyMedium())
            }

            FormField(label: "Priority") {
                Picker("Priority", selection: $model.priority) {
                    ForEach(ActionEditModel.priorities, id: \.self) { p in
                        Text(p).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            FormField(label: "Notes") {
                TextField("Optional notes", text: $model.notes)
                    .textFieldStyle(.roundedBorder)
            }

            FormField(label: "Person") {
                TextField("Related person", text: $model.person)
                    .textFieldStyle(.roundedBorder)
            }

            FormField(label: "Recurrence") {
                Picker("Recurrence", selection: $model.recurrence) {
                    ForEach(ActionEditModel.recurrences, id: \.self) { r in
                        Text(r).tag(r)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

// MARK: - Calendar Form Fields

private struct CalendarFormFields: View {
    @ObservedObject var model: ActionEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            FormField(label: "Title") {
                TextField("Event title", text: $model.title)
                    .textFieldStyle(.roundedBorder)
            }

            DatePicker("Start", selection: $model.startDate)
                .font(LisnFont.bodyMedium())
                .fontWeight(.medium)

            DatePicker("End", selection: $model.endDate)
                .font(LisnFont.bodyMedium())
                .fontWeight(.medium)

            FormField(label: "Location") {
                TextField("Optional location", text: $model.location)
                    .textFieldStyle(.roundedBorder)
            }

            FormField(label: "Notes") {
                TextField("Optional notes", text: $model.notes)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
}

// MARK: - Message Form Fields

private struct MessageFormFields: View {
    @ObservedObject var model: ActionEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            FormField(label: "Recipient") {
                TextField("Phone number", text: $model.recipient)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
            }

            if let warning = model.contactWarning {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(LisnColors.warning)
                        .font(.system(size: 14))
                    Text(warning)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.warning)
                }
            }

            FormField(label: "Message") {
                TextEditor(text: $model.content)
                    .frame(minHeight: 80)
                    .font(LisnFont.bodyMedium())
                    .padding(LisnSpacing.xs)
                    .background(LisnColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous)
                            .stroke(LisnColors.borderSubtle, lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Call Form Fields

private struct CallFormFields: View {
    @ObservedObject var model: ActionEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            FormField(label: "Contact") {
                TextField("Phone number", text: $model.recipient)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.phonePad)
            }

            if let warning = model.contactWarning {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(LisnColors.warning)
                        .font(.system(size: 14))
                    Text(warning)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.warning)
                }
            }

            FormField(label: "Call Type") {
                Picker("App", selection: $model.callApp) {
                    ForEach(ActionEditModel.callApps, id: \.self) { app in
                        Text(app).tag(app)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Email Form Fields

private struct EmailFormFields: View {
    @ObservedObject var model: ActionEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            FormField(label: "To") {
                TextField("email@example.com", text: $model.emailTo)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            FormField(label: "CC") {
                TextField("Optional CC", text: $model.emailCc)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
            }

            FormField(label: "Subject") {
                TextField("Email subject", text: $model.emailSubject)
                    .textFieldStyle(.roundedBorder)
            }

            FormField(label: "Body") {
                TextEditor(text: $model.emailBody)
                    .frame(minHeight: 120)
                    .font(LisnFont.bodyMedium())
                    .padding(LisnSpacing.xs)
                    .background(LisnColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous)
                            .stroke(LisnColors.borderSubtle, lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Note Form Fields

private struct NoteFormFields: View {
    @ObservedObject var model: ActionEditModel

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            FormField(label: "Title") {
                TextField("Note title", text: $model.title)
                    .textFieldStyle(.roundedBorder)
            }

            FormField(label: "Content") {
                TextEditor(text: $model.content)
                    .frame(minHeight: 150)
                    .font(LisnFont.bodyMedium())
                    .padding(LisnSpacing.xs)
                    .background(LisnColors.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous)
                            .stroke(LisnColors.borderSubtle, lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Form Field Helper

private struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xxs) {
            Text(label)
                .font(LisnFont.caption())
                .fontWeight(.medium)
                .foregroundColor(LisnColors.textSecondary)
            content
        }
    }
}

import SwiftUI
import MessageUI

/// View for managing pending actions and permission requests
struct ActionsView: View {
    @StateObject private var viewModel = ActionsViewModel()
    @State private var selectedPermission: PendingPermission?
    @State private var showPermissionSheet = false
    @State private var showSuggestionsView = false
    @State private var showMailComposer = false
    @State private var showEmailInputSheet = false
    @State private var emailInputText = ""
    @State private var pendingEmailAction: PendingAction?
    @State private var emailDraftDetails: EmailDraftDetails?

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.pendingActions.isEmpty && viewModel.pendingPermissions.isEmpty && viewModel.suggestions.isEmpty {
                    ProgressView("Loading...")
                } else if viewModel.pendingActions.isEmpty && viewModel.pendingPermissions.isEmpty && viewModel.suggestions.isEmpty {
                    emptyStateView
                } else {
                    contentList
                }
            }
            .navigationTitle("Actions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadData()
            }
            .sheet(isPresented: $showPermissionSheet) {
                if let permission = selectedPermission {
                    PermissionApprovalSheet(
                        permission: permission,
                        onApprove: { scope, createRule in
                            Task {
                                await viewModel.approvePermission(permission, scope: scope, createRule: createRule)
                                showPermissionSheet = false
                                selectedPermission = nil
                            }
                        },
                        onDeny: {
                            Task {
                                await viewModel.denyPermission(permission)
                                showPermissionSheet = false
                                selectedPermission = nil
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $showEmailInputSheet) {
                EmailInputSheet(
                    recipientName: pendingEmailAction?.params["recipientName"]?.stringValue ?? "recipient",
                    emailText: $emailInputText,
                    onSubmit: { email in
                        Task {
                            await handleEmailAddressSubmitted(email)
                        }
                    },
                    onCancel: {
                        showEmailInputSheet = false
                        pendingEmailAction = nil
                    }
                )
            }
            .sheet(isPresented: $showMailComposer) {
                if let details = emailDraftDetails, MFMailComposeViewController.canSendMail() {
                    MailComposeView(
                        recipients: details.recipients,
                        ccRecipients: details.ccRecipients,
                        subject: details.subject,
                        body: details.body
                    ) { result in
                        Task {
                            await handleMailComposerResult(result)
                        }
                    }
                }
            }
            .navigationDestination(isPresented: $showSuggestionsView) {
                SuggestionsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSuggestions)) { _ in
                showSuggestionsView = true
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Email Handling

    private func handleEmailAddressSubmitted(_ email: String) async {
        showEmailInputSheet = false
        guard let action = pendingEmailAction else { return }

        let executor = ActionExecutor.shared
        let result = await executor.addEmailAndExecute(email)

        if result.success && result.requiresUserInput == .mailComposer {
            if let details = executor.getEmailDraftDetails(from: executor.pendingEmailAction!) {
                emailDraftDetails = details
                showMailComposer = true
            }
        } else if !result.success {
            viewModel.error = result.message
        }

        pendingEmailAction = nil
    }

    private func handleMailComposerResult(_ result: MFMailComposeResult) async {
        let sent = result == .sent
        let executor = ActionExecutor.shared

        if let action = executor.pendingEmailAction {
            await executor.completeEmailAction(action, sent: sent)

            if sent {
                // Remove from list
                viewModel.pendingActions.removeAll { $0.id == action.id }
            }
        }

        showMailComposer = false
        emailDraftDetails = nil
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Pending Actions",
            systemImage: "checkmark.circle",
            description: Text("Actions from your conversations will appear here")
        )
    }

    // MARK: - Content List

    private var contentList: some View {
        List {
            // Proactive Suggestions Section
            if !viewModel.suggestions.isEmpty {
                Section {
                    ForEach(viewModel.suggestions.prefix(3)) { suggestion in
                        SuggestionPreviewRow(suggestion: suggestion)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showSuggestionsView = true
                            }
                    }
                    if viewModel.suggestions.count > 3 {
                        Button(action: { showSuggestionsView = true }) {
                            HStack {
                                Text("View all \(viewModel.suggestions.count) suggestions")
                                    .foregroundColor(.blue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Label("Suggestions", systemImage: "lightbulb.fill")
                }
            }

            // Permission Requests Section
            if !viewModel.pendingPermissions.isEmpty {
                Section {
                    ForEach(viewModel.pendingPermissions) { permission in
                        PermissionRequestRow(permission: permission)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPermission = permission
                                showPermissionSheet = true
                            }
                    }
                } header: {
                    Label("Needs Approval", systemImage: "lock.shield")
                }
            }

            // Pending Actions Section
            if !viewModel.pendingActions.isEmpty {
                Section {
                    ForEach(viewModel.pendingActions) { action in
                        PendingActionRow(action: action) {
                            Task {
                                let result = await viewModel.executeAction(action)

                                // Handle different user input requirements
                                switch result.requiresUserInput {
                                case .emailAddress:
                                    pendingEmailAction = action
                                    emailInputText = ""
                                    showEmailInputSheet = true

                                case .mailComposer:
                                    if let details = ActionExecutor.shared.getEmailDraftDetails(from: ActionExecutor.shared.pendingEmailAction ?? action) {
                                        emailDraftDetails = details
                                        showMailComposer = true
                                    }

                                case .phoneNumber:
                                    // TODO: Implement phone number input
                                    break

                                case .none:
                                    break
                                }
                            }
                        }
                    }
                } header: {
                    Label("Ready to Execute", systemImage: "bolt.fill")
                }
            }
        }
    }
}

// MARK: - Suggestion Preview Row

struct SuggestionPreviewRow: View {
    let suggestion: ProactiveSuggestion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: typeIcon)
                .font(.title3)
                .foregroundColor(typeColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text(suggestion.body)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var typeIcon: String {
        switch suggestion.type {
        case "call_reminder": return "phone.fill"
        case "follow_up": return "arrow.turn.up.right"
        case "task_reminder": return "checkmark.circle"
        case "pattern_insight": return "chart.line.uptrend.xyaxis"
        case "connection_prompt": return "person.2.fill"
        case "event_reminder": return "calendar"
        default: return "lightbulb.fill"
        }
    }

    private var typeColor: Color {
        switch suggestion.type {
        case "call_reminder": return .green
        case "follow_up": return .blue
        case "task_reminder": return .orange
        case "pattern_insight": return .purple
        case "connection_prompt": return .pink
        case "event_reminder": return .cyan
        default: return .yellow
        }
    }
}

// MARK: - Permission Request Row

struct PermissionRequestRow: View {
    let permission: PendingPermission

    var body: some View {
        HStack(spacing: 12) {
            // Risk indicator
            Circle()
                .fill(riskColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(permission.displayTitle)
                    .font(.headline)

                Text(permission.displayDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                HStack {
                    Label(permission.skill, systemImage: "app.fill")
                        .font(.caption)
                        .foregroundColor(.blue)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(permission.tool)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var riskColor: Color {
        switch permission.displayRisk?.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .green
        }
    }
}

// MARK: - Pending Action Row

struct PendingActionRow: View {
    let action: PendingAction
    let onExecute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Action type icon
            Image(systemName: actionIcon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(actionTitle)
                    .font(.headline)

                Text(actionDescription)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)

                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onExecute) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundColor(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var actionIcon: String {
        // Check skill/tool first for more accurate icon
        let skill = action.params["skill"]?.stringValue?.lowercased() ?? ""
        let tool = action.params["tool"]?.stringValue?.lowercased() ?? ""

        switch (skill, tool) {
        case ("email-draft", _), ("messaging", "send_email"):
            return "envelope.fill"
        case ("apple-reminders", _), (_, "create_reminder"):
            return "bell.fill"
        case ("apple-calendar", _), (_, "create_event"):
            return "calendar"
        case ("apple-notes", _), (_, "create_note"):
            return "note.text"
        case ("messaging", "send_message"):
            return "message.fill"
        default:
            switch action.type.lowercased() {
            case "reminder": return "bell.fill"
            case "calendar": return "calendar"
            case "note": return "note.text"
            case "message": return "message.fill"
            case "email": return "envelope.fill"
            default: return "bolt.fill"
            }
        }
    }

    private var actionTitle: String {
        // Check skill/tool first for more accurate title
        let skill = action.params["skill"]?.stringValue?.lowercased() ?? ""
        let tool = action.params["tool"]?.stringValue?.lowercased() ?? ""

        switch (skill, tool) {
        case ("email-draft", _), ("messaging", "send_email"):
            return "Compose Email"
        case ("apple-reminders", _), (_, "create_reminder"):
            return "Create Reminder"
        case ("apple-calendar", _), (_, "create_event"):
            return "Create Event"
        case ("apple-notes", _), (_, "create_note"):
            return "Create Note"
        case ("messaging", "send_message"):
            return "Send Message"
        default:
            switch action.type.lowercased() {
            case "reminder": return "Create Reminder"
            case "calendar": return "Create Event"
            case "note": return "Create Note"
            case "message": return "Send Message"
            case "email": return "Compose Email"
            default: return action.type.capitalized
            }
        }
    }

    private var actionDescription: String {
        // For emails, show subject
        if let subject = action.params["subject"]?.stringValue, !subject.isEmpty {
            if let recipientName = action.params["recipientName"]?.stringValue {
                return "To \(recipientName): \(subject)"
            }
            return subject
        }
        // For reminders/calendar, show title
        if let title = action.params["title"]?.stringValue {
            return title
        }
        // For messages, show content preview
        if let content = action.params["content"]?.stringValue {
            return content
        }
        // For recipient info without other details
        if let recipient = action.params["recipient"]?.stringValue {
            return "To: \(recipient)"
        }
        if let recipientName = action.params["recipientName"]?.stringValue {
            return "To: \(recipientName)"
        }
        return "Tap to execute"
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: action.createdAt) {
            let relative = RelativeDateTimeFormatter()
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return action.createdAt
    }
}

// MARK: - Permission Approval Sheet

struct PermissionApprovalSheet: View {
    let permission: PendingPermission
    let onApprove: (PermissionScope, Bool) -> Void
    let onDeny: () -> Void

    @State private var selectedScope: PermissionScope = .once
    @State private var createRule = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    Text(permission.displayTitle)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text(permission.displayDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Scope selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Allow this action:")
                        .font(.headline)

                    Picker("Scope", selection: $selectedScope) {
                        ForEach(PermissionScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedScope == .always {
                        Toggle("Create a rule for similar actions", isOn: $createRule)
                            .font(.subheadline)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                // Risk indicator
                if let risk = permission.displayRisk {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(riskColor(risk))
                        Text("Risk level: \(risk)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: { onApprove(selectedScope, createRule) }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Allow")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    Button(action: onDeny) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Deny")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func riskColor(_ risk: String) -> Color {
        switch risk.lowercased() {
        case "high": return .red
        case "medium": return .orange
        default: return .green
        }
    }
}

// MARK: - View Model

@MainActor
class ActionsViewModel: ObservableObject {
    @Published var pendingActions: [PendingAction] = []
    @Published var pendingPermissions: [PendingPermission] = []
    @Published var suggestions: [ProactiveSuggestion] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let api = APIService.shared

    func loadData() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true

        // Fetch each independently to avoid cascading failures
        do {
            let actionsResponse = try await api.getPendingActions()
            pendingActions = actionsResponse.actions
        } catch {
            print("[ActionsView] Failed to load actions: \(error)")
            // Don't show error for this, try others
        }

        do {
            let permissionsResponse = try await api.getPendingPermissions()
            pendingPermissions = permissionsResponse.pending
        } catch {
            print("[ActionsView] Failed to load permissions: \(error)")
            // Don't show error for this, try others
        }

        do {
            let suggestionsResponse = try await api.getSuggestions(status: "pending")
            suggestions = suggestionsResponse.suggestions
        } catch {
            print("[ActionsView] Failed to load suggestions: \(error)")
            // Don't show error for this
        }

        isLoading = false
    }

    func approvePermission(_ permission: PendingPermission, scope: PermissionScope, createRule: Bool) async {
        do {
            _ = try await api.approvePermission(
                permissionId: permission.id,
                scope: scope,
                createRule: createRule
            )

            // Remove from list
            pendingPermissions.removeAll { $0.id == permission.id }

            // Refresh to get any new actions
            await refresh()

        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func denyPermission(_ permission: PendingPermission) async {
        do {
            _ = try await api.denyPermission(permissionId: permission.id)

            // Remove from list
            pendingPermissions.removeAll { $0.id == permission.id }

        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func executeAction(_ action: PendingAction) async -> ActionExecutionResult {
        let executor = ActionExecutor.shared

        let result = await executor.executeAction(action)

        if result.success && result.requiresUserInput == .none {
            // Remove from list for non-interactive actions
            pendingActions.removeAll { $0.id == action.id }
        } else if !result.success {
            errorMessage = result.message
            showError = true
        }

        return result
    }
}

// MARK: - Email Input Sheet

struct EmailInputSheet: View {
    let recipientName: String
    @Binding var emailText: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "envelope.badge.person.crop")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    Text("Email Address Needed")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Enter the email address for \(recipientName)")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Email input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address")
                        .font(.headline)

                    TextField("name@example.com", text: $emailText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        if isValidEmail(emailText) {
                            onSubmit(emailText)
                        }
                    }) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Continue")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isValidEmail(emailText) ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!isValidEmail(emailText))

                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(.systemGray5))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isFocused = true
            }
        }
        .presentationDetents([.medium])
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

#Preview {
    ActionsView()
}

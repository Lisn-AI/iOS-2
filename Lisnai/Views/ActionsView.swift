import SwiftUI
import MessageUI

/// View for managing pending actions and permission requests
struct ActionsView: View {
    @ObservedObject var viewModel: ActionsViewModel
    @State private var selectedPermission: PendingPermission?
    @State private var selectedSuggestion: ProactiveSuggestion?
    @State private var showMailComposer = false
    @State private var showEmailInputSheet = false
    @State private var emailInputText = ""
    @State private var pendingEmailAction: PendingAction?
    @State private var emailDraftDetails: EmailDraftDetails?
    @State private var showSuccessAlert = false
    @State private var successMessage = ""

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
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                HStack {
                    Text("Actions")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(LisnColors.textPrimary)
                    Spacer()
                    Button(action: { Task { await viewModel.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(LisnColors.textSecondary)
                    }
                    .disabled(viewModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.top, LisnSpacing.sm)
                .padding(.bottom, LisnSpacing.xs)
                .background(.regularMaterial)
            }
            .refreshable {
                await viewModel.refresh()
            }
            .sheet(item: $selectedPermission) { permission in
                PermissionApprovalSheet(
                    permission: permission,
                    onApprove: { scope, createRule in
                        Task {
                            let result = await viewModel.approvePermission(permission, scope: scope, createRule: createRule)
                            selectedPermission = nil

                            // Show success feedback if action was executed
                            if let result = result, result.success {
                                successMessage = result.message
                                showSuccessAlert = true
                            }
                        }
                    },
                    onDeny: {
                        Task {
                            await viewModel.denyPermission(permission)
                            selectedPermission = nil
                        }
                    }
                )
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
            .sheet(item: $selectedSuggestion) { suggestion in
                SuggestionDetailSheet(
                    suggestion: suggestion,
                    onAccept: {
                        Task {
                            let result = await viewModel.acceptSuggestion(suggestion)
                            selectedSuggestion = nil

                            if let result = result, result.success && result.requiresUserInput == .none {
                                successMessage = result.message
                                showSuccessAlert = true
                            }
                        }
                    },
                    onDismiss: {
                        Task {
                            await viewModel.dismissSuggestion(suggestion)
                            selectedSuggestion = nil
                        }
                    }
                )
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Success", isPresented: $showSuccessAlert) {
                Button("OK") { }
            } message: {
                Text(successMessage)
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
            viewModel.errorMessage = result.message
            viewModel.showError = true
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
        VStack(spacing: LisnSpacing.md) {
            Circle()
                .fill(LisnColors.bgSecondary)
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "bolt")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(LisnColors.accent)
                }

            Text("All Caught Up")
                .font(LisnFont.titleLarge())
                .foregroundColor(LisnColors.textPrimary)

            Text("Actions from your conversations will appear here")
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, LisnSpacing.xl)
    }

    // MARK: - Content List

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: LisnSpacing.lg) {
                // Proactive Suggestions Section
                if !viewModel.suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                        Label("Suggestions", systemImage: "lightbulb.fill")
                            .lisnSectionHeader()
                            .padding(.horizontal, LisnSpacing.xxs)

                        VStack(spacing: LisnSpacing.sm) {
                            ForEach(viewModel.suggestions) { suggestion in
                                SuggestionPreviewRow(suggestion: suggestion)
                                    .padding(LisnSpacing.md)
                                    .lisnCardStyle()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedSuggestion = suggestion
                                    }
                            }
                        }
                    }
                }

                // Permission Requests Section
                if !viewModel.pendingPermissions.isEmpty {
                    VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                        Label("Needs Approval", systemImage: "lock.shield")
                            .lisnSectionHeader()
                            .padding(.horizontal, LisnSpacing.xxs)

                        VStack(spacing: LisnSpacing.sm) {
                            ForEach(viewModel.pendingPermissions) { permission in
                                PermissionRequestRow(permission: permission)
                                    .padding(LisnSpacing.md)
                                    .lisnCardStyle()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPermission = permission
                                    }
                            }
                        }
                    }
                }

                // Pending Actions Section
                if !viewModel.pendingActions.isEmpty {
                    VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                        Label("Ready to Execute", systemImage: "bolt.fill")
                            .lisnSectionHeader()
                            .padding(.horizontal, LisnSpacing.xxs)

                        VStack(spacing: LisnSpacing.sm) {
                            ForEach(viewModel.pendingActions) { action in
                                PendingActionRow(action: action) {
                                    Task {
                                        let result = await viewModel.executeAction(action)

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
                                            break

                                        case .none:
                                            break
                                        }
                                    }
                                }
                                .padding(LisnSpacing.md)
                                .lisnCardStyle()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LisnSpacing.md)
            .padding(.top, LisnSpacing.xs)
            .padding(.bottom, LisnSpacing.xxxl)
        }
        .background(LisnColors.bgPrimary)
    }
}

// MARK: - Suggestion Preview Row

struct SuggestionPreviewRow: View {
    let suggestion: ProactiveSuggestion

    var body: some View {
        HStack(alignment: .top, spacing: LisnSpacing.sm) {
            Circle()
                .fill(typeColor.opacity(0.12))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: typeIcon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(typeColor)
                }

            VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                Text(suggestion.title)
                    .font(LisnFont.bodyMedium())
                    .fontWeight(.semibold)
                    .foregroundColor(LisnColors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(suggestion.body)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: LisnSpacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LisnColors.textTertiary)
                .padding(.top, LisnSpacing.xs)
        }
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
        case "call_reminder": return LisnColors.success
        case "follow_up": return LisnColors.accent
        case "task_reminder": return LisnColors.warning
        case "pattern_insight": return Color.purple
        case "connection_prompt": return Color.pink
        case "event_reminder": return Color.cyan
        default: return LisnColors.warning
        }
    }
}

// MARK: - Permission Request Row

struct PermissionRequestRow: View {
    let permission: PendingPermission

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            Circle()
                .fill(riskColor.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(riskColor)
                }

            VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
                Text(permission.displayTitle)
                    .font(LisnFont.bodyMedium())
                    .fontWeight(.medium)
                    .foregroundColor(LisnColors.textPrimary)

                Text(permission.displayDescription)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(2)

                HStack(spacing: LisnSpacing.xxs) {
                    Label(permission.skill, systemImage: "app.fill")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.accent)

                    Text("\u{2022}")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)

                    Text(permission.tool)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LisnColors.textTertiary)
        }
    }

    private var riskColor: Color {
        switch permission.displayRisk?.lowercased() {
        case "high": return LisnColors.error
        case "medium": return LisnColors.warning
        default: return LisnColors.success
        }
    }
}

// MARK: - Pending Action Row

struct PendingActionRow: View {
    let action: PendingAction
    let onExecute: () -> Void

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            Circle()
                .fill(LisnColors.accent.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: actionIcon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(LisnColors.accent)
                }

            VStack(alignment: .leading, spacing: LisnSpacing.xxxs) {
                Text(actionTitle)
                    .font(LisnFont.bodyMedium())
                    .fontWeight(.medium)
                    .foregroundColor(LisnColors.textPrimary)

                Text(actionDescription)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .lineLimit(2)

                Text(formattedDate)
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textTertiary)
            }

            Spacer()

            Button(action: onExecute) {
                Text("Execute")
                    .font(LisnFont.caption())
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, LisnSpacing.sm)
                    .padding(.vertical, LisnSpacing.xs)
                    .background(LisnColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
                        .foregroundColor(LisnColors.accent)

                    Text(permission.displayTitle)
                        .font(LisnFont.titleLarge())
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text(permission.displayDescription)
                        .font(LisnFont.bodyLarge())
                        .foregroundColor(LisnColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Scope selection
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Allow this action:")
                            .font(LisnFont.titleSmall())

                        Picker("Scope", selection: $selectedScope) {
                            ForEach(PermissionScope.allCases, id: \.self) { scope in
                                Text(scope.displayName).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)

                        if selectedScope == .always {
                            Toggle("Create a rule for similar actions", isOn: $createRule)
                                .font(LisnFont.bodyMedium())
                        }
                    }
                    .padding()
                }

                // Risk indicator
                if let risk = permission.displayRisk {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(riskColor(risk))
                        Text("Risk level: \(risk)")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
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
                        .background(LisnColors.success)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }

                    Button(action: onDeny) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                            Text("Deny")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(LisnColors.bgSecondary)
                        .foregroundColor(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
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
        case "high": return LisnColors.error
        case "medium": return LisnColors.warning
        default: return LisnColors.success
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

    func approvePermission(_ permission: PendingPermission, scope: PermissionScope, createRule: Bool) async -> ActionExecutionResult? {
        do {
            _ = try await api.approvePermission(
                permissionId: permission.id,
                scope: scope,
                createRule: createRule
            )

            // Remove from list
            pendingPermissions.removeAll { $0.id == permission.id }

            // IMPORTANT: After approval, actually execute the action!
            // Convert permission to action and execute via ActionExecutor
            let executor = ActionExecutor.shared
            let result = await executor.executePermissionAction(permission)

            if result.success {
                print("[ActionsVM] Permission action executed successfully: \(result.message)")
            } else {
                print("[ActionsVM] Permission action failed: \(result.message)")
                errorMessage = result.message
                showError = true
            }

            return result

        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return nil
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

    func acceptSuggestion(_ suggestion: ProactiveSuggestion) async -> ActionExecutionResult? {
        do {
            let response = try await api.acceptSuggestion(suggestionId: suggestion.id)

            suggestions.removeAll { $0.id == suggestion.id }

            if let action = response.suggestedAction {
                let executor = ActionExecutor.shared
                let result = await executor.executeSuggestedAction(action, suggestionId: suggestion.id)

                if !result.success {
                    errorMessage = result.message
                    showError = true
                }

                return result
            }

            return nil
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return nil
        }
    }

    func dismissSuggestion(_ suggestion: ProactiveSuggestion) async {
        do {
            _ = try await api.dismissSuggestion(suggestionId: suggestion.id)
            suggestions.removeAll { $0.id == suggestion.id }
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
                        .foregroundColor(LisnColors.accent)

                    Text("Email Address Needed")
                        .font(LisnFont.titleLarge())
                        .fontWeight(.semibold)

                    Text("Enter the email address for \(recipientName)")
                        .font(LisnFont.bodyLarge())
                        .foregroundColor(LisnColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Email input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email Address")
                        .font(LisnFont.titleSmall())

                    TextField("name@example.com", text: $emailText)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                }
                .padding()
                .background(LisnColors.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))

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
                        .background(isValidEmail(emailText) ? LisnColors.accent : Color.gray)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }
                    .disabled(!isValidEmail(emailText))

                    Button(action: onCancel) {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LisnColors.bgSecondary)
                            .foregroundColor(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
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
    ActionsView(viewModel: ActionsViewModel())
}

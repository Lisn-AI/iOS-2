import SwiftUI
import SwiftData
import MessageUI

/// Unified Actions page with Active/Insights tabs
struct ActionsView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject var viewModel: ActionsViewModel
    @State private var selectedTab: ActionTab = .active
    @State private var selectedSuggestion: ProactiveSuggestion?
    @State private var showMailComposer = false
    @State private var showEmailInputSheet = false
    @State private var emailInputText = ""
    @State private var pendingEmailAction: PendingAction?
    @State private var emailDraftDetails: EmailDraftDetails?
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var actionToEdit: PendingAction?

    enum ActionTab: String, CaseIterable {
        case active = "Active"
        case commitments = "Commitments"
        case insights = "Insights"
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.pendingActions.isEmpty && viewModel.suggestions.isEmpty {
                    ProgressView("Loading...")
                } else if filteredItems.isEmpty {
                    emptyStateView
                } else {
                    contentList
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top) {
                VStack(spacing: LisnSpacing.sm) {
                    HStack {
                        Text("Actions")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(LisnColors.textPrimary)
                        Spacer()
                        Button(action: { Task { await viewModel.refresh(modelContext: modelContext) } }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(LisnColors.textSecondary)
                        }
                        .disabled(viewModel.isLoading)
                    }
                    .padding(.horizontal)

                    // Tab picker
                    Picker("", selection: $selectedTab) {
                        ForEach(ActionTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
                .padding(.top, LisnSpacing.sm)
                .padding(.bottom, LisnSpacing.xs)
                .background(.regularMaterial)
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
            }
            .sheet(item: $actionToEdit) { action in
                ActionEditSheet(
                    action: action,
                    onConfirm: { editedAction in
                        actionToEdit = nil
                        Task {
                            let result = await viewModel.executeAction(editedAction)
                            handleActionResult(result, for: editedAction)
                        }
                    },
                    onCancel: { actionToEdit = nil }
                )
            }
            .sheet(item: $selectedSuggestion) { suggestion in
                SuggestionDetailSheet(
                    suggestion: suggestion,
                    onAccept: {
                        Task {
                            if let action = await viewModel.acceptSuggestionForEdit(suggestion) {
                                selectedSuggestion = nil
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    actionToEdit = action
                                }
                            } else {
                                selectedSuggestion = nil
                                successMessage = "Suggestion accepted"
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
            .sheet(isPresented: $showEmailInputSheet) {
                EmailInputSheet(
                    recipientName: pendingEmailAction?.params?["recipientName"]?.stringValue ?? "recipient",
                    emailText: $emailInputText,
                    onSubmit: { email in
                        Task { await handleEmailAddressSubmitted(email) }
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
                        Task { await handleMailComposerResult(result) }
                    }
                }
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
            // Sync: refresh when an action is completed from chat
            .onReceive(NotificationCenter.default.publisher(for: .actionCompleted)) { notification in
                if let actionId = notification.userInfo?["actionId"] as? String {
                    viewModel.pendingActions.removeAll { $0.id == actionId }
                }
            }
        }
    }

    // MARK: - Filtered Items

    private var filteredItems: [ProactiveSuggestion] {
        switch selectedTab {
        case .active:
            return viewModel.suggestions.filter { suggestion in
                suggestion.type != "commitment" &&
                suggestion.type != "pattern_insight" &&
                suggestion.type != "connection_prompt"
            }
        case .commitments:
            return viewModel.suggestions.filter { $0.type == "commitment" }
        case .insights:
            return viewModel.suggestions.filter {
                $0.type == "pattern_insight" || $0.type == "connection_prompt"
            }
        }
    }

    // MARK: - Action Result Handler

    private func handleActionResult(_ result: ActionExecutionResult, for action: PendingAction) {
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
            if result.success {
                successMessage = result.message
                showSuccessAlert = true
            }
        }
    }

    // MARK: - Email Handling

    private func handleEmailAddressSubmitted(_ email: String) async {
        showEmailInputSheet = false
        guard pendingEmailAction != nil else { return }

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
                    Image(systemName: emptyIcon)
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(LisnColors.accent)
                }

            Text(emptyTitle)
                .font(LisnFont.titleLarge())
                .foregroundColor(LisnColors.textPrimary)

            Text(emptySubtitle)
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, LisnSpacing.xl)
    }

    private var suggestionSectionHeader: String {
        switch selectedTab {
        case .active: return "Suggestions"
        case .commitments: return "Commitments"
        case .insights: return "Insights"
        }
    }

    private var suggestionSectionIcon: String {
        switch selectedTab {
        case .active: return "sparkles"
        case .commitments: return "flag.fill"
        case .insights: return "lightbulb.fill"
        }
    }

    private var emptyIcon: String {
        switch selectedTab {
        case .active: return "bolt"
        case .commitments: return "flag"
        case .insights: return "lightbulb"
        }
    }

    private var emptyTitle: String {
        switch selectedTab {
        case .active: return "All Caught Up"
        case .commitments: return "No Commitments"
        case .insights: return "No Insights Yet"
        }
    }

    private var emptySubtitle: String {
        switch selectedTab {
        case .active: return "Proactive suggestions from your conversations will appear here"
        case .commitments: return "Promises and follow-ups detected in your recordings will appear here"
        case .insights: return "Pattern insights and connection prompts will appear here"
        }
    }

    // MARK: - Content List

    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: LisnSpacing.sm) {
                // Active tab: pending actions from chat + actionable suggestions
                if selectedTab == .active {
                    // Pending actions from chat (always at top)
                    if !viewModel.pendingActions.isEmpty {
                        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                            Label("From Chat", systemImage: "bubble.left.fill")
                                .lisnSectionHeader()
                                .padding(.horizontal, LisnSpacing.xxs)

                            ForEach(viewModel.pendingActions) { action in
                                PendingActionRow(action: action) {
                                    actionToEdit = action
                                }
                                .padding(LisnSpacing.md)
                                .lisnCardStyle()
                            }
                        }
                    }
                }

                // Suggestions (filtered by tab)
                if !filteredItems.isEmpty {
                    VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                        Label(suggestionSectionHeader, systemImage: suggestionSectionIcon)
                            .lisnSectionHeader()
                            .padding(.horizontal, LisnSpacing.xxs)

                        ForEach(filteredItems) { suggestion in
                            SuggestionCard(suggestion: suggestion)
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
            .padding(.horizontal, LisnSpacing.md)
            .padding(.top, LisnSpacing.xs)
            .padding(.bottom, 68)
        }
        .background(LisnColors.bgPrimary)
    }
}

// MARK: - Suggestion Card

struct SuggestionCard: View {
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

                HStack(spacing: LisnSpacing.xxs) {
                    // Source badge
                    Text(sourceBadge)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(LisnColors.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(LisnColors.accent.opacity(0.1))
                        .clipShape(Capsule())

                    Text("\u{2022}")
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)

                    Text(formattedDate)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.textTertiary)
                }
            }

            Spacer(minLength: LisnSpacing.xs)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(LisnColors.textTertiary)
                .padding(.top, LisnSpacing.xs)
        }
    }

    private var sourceBadge: String {
        switch suggestion.type {
        case "commitment": return "commitment"
        default:
            if suggestion.reasoning.contains("live recording") { return "live" }
            return "proactive"
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
        case "commitment": return "flag.fill"
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
        case "commitment": return Color.orange
        default: return LisnColors.warning
        }
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: suggestion.createdAt) {
            let relative = RelativeDateTimeFormatter()
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return suggestion.createdAt
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
                Text("Review")
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
        let skill = (action.skill ?? action.params?["skill"]?.stringValue ?? "").lowercased()
        let tool = (action.tool ?? action.params?["tool"]?.stringValue ?? "").lowercased()

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
            return "bolt.fill"
        }
    }

    private var actionTitle: String {
        let skill = (action.skill ?? "").lowercased()
        let tool = (action.tool ?? "").lowercased()

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
            return action.displayType.capitalized
        }
    }

    private var actionDescription: String {
        let params = action.params ?? [:]
        if let subject = params["subject"]?.stringValue, !subject.isEmpty {
            if let name = params["recipientName"]?.stringValue {
                return "To \(name): \(subject)"
            }
            return subject
        }
        if let title = params["title"]?.stringValue { return title }
        if let content = params["content"]?.stringValue { return content }
        if let recipient = params["recipient"]?.stringValue { return "To: \(recipient)" }
        return "Tap to review"
    }

    private var formattedDate: String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: action.createdAt ?? "") {
            let relative = RelativeDateTimeFormatter()
            return relative.localizedString(for: date, relativeTo: Date())
        }
        return action.createdAt ?? ""
    }
}

// MARK: - View Model

@MainActor
class ActionsViewModel: ObservableObject {
    @Published var pendingActions: [PendingAction] = []
    @Published var suggestions: [ProactiveSuggestion] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let dataService = DataService.shared

    func loadData(modelContext: ModelContext? = nil) async {
        await refresh(modelContext: modelContext)
    }

    func refresh(modelContext: ModelContext? = nil) async {
        isLoading = true

        // Clean expired suggestions
        if let ctx = modelContext {
            LocalSuggestion.cleanExpired(context: ctx)
        }

        // Fetch pending actions from chat
        do {
            let actionsResponse = try await APIService.shared.getPendingActions()
            pendingActions = actionsResponse.actions
        } catch {
            print("[ActionsView] Failed to load actions: \(error)")
        }

        // Fetch suggestions (local-first)
        do {
            let suggestionsResponse = try await dataService.getSuggestions(context: modelContext)
            suggestions = suggestionsResponse.suggestions
        } catch {
            print("[ActionsView] Failed to load suggestions: \(error)")
        }

        isLoading = false
    }

    func acceptSuggestionForEdit(_ suggestion: ProactiveSuggestion) async -> PendingAction? {
        do {
            _ = try await APIService.shared.acceptSuggestion(suggestionId: suggestion.id)
        } catch {
            print("[ActionsVM] Backend accept failed (non-fatal): \(error)")
        }

        suggestions.removeAll { $0.id == suggestion.id }

        guard let suggestedAction = suggestion.suggestedAction else { return nil }

        return PendingAction(
            id: suggestion.id,
            skill: suggestedAction.skill,
            tool: suggestedAction.tool,
            type: suggestedAction.tool,
            params: suggestedAction.params,
            status: "pending",
            createdAt: suggestion.createdAt
        )
    }

    func dismissSuggestion(_ suggestion: ProactiveSuggestion) async {
        do {
            _ = try await APIService.shared.dismissSuggestion(suggestionId: suggestion.id)
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

                VStack(spacing: 12) {
                    Button(action: {
                        if isValidEmail(emailText) { onSubmit(emailText) }
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
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Suggestion Detail Sheet

struct SuggestionDetailSheet: View {
    let suggestion: ProactiveSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LisnSpacing.xl) {
                    // Header
                    VStack(spacing: LisnSpacing.sm) {
                        Image(systemName: typeIcon)
                            .font(.system(size: 48))
                            .foregroundColor(typeColor)

                        Text(suggestion.title)
                            .font(LisnFont.titleLarge())
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        Text(typeName)
                            .font(LisnFont.caption())
                            .padding(.horizontal, LisnSpacing.sm)
                            .padding(.vertical, 4)
                            .background(typeColor.opacity(0.2))
                            .foregroundColor(typeColor)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }
                    .padding(.top)

                    // Body
                    GlassCard {
                        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                            Text("Suggestion")
                                .font(LisnFont.titleSmall())

                            Text(suggestion.body)
                                .font(LisnFont.bodyLarge())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Reasoning
                    GlassCard {
                        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
                            Text("Why this suggestion?")
                                .font(LisnFont.titleSmall())

                            Text(suggestion.reasoning)
                                .font(LisnFont.bodyLarge())
                                .foregroundColor(LisnColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Confidence
                    HStack {
                        Image(systemName: "chart.bar.fill")
                            .foregroundColor(confidenceColor)
                        Text("Confidence: \(Int(suggestion.confidence * 100))%")
                            .font(LisnFont.bodyMedium())
                            .foregroundColor(LisnColors.textSecondary)
                    }

                    // Suggested action preview
                    if let action = suggestion.suggestedAction {
                        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
                            Text("Suggested Action")
                                .font(LisnFont.titleSmall())

                            HStack {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(LisnColors.accent)
                                Text("\(action.skill) > \(action.tool)")
                                    .font(LisnFont.bodyMedium())
                                    .foregroundColor(LisnColors.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(LisnColors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: LisnSpacing.sm) {
                        Button(action: onAccept) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text(suggestion.suggestedAction != nil ? "Accept & Edit" : "Mark as Helpful")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(LisnColors.success)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                        }

                        Button(action: onDismiss) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                Text("Not Helpful")
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
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var typeIcon: String {
        switch suggestion.type {
        case "call_reminder": return "phone.fill"
        case "follow_up": return "arrow.turn.up.right"
        case "task_reminder": return "checkmark.circle"
        case "pattern_insight": return "chart.line.uptrend.xyaxis"
        case "connection_prompt": return "person.2.fill"
        case "event_reminder": return "calendar"
        case "commitment": return "flag.fill"
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
        case "commitment": return Color.orange
        default: return LisnColors.warning
        }
    }

    private var typeName: String {
        switch suggestion.type {
        case "call_reminder": return "Call Reminder"
        case "follow_up": return "Follow Up"
        case "task_reminder": return "Task Reminder"
        case "pattern_insight": return "Pattern Insight"
        case "connection_prompt": return "Connection Prompt"
        case "event_reminder": return "Event Reminder"
        case "commitment": return "Commitment"
        default: return suggestion.type.capitalized
        }
    }

    private var confidenceColor: Color {
        if suggestion.confidence >= 0.8 {
            return LisnColors.success
        } else if suggestion.confidence >= 0.6 {
            return LisnColors.warning
        } else {
            return LisnColors.textTertiary
        }
    }
}

#Preview {
    ActionsView(viewModel: ActionsViewModel())
}

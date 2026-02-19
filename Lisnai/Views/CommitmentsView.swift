import SwiftUI
import SwiftData
import MessageUI

/// View for displaying and managing user commitments detected from conversations
struct CommitmentsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = CommitmentsViewModel()
    @State private var selectedFilter: CommitmentFilter = .all
    @State private var selectedCommitment: Commitment?
    @State private var showDetailSheet = false
    @State private var actionFromCommitment: PendingAction?
    @State private var commitmentForAction: Commitment?
    @State private var showSuccessAlert = false
    @State private var successMessage = ""
    @State private var showEmailInputSheet = false
    @State private var emailInputText = ""
    @State private var pendingEmailAction: PendingAction?
    @State private var emailDraftDetails: EmailDraftDetails?
    @State private var showMailComposer = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.commitments.isEmpty {
                    ProgressView("Loading commitments...")
                } else if viewModel.commitments.isEmpty {
                    emptyStateView
                } else {
                    commitmentsList
                }
            }
            .navigationTitle("Commitments")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(CommitmentFilter.allCases, id: \.self) { filter in
                            Button(action: { selectedFilter = filter }) {
                                HStack {
                                    Text(filter.displayName)
                                    if selectedFilter == filter {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { Task { await viewModel.refresh(modelContext: modelContext) } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            .refreshable {
                await viewModel.refresh(modelContext: modelContext)
            }
            .task {
                await viewModel.loadData(modelContext: modelContext)
            }
            .sheet(isPresented: $showDetailSheet) {
                if let commitment = selectedCommitment {
                    CommitmentDetailSheet(
                        commitment: commitment,
                        onComplete: {
                            Task {
                                await viewModel.completeCommitment(commitment)
                                showDetailSheet = false
                                selectedCommitment = nil
                            }
                        },
                        onTakeAction: { action in
                            commitmentForAction = commitment
                            showDetailSheet = false
                            // Small delay so the detail sheet dismisses before the edit sheet presents
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                actionFromCommitment = action
                            }
                        }
                    )
                }
            }
            .sheet(item: $actionFromCommitment) { action in
                ActionEditSheet(
                    action: action,
                    onConfirm: { editedAction in
                        actionFromCommitment = nil
                        Task {
                            let result = await ActionExecutor.shared.executeAction(editedAction)

                            switch result.requiresUserInput {
                            case .emailAddress:
                                pendingEmailAction = editedAction
                                emailInputText = ""
                                showEmailInputSheet = true

                            case .mailComposer:
                                if let details = ActionExecutor.shared.getEmailDraftDetails(from: ActionExecutor.shared.pendingEmailAction ?? editedAction) {
                                    emailDraftDetails = details
                                    showMailComposer = true
                                }

                            case .phoneNumber:
                                break

                            case .none:
                                if result.success {
                                    // Auto-complete the commitment
                                    if let commitment = commitmentForAction {
                                        await viewModel.completeCommitment(commitment)
                                    }
                                    successMessage = result.message
                                    showSuccessAlert = true
                                    commitmentForAction = nil
                                }
                            }
                        }
                    },
                    onCancel: {
                        actionFromCommitment = nil
                        commitmentForAction = nil
                    }
                )
            }
            .sheet(isPresented: $showEmailInputSheet) {
                EmailInputSheet(
                    recipientName: pendingEmailAction?.params?["recipientName"]?.stringValue ?? "recipient",
                    emailText: $emailInputText,
                    onSubmit: { email in
                        showEmailInputSheet = false
                        Task {
                            let executor = ActionExecutor.shared
                            let result = await executor.addEmailAndExecute(email)
                            if result.success && result.requiresUserInput == .mailComposer {
                                if let details = executor.getEmailDraftDetails(from: executor.pendingEmailAction!) {
                                    emailDraftDetails = details
                                    showMailComposer = true
                                }
                            }
                            pendingEmailAction = nil
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
                        let sent = result == .sent
                        let executor = ActionExecutor.shared
                        Task {
                            if let action = executor.pendingEmailAction {
                                await executor.completeEmailAction(action, sent: sent)
                                if sent, let commitment = commitmentForAction {
                                    await viewModel.completeCommitment(commitment)
                                    successMessage = "Email sent"
                                    showSuccessAlert = true
                                    commitmentForAction = nil
                                }
                            }
                        }
                        showMailComposer = false
                        emailDraftDetails = nil
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
        }
    }

    // MARK: - Filter

    enum CommitmentFilter: String, CaseIterable {
        case all = "all"
        case active = "active"
        case pending = "pending"
        case completed = "completed"

        var displayName: String {
            switch self {
            case .all: return "All"
            case .active: return "Active"
            case .pending: return "Pending"
            case .completed: return "Completed"
            }
        }
    }

    private var filteredCommitments: [Commitment] {
        switch selectedFilter {
        case .all:
            return viewModel.commitments
        case .active:
            return viewModel.commitments.filter { $0.status == "active" || $0.status == "pending" }
        case .pending:
            return viewModel.commitments.filter { $0.status == "pending" }
        case .completed:
            return viewModel.commitments.filter { $0.status == "completed" }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        ContentUnavailableView(
            "No Commitments",
            systemImage: "checkmark.seal",
            description: Text("Commitments you make during conversations will be tracked here")
        )
    }

    // MARK: - Commitments List

    private var commitmentsList: some View {
        List {
            // Summary section
            if selectedFilter == .all || selectedFilter == .active {
                Section {
                    HStack(spacing: LisnSpacing.md) {
                        StatBox(
                            title: "Active",
                            count: viewModel.commitments.filter { $0.status != "completed" }.count,
                            color: LisnColors.accent
                        )
                        StatBox(
                            title: "Due Today",
                            count: viewModel.commitments.filter { isDueToday($0) }.count,
                            color: LisnColors.warning
                        )
                        StatBox(
                            title: "Overdue",
                            count: viewModel.commitments.filter { isOverdue($0) }.count,
                            color: LisnColors.error
                        )
                    }
                    .padding(.vertical, LisnSpacing.xxs)
                    .listRowBackground(LisnColors.bgElevated)
                }
            }

            // Group by urgency
            ForEach(groupedCommitments.keys.sorted(), id: \.self) { urgency in
                Section {
                    ForEach(groupedCommitments[urgency] ?? []) { commitment in
                        CommitmentRow(commitment: commitment)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedCommitment = commitment
                                showDetailSheet = true
                            }
                            .listRowBackground(LisnColors.bgElevated)
                            .swipeActions(edge: .trailing) {
                                if commitment.status != "completed" {
                                    Button {
                                        Task { await viewModel.completeCommitment(commitment) }
                                    } label: {
                                        Label("Complete", systemImage: "checkmark")
                                    }
                                    .tint(LisnColors.success)
                                }
                            }
                    }
                } header: {
                    Label(urgencyHeader(urgency), systemImage: urgencyIcon(urgency))
                        .foregroundColor(urgencyColor(urgency))
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LisnColors.bgPrimary)
    }

    private var groupedCommitments: [String: [Commitment]] {
        Dictionary(grouping: filteredCommitments) { $0.urgency }
    }

    private func isDueToday(_ commitment: Commitment) -> Bool {
        guard let dueDateString = commitment.dueDate else { return false }
        let formatter = ISO8601DateFormatter()
        guard let dueDate = formatter.date(from: dueDateString) else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }

    private func isOverdue(_ commitment: Commitment) -> Bool {
        guard let dueDateString = commitment.dueDate,
              commitment.status != "completed" else { return false }
        let formatter = ISO8601DateFormatter()
        guard let dueDate = formatter.date(from: dueDateString) else { return false }
        return dueDate < Date()
    }

    private func urgencyHeader(_ urgency: String) -> String {
        switch urgency.lowercased() {
        case "high": return "High Priority"
        case "medium": return "Medium Priority"
        case "low": return "Low Priority"
        default: return urgency.capitalized
        }
    }

    private func urgencyIcon(_ urgency: String) -> String {
        switch urgency.lowercased() {
        case "high": return "exclamationmark.triangle.fill"
        case "medium": return "exclamationmark.circle.fill"
        case "low": return "minus.circle.fill"
        default: return "circle.fill"
        }
    }

    private func urgencyColor(_ urgency: String) -> Color {
        switch urgency.lowercased() {
        case "high": return LisnColors.error
        case "medium": return LisnColors.warning
        case "low": return LisnColors.accent
        default: return LisnColors.textSecondary
        }
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: LisnSpacing.xxs) {
            Text("\(count)")
                .font(LisnFont.titleLarge())
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LisnSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous)
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - Commitment Row

struct CommitmentRow: View {
    let commitment: Commitment

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            // Status indicator
            Image(systemName: statusIcon)
                .font(LisnFont.titleLarge())
                .foregroundColor(statusColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: LisnSpacing.xxs) {
                Text(commitment.description)
                    .font(LisnFont.titleSmall())
                    .strikethrough(commitment.status == "completed")

                HStack(spacing: LisnSpacing.xs) {
                    // Type badge
                    Label(commitment.type.capitalized, systemImage: typeIcon)
                        .font(LisnFont.caption())
                        .foregroundColor(LisnColors.accent)

                    // Person if present
                    if let person = commitment.person {
                        Text("-")
                            .foregroundColor(LisnColors.textSecondary)
                        Label(person, systemImage: "person.fill")
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textSecondary)
                    }
                }

                // Due date
                if let dueDateString = commitment.dueDate {
                    Text(formattedDueDate(dueDateString))
                        .font(LisnFont.caption())
                        .foregroundColor(dueDateColor(dueDateString))
                }
            }

            Spacer()

            if commitment.status != "completed" {
                Image(systemName: "chevron.right")
                    .foregroundColor(LisnColors.textSecondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(LisnColors.success)
            }
        }
        .padding(.vertical, LisnSpacing.xxs)
        .opacity(commitment.status == "completed" ? 0.6 : 1.0)
    }

    private var statusIcon: String {
        switch commitment.status.lowercased() {
        case "completed": return "checkmark.circle.fill"
        case "overdue": return "exclamationmark.circle.fill"
        default: return "circle"
        }
    }

    private var statusColor: Color {
        switch commitment.status.lowercased() {
        case "completed": return LisnColors.success
        case "overdue": return LisnColors.error
        default: return LisnColors.accent
        }
    }

    private var typeIcon: String {
        switch commitment.type.lowercased() {
        case "call": return "phone.fill"
        case "meeting": return "person.2.fill"
        case "task": return "checklist"
        case "follow_up": return "arrow.turn.up.right"
        case "delivery": return "shippingbox.fill"
        default: return "star.fill"
        }
    }

    private func formattedDueDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else {
            return dateString
        }

        if Calendar.current.isDateInToday(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Due today at \(timeFormatter.string(from: date))"
        } else if Calendar.current.isDateInTomorrow(date) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return "Due tomorrow at \(timeFormatter.string(from: date))"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short
            return "Due \(dateFormatter.string(from: date))"
        }
    }

    private func dueDateColor(_ dateString: String) -> Color {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return LisnColors.textSecondary }

        if date < Date() && commitment.status != "completed" {
            return LisnColors.error
        } else if Calendar.current.isDateInToday(date) {
            return LisnColors.warning
        }
        return LisnColors.textSecondary
    }
}

// MARK: - Commitment Detail Sheet

struct CommitmentDetailSheet: View {
    let commitment: Commitment
    let onComplete: () -> Void
    var onTakeAction: ((PendingAction) -> Void)? = nil

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

                        Text(commitment.description)
                            .font(LisnFont.titleLarge())
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)

                        HStack(spacing: LisnSpacing.sm) {
                            LisnChip(
                                text: commitment.type.capitalized,
                                icon: typeIcon,
                                color: typeColor
                            )

                            LisnChip(
                                text: commitment.urgency.capitalized,
                                icon: urgencyIcon,
                                color: urgencyColor
                            )
                        }
                    }
                    .padding(.top)

                    // Details
                    GlassCard {
                        VStack(alignment: .leading, spacing: LisnSpacing.md) {
                            if let person = commitment.person {
                                DetailRow(icon: "person.fill", title: "Person", value: person)
                            }

                            if let dueDate = commitment.dueDate {
                                DetailRow(icon: "calendar", title: "Due Date", value: formattedDate(dueDate))
                            }

                            DetailRow(icon: "clock.fill", title: "Created", value: formattedDate(commitment.createdAt))

                            DetailRow(icon: "flag.fill", title: "Status", value: commitment.status.capitalized)
                        }
                    }

                    Spacer()

                    // Actions
                    if commitment.status != "completed" {
                        VStack(spacing: LisnSpacing.sm) {
                            LisnButton(
                                title: actionButtonLabel,
                                icon: actionButtonIcon,
                                style: .primary,
                                action: {
                                    let action = commitmentToAction(commitment)
                                    onTakeAction?(action)
                                }
                            )

                            LisnButton(
                                title: "Mark as Complete",
                                icon: "checkmark.circle.fill",
                                style: .secondary,
                                action: onComplete
                            )
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
        switch commitment.type.lowercased() {
        case "call": return "phone.fill"
        case "meeting": return "person.2.fill"
        case "task": return "checklist"
        case "follow_up": return "arrow.turn.up.right"
        case "delivery": return "shippingbox.fill"
        default: return "star.fill"
        }
    }

    private var typeColor: Color {
        switch commitment.type.lowercased() {
        case "call": return LisnColors.success
        case "meeting": return .purple
        case "task": return LisnColors.accent
        case "follow_up": return LisnColors.warning
        case "delivery": return .cyan
        default: return .yellow
        }
    }

    private var urgencyIcon: String {
        switch commitment.urgency.lowercased() {
        case "high": return "exclamationmark.triangle.fill"
        case "medium": return "exclamationmark.circle.fill"
        case "low": return "minus.circle.fill"
        default: return "circle.fill"
        }
    }

    private var urgencyColor: Color {
        switch commitment.urgency.lowercased() {
        case "high": return LisnColors.error
        case "medium": return LisnColors.warning
        case "low": return LisnColors.accent
        default: return LisnColors.textSecondary
        }
    }

    // MARK: - Action Button

    private var actionButtonLabel: String {
        switch commitment.type.lowercased() {
        case "call": return "Call"
        case "meeting": return "Schedule Event"
        case "followup", "follow_up": return "Send Message"
        case "task", "deadline", "promise", "delivery": return "Set Reminder"
        default: return "Set Reminder"
        }
    }

    private var actionButtonIcon: String {
        switch commitment.type.lowercased() {
        case "call": return "phone.fill"
        case "meeting": return "calendar"
        case "followup", "follow_up": return "message.fill"
        case "task", "deadline", "promise", "delivery": return "bell.fill"
        default: return "bell.fill"
        }
    }

    // MARK: - Commitment → Action Conversion

    private func commitmentToAction(_ commitment: Commitment) -> PendingAction {
        var params: [String: AnyCodable] = [:]
        let skill: String
        let tool: String

        switch commitment.type.lowercased() {
        case "call":
            skill = "messaging"
            tool = "make_call"
            if let person = commitment.person {
                // If person has digits, treat as phone number; otherwise as contact name
                if person.contains(where: { $0.isNumber }) {
                    params["contact"] = AnyCodable(person)
                } else {
                    params["contact"] = AnyCodable(person)
                }
            }

        case "meeting":
            skill = "apple-calendar"
            tool = "create_event"
            params["title"] = AnyCodable(commitment.description)
            if let dueDate = commitment.dueDate {
                params["startTime"] = AnyCodable(dueDate)
            }
            if let person = commitment.person {
                params["notes"] = AnyCodable("Meeting with \(person)")
            }

        case "followup", "follow_up":
            skill = "messaging"
            tool = "send_message"
            params["content"] = AnyCodable(commitment.description)
            if let person = commitment.person {
                params["recipient"] = AnyCodable(person)
            }

        case "task", "deadline", "promise", "delivery":
            skill = "apple-reminders"
            tool = "create_reminder"
            params["title"] = AnyCodable(commitment.description)
            if let dueDate = commitment.dueDate {
                params["dueDateTime"] = AnyCodable(dueDate)
            }
            if let person = commitment.person {
                params["person"] = AnyCodable(person)
            }

        default:
            skill = "apple-reminders"
            tool = "create_reminder"
            params["title"] = AnyCodable(commitment.description)
            if let dueDate = commitment.dueDate {
                params["dueDateTime"] = AnyCodable(dueDate)
            }
            if let person = commitment.person {
                params["person"] = AnyCodable(person)
            }
        }

        return PendingAction(
            id: commitment.id,
            skill: skill,
            tool: tool,
            type: tool,
            params: params,
            status: "pending",
            createdAt: commitment.createdAt
        )
    }

    private func formattedDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        return dateFormatter.string(from: date)
    }
}

// MARK: - Detail Row

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(LisnColors.textSecondary)
                .frame(width: 24)

            Text(title)
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textSecondary)

            Spacer()

            Text(value)
                .font(LisnFont.bodyMedium())
                .fontWeight(.medium)
        }
    }
}

// MARK: - View Model

@MainActor
class CommitmentsViewModel: ObservableObject {
    @Published var commitments: [Commitment] = []
    @Published var isLoading = false
    @Published var showError = false
    @Published var errorMessage = ""

    private let dataService = DataService.shared

    func loadData(modelContext: ModelContext? = nil) async {
        await refresh(modelContext: modelContext)
    }

    func refresh(modelContext: ModelContext? = nil) async {
        isLoading = true

        do {
            let response = try await dataService.getCommitments(context: modelContext)
            commitments = response.commitments
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    func completeCommitment(_ commitment: Commitment) async {
        do {
            _ = try await APIService.shared.completeCommitment(commitmentId: commitment.id)

            // Update local state
            if let index = commitments.firstIndex(where: { $0.id == commitment.id }) {
                let updated = commitments[index]
                // Create new commitment with completed status
                commitments[index] = Commitment(
                    id: updated.id,
                    description: updated.description,
                    type: updated.type,
                    person: updated.person,
                    dueDate: updated.dueDate,
                    urgency: updated.urgency,
                    status: "completed",
                    createdAt: updated.createdAt
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

#Preview {
    CommitmentsView()
}

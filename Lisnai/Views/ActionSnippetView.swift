import SwiftUI

/// Inline action card rendered within a chat message bubble
/// Shows tool call details with 4 visual states matching the tool lifecycle
struct ActionSnippetView: View {
    let toolCall: InlineToolCall
    @State private var showEditSheet = false
    @State private var localCompleted = false
    @State private var localFailed = false
    @State private var localResultMessage: String?
    @State private var showNoteShareSheet = false
    @State private var pendingNoteTextLocal: String?

    private var pendingAction: PendingAction {
        toolCall.toPendingAction()
    }

    private var formType: ActionFormType {
        ActionFormType.from(pendingAction)
    }

    /// Effective status — local overrides take priority over stream status
    private var effectiveStatus: ToolCallStatus {
        if localCompleted { return .completed }
        if localFailed { return .failed }
        return toolCall.status
    }

    private var displayTitle: String {
        let params = toolCall.params
        if let title = params["title"]?.stringValue, !title.isEmpty {
            return title
        }
        if let content = params["content"]?.stringValue, !content.isEmpty {
            return String(content.prefix(40))
        }
        if let recipient = params["recipient"]?.stringValue, !recipient.isEmpty {
            return "To: \(recipient)"
        }
        return formType.title.replacingOccurrences(of: "Edit ", with: "")
    }

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            // Icon with state-dependent appearance
            iconView

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(LisnFont.bodyMedium())
                    .fontWeight(.medium)
                    .foregroundColor(LisnColors.textPrimary)
                    .lineLimit(1)

                subtitleView
            }

            Spacer()

            // Trailing action
            trailingView
        }
        .padding(LisnSpacing.sm)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                .stroke(borderColor, lineWidth: 0.5)
        )
        .padding(.top, LisnSpacing.xxs)
        .sheet(isPresented: $showEditSheet) {
            ActionEditSheet(
                action: pendingAction,
                onConfirm: { editedAction in
                    showEditSheet = false
                    executeAction(editedAction)
                },
                onCancel: {
                    showEditSheet = false
                }
            )
        }
        .sheet(isPresented: $showNoteShareSheet, onDismiss: {
            Task { await ActionExecutor.shared.completeNoteAction(shared: false) }
        }) {
            if let text = pendingNoteTextLocal {
                NoteShareSheet(text: text) {
                    Task { await ActionExecutor.shared.completeNoteAction(shared: true) }
                    localCompleted = true
                    localResultMessage = "Note saved"
                    showNoteShareSheet = false
                }
            }
        }
    }

    // MARK: - State-dependent sub-views

    @ViewBuilder
    private var iconView: some View {
        switch effectiveStatus {
        case .preparing:
            PreparingIconView(accentColor: formType.accentColor, icon: formType.icon)

        case .completed:
            Circle()
                .fill(LisnColors.success.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LisnColors.success)
                }

        case .failed:
            Circle()
                .fill(LisnColors.warning.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(LisnColors.warning)
                }

        case .permissionRequired:
            Circle()
                .fill(Color.orange.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.orange)
                }
        }
    }

    @ViewBuilder
    private var subtitleView: some View {
        switch effectiveStatus {
        case .preparing:
            Text(toolCall.skill.replacingOccurrences(of: "-", with: " ").capitalized + " · Preparing...")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.textTertiary)

        case .completed:
            Text(localResultMessage ?? toolCall.resultMessage ?? "Done")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.success)

        case .failed:
            Text(localResultMessage ?? toolCall.resultMessage ?? "Failed")
                .font(LisnFont.caption())
                .foregroundColor(LisnColors.warning)

        case .permissionRequired:
            Text("Permission needed")
                .font(LisnFont.caption())
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var trailingView: some View {
        switch effectiveStatus {
        case .preparing:
            Text("Running...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(LisnColors.textTertiary)

        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(LisnColors.success)

        case .failed:
            Button {
                showEditSheet = true
            } label: {
                Text("Retry")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(LisnColors.warning)
                    .clipShape(Capsule())
            }

        case .permissionRequired:
            Button {
                showEditSheet = true
            } label: {
                Text("Review")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.orange)
                    .clipShape(Capsule())
            }
        }
    }

    private var borderColor: Color {
        switch effectiveStatus {
        case .preparing: return Color.primary.opacity(0.06)
        case .completed: return LisnColors.success.opacity(0.3)
        case .failed: return LisnColors.warning.opacity(0.3)
        case .permissionRequired: return Color.orange.opacity(0.3)
        }
    }

    private func executeAction(_ action: PendingAction) {
        Task {
            let result = await ActionExecutor.shared.executeAction(action)
            if result.success {
                // Notes use a share sheet — present it locally so it works from any sheet context
                if let noteText = ActionExecutor.shared.pendingNoteText {
                    pendingNoteTextLocal = noteText
                    // Small delay to let any dismissing sheet animation finish
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    showNoteShareSheet = true
                } else {
                    localCompleted = true
                    localResultMessage = result.message
                    LisnHaptics.success()
                }
            } else {
                localFailed = true
                localResultMessage = result.message
                LisnHaptics.error()
            }
        }
    }
}

// MARK: - Preparing Icon with Gradient Animation (matches ThinkingIndicator style)

private struct PreparingIconView: View {
    let accentColor: Color
    let icon: String

    private static let gradientColors: [Color] = [
        .red, .orange, Color(.systemYellow), .teal, .blue, .purple, .red
    ]

    @State private var gradientOffset: CGFloat = 0

    var body: some View {
        Circle()
            .fill(accentColor.opacity(0.12))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: Self.gradientColors,
                            startPoint: UnitPoint(x: gradientOffset, y: 0.5),
                            endPoint: UnitPoint(x: CGFloat(gradientOffset + 0.5), y: 0.5)
                        )
                    )
            }
            .overlay {
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: Self.gradientColors,
                            center: .center,
                            startAngle: .degrees(Double(gradientOffset) * 360),
                            endAngle: .degrees(Double(gradientOffset) * 360 + 180)
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 36, height: 36)
                    .opacity(0.6)
            }
            .onAppear {
                withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                    gradientOffset = 1.0
                }
            }
    }
}

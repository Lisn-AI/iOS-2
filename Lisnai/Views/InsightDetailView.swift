import SwiftUI
import MarkdownUI

/// Reusable view for displaying a full recording insight
struct InsightDetailView: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.md) {
            // Header: Setting + Mood
            headerSection

            // Third-person take (markdown)
            Markdown(insight.thirdPersonTake)
                .markdownTheme(.lisnContent)

            // Correlations
            if !insight.correlations.isEmpty {
                correlationsSection
            }

            // Actionable ideas
            if !insight.actionableIdeas.isEmpty {
                actionableIdeasSection
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.xs) {
            HStack(spacing: LisnSpacing.sm) {
                if let emoji = insight.settingEmoji {
                    Text(emoji)
                        .font(.system(size: 28))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(insight.setting)
                        .font(LisnFont.labelLarge())
                        .foregroundColor(LisnColors.textPrimary)

                    if let mood = insight.mood {
                        Text(mood)
                            .font(LisnFont.caption())
                            .foregroundColor(LisnColors.textSecondary)
                            .padding(.horizontal, LisnSpacing.xs)
                            .padding(.vertical, 2)
                            .background(LisnColors.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.sm, style: .continuous))
                    }
                }

                Spacer()
            }
        }
    }

    // MARK: - Correlations

    private var correlationsSection: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LisnColors.accent)
                Text("Connections to Past")
                    .font(LisnFont.labelMedium())
                    .foregroundColor(LisnColors.textPrimary)
            }

            ForEach(Array(insight.correlations.enumerated()), id: \.offset) { _, correlation in
                HStack(alignment: .top, spacing: LisnSpacing.sm) {
                    Circle()
                        .fill(LisnColors.accent.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(correlation.memoryDate)
                            .font(LisnFont.captionBold())
                            .foregroundColor(LisnColors.textSecondary)
                        Markdown(correlation.connection)
                            .markdownTheme(.lisnContent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Actionable Ideas

    private var actionableIdeasSection: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(LisnColors.warning)
                Text("Ideas")
                    .font(LisnFont.labelMedium())
                    .foregroundColor(LisnColors.textPrimary)
            }

            ForEach(insight.actionableIdeas, id: \.self) { idea in
                Markdown(idea)
                    .markdownTheme(.lisnContent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Card wrapper for insight used in HomeView results
struct InsightCard: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: LisnSpacing.sm) {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(LisnColors.accent)

                Text("AI Insight")
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Spacer()

                if let emoji = insight.settingEmoji {
                    Text(emoji)
                        .font(.system(size: 16))
                }
            }

            InsightDetailView(insight: insight)
        }
        .padding(LisnSpacing.md)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(
            color: LisnShadow.sm.color,
            radius: LisnShadow.sm.radius,
            x: LisnShadow.sm.x,
            y: LisnShadow.sm.y
        )
    }
}

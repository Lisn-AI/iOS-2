import SwiftUI

/// Inline dark card shown when usage limits are hit
/// Inspired by Pocket's "3/3 FREE CHATS USED" style
struct UpgradePromptCard: View {
    let resourceName: String
    let used: Int
    let limit: Int
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: LisnSpacing.sm) {
            HStack {
                // Counter badge
                Text("\(used)/\(limit)")
                    .font(LisnFont.captionBold())
                    .foregroundStyle(LisnColors.warning)
                    .padding(.horizontal, LisnSpacing.xs)
                    .padding(.vertical, 2)
                    .background(LisnColors.warning.opacity(0.15))
                    .clipShape(Capsule())

                Text("\(resourceName.uppercased()) USED")
                    .font(LisnFont.captionBold())
                    .foregroundStyle(LisnColors.textSecondary)
                    .tracking(0.5)

                Spacer()
            }

            Text("You've reached your free limit. Upgrade to continue using \(resourceName).")
                .font(LisnFont.bodySmall())
                .foregroundStyle(LisnColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onUpgrade) {
                HStack(spacing: LisnSpacing.xs) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 12))
                    Text("Upgrade to continue")
                        .font(LisnFont.labelMedium())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, LisnSpacing.sm)
                .background(LisnColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            }
        }
        .padding(LisnSpacing.md)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}

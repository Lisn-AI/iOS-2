import SwiftUI

struct LisnEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: LisnSpacing.lg) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LisnColors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(LisnColors.accent)
            }

            VStack(spacing: LisnSpacing.xs) {
                Text(title)
                    .font(LisnFont.titleLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Text(subtitle)
                    .font(LisnFont.bodyMedium())
                    .foregroundColor(LisnColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, LisnSpacing.xxl)
            }

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(LisnFont.labelLarge())
                        .foregroundColor(.white)
                        .padding(.horizontal, LisnSpacing.xl)
                        .padding(.vertical, LisnSpacing.sm)
                        .background(LisnColors.accent)
                        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

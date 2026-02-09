import SwiftUI

struct LisnChip: View {
    let text: String
    var icon: String? = nil
    var color: Color = LisnColors.accent
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if let action {
                Button(action: action) {
                    chipContent
                }
                .buttonStyle(.plain)
            } else {
                chipContent
            }
        }
    }

    private var chipContent: some View {
        HStack(spacing: LisnSpacing.xxs) {
            if let icon {
                Image(systemName: icon)
                    .font(LisnFont.caption())
            }
            Text(text)
                .font(LisnFont.caption())
        }
        .padding(.horizontal, LisnSpacing.md)
        .padding(.vertical, LisnSpacing.xs)
        .background(LisnColors.bgSecondary)
        .foregroundColor(LisnColors.textPrimary)
        .clipShape(Capsule())
    }
}

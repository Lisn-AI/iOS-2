import SwiftUI

struct LisnToast: View {
    let message: String
    var type: ToastType = .success

    enum ToastType {
        case success
        case error
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return LisnColors.success
            case .error: return LisnColors.error
            case .info: return LisnColors.info
            }
        }
    }

    var body: some View {
        HStack(spacing: LisnSpacing.sm) {
            Image(systemName: type.icon)
                .foregroundColor(type.color)

            Text(message)
                .font(LisnFont.bodyMedium())
                .foregroundColor(LisnColors.textPrimary)

            Spacer()
        }
        .padding(LisnSpacing.md)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                .stroke(type.color.opacity(0.3), lineWidth: 1)
        )
        .shadow(
            color: LisnShadow.md.color,
            radius: LisnShadow.md.radius,
            x: LisnShadow.md.x,
            y: LisnShadow.md.y
        )
        .padding(.horizontal, LisnSpacing.md)
    }
}

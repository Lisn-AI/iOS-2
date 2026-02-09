import SwiftUI

struct LisnButton: View {
    let title: String
    var icon: String? = nil
    var style: ButtonStyle = .primary
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case ghost
    }

    var body: some View {
        Button(action: {
            LisnHaptics.light()
            action()
        }) {
            HStack(spacing: LisnSpacing.xs) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(LisnFont.labelLarge())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(backgroundColor)
            .foregroundColor(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous))
            .overlay(
                Group {
                    if style == .secondary || style == .ghost {
                        RoundedRectangle(cornerRadius: LisnRadius.md, style: .continuous)
                            .stroke(borderColor, lineWidth: style == .ghost ? 0 : 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return LisnColors.accent
        case .secondary: return LisnColors.bgSecondary
        case .destructive: return LisnColors.error
        case .ghost: return .clear
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary, .destructive: return .white
        case .secondary: return LisnColors.textPrimary
        case .ghost: return LisnColors.accent
        }
    }

    private var borderColor: Color {
        switch style {
        case .secondary: return LisnColors.border
        default: return .clear
        }
    }
}

import SwiftUI

/// Reusable frosted glass pill button matching the premium warm-amber design language
struct GlassButton: View {
    let icon: String
    let label: String
    var accentColor: Color = LisnColors.accent
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        if #available(iOS 26.0, *) {
            iOS26Button
        } else {
            legacyButton
        }
    }

    @available(iOS 26.0, *)
    private var iOS26Button: some View {
        Button {
            LisnHaptics.medium()
            action()
        } label: {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(LisnFont.labelMedium())
            }
            .foregroundColor(isDestructive ? LisnColors.textSecondary : accentColor)
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.vertical, LisnSpacing.sm + 2)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }

    private var legacyButton: some View {
        Button {
            LisnHaptics.medium()
            action()
        } label: {
            HStack(spacing: LisnSpacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(label)
                    .font(LisnFont.labelMedium())
            }
            .foregroundColor(isDestructive ? LisnColors.textSecondary : accentColor)
            .padding(.horizontal, LisnSpacing.lg)
            .padding(.vertical, LisnSpacing.sm + 2)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(
                        isDestructive
                            ? Color.white.opacity(0.1)
                            : accentColor.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: LisnShadow.md.color,
                radius: LisnShadow.md.radius,
                x: LisnShadow.md.x,
                y: LisnShadow.md.y
            )
            .shadow(
                color: isPressed ? LisnShadow.glow.color : .clear,
                radius: isPressed ? LisnShadow.glow.radius : 0,
                x: LisnShadow.glow.x,
                y: LisnShadow.glow.y
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

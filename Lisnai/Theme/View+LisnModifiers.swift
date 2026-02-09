import SwiftUI

extension View {
    func lisnBackground() -> some View {
        self.background(LisnColors.bgPrimary)
    }

    func lisnCardStyle() -> some View {
        self
            .background(LisnColors.bgElevated)
            .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
            .shadow(
                color: LisnShadow.sm.color,
                radius: LisnShadow.sm.radius,
                x: LisnShadow.sm.x,
                y: LisnShadow.sm.y
            )
    }

    func lisnSectionHeader() -> some View {
        self
            .font(LisnFont.labelLarge())
            .foregroundColor(LisnColors.textSecondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}

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

    /// Subtle scroll edge fade — simple background-color gradient overlay.
    /// Pocket-style: content fades smoothly into the background color at edges.
    /// No material blur (which renders as an opaque white band on light backgrounds).
    func scrollEdgeFade(
        top: CGFloat = 24,
        bottom: CGFloat = 24
    ) -> some View {
        self
            .overlay(alignment: .top) {
                if top > 0 {
                    LinearGradient(
                        stops: [
                            .init(color: LisnColors.bgPrimary, location: 0),
                            .init(color: LisnColors.bgPrimary.opacity(0.6), location: 0.5),
                            .init(color: LisnColors.bgPrimary.opacity(0), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: top)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if bottom > 0 {
                    LinearGradient(
                        stops: [
                            .init(color: LisnColors.bgPrimary.opacity(0), location: 0),
                            .init(color: LisnColors.bgPrimary.opacity(0.6), location: 0.5),
                            .init(color: LisnColors.bgPrimary, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottom)
                    .allowsHitTesting(false)
                }
            }
    }
}

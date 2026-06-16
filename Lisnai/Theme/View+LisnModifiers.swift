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

    /// Glass surface for content cards.
    /// iOS 26: native `.glassEffect` (Liquid Glass, refractive translucent).
    /// iOS 17 fallback: `.ultraThinMaterial` + hairline border + subtle shadow.
    /// Apply this as the LAST modifier (per HIG: glass effects must be terminal).
    @ViewBuilder
    func lisnGlassSurface(cornerRadius: CGFloat = LisnRadius.xl) -> some View {
        if #available(iOS 26.0, *) {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LisnColors.bgElevated.opacity(0.4))
                )
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5)
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: 4)
        }
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

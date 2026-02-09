import SwiftUI

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
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

import SwiftUI

struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            content
                .padding(LisnSpacing.md)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: LisnRadius.lg))
        } else {
            content
                .padding(LisnSpacing.md)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous)
                        .stroke(
                            colorScheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.06),
                            lineWidth: 1
                        )
                )
                .shadow(
                    color: colorScheme == .dark ? .clear : .black.opacity(0.04),
                    radius: 8,
                    y: 4
                )
        }
    }
}

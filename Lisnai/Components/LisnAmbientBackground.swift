import SwiftUI

/// A restrained ambient background: a single slow-breathing radial bloom.
///
/// Per DESIGN.md Part 4, this REPLACES:
/// - The iOS 18 MeshGradient + iOS 17 LinearGradient fallback in OnboardingCoordinator
/// - The 5-particle Vortex ambient system in OnboardingWelcomeScreen
///
/// One bloom per screen. Period. The previous implementation used multiple
/// animated effects competing for attention. This is what "Ambient AI" looks like:
/// quiet, alive, ownable. Like Granola or Krea.
///
/// Usage:
/// ```swift
/// ZStack {
///   LisnAmbientBackground()
///   // your content
/// }
/// ```
struct LisnAmbientBackground: View {
    /// Anchor of the bloom relative to the view bounds (0...1)
    var anchor: UnitPoint = .center

    /// Bloom intensity (opacity of the inner color). Default produces a soft, warm wash.
    var intensity: Double = 0.18

    /// Loop duration for the breathing effect
    var period: Double = 10.0

    @State private var breath: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Base — warm cream
            LisnColors.bgPrimary
                .ignoresSafeArea()

            // Single radial bloom that breathes slowly
            GeometryReader { proxy in
                let radius = max(proxy.size.width, proxy.size.height) * (breath ? 1.0 : 0.85)
                RadialGradient(
                    colors: [
                        LisnColors.orbGlow.opacity(intensity),
                        LisnColors.orbLight.opacity(intensity * 0.4),
                        Color.clear
                    ],
                    center: anchor,
                    startRadius: 30,
                    endRadius: radius
                )
                .opacity(breath ? 1.0 : 0.75)
                .blendMode(.normal)
                .ignoresSafeArea()
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: period).repeatForever(autoreverses: true)) {
                breath = true
            }
        }
    }
}

#Preview("Ambient background") {
    ZStack {
        LisnAmbientBackground()
        VStack(spacing: LisnSpacing.lg) {
            Text("Remember")
                .font(LisnFont.displayLarge())
                .foregroundStyle(
                    LinearGradient(
                        colors: [LisnColors.accent, LisnColors.orbDark],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text("Everything.")
                .font(LisnFont.displayLarge())
                .foregroundColor(LisnColors.textPrimary)
        }
    }
}

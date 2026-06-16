import SwiftUI

/// A circular progress indicator that draws around as progress advances.
///
/// Per DESIGN.md Part 5: replaces the floating percentage numbers that
/// previously appeared mid-screen during onboarding's processing phase.
/// Numbers in the middle of a screen are dev-placeholder energy — this
/// is a designed moment instead.
///
/// Rules:
/// - No text inside the ring (numerals never appear mid-screen)
/// - Optional caption below ("Analyzing…") in tertiary text
/// - Track is barely visible; only the progress stroke carries weight
/// - Active state breathes subtly so the user knows work is happening
struct LisnProgressRing: View {
    /// Progress value 0.0 → 1.0
    let progress: Double
    /// Outer diameter in points
    var size: CGFloat = 80
    /// Stroke thickness; defaults to 8% of size
    var lineWidth: CGFloat? = nil
    /// Optional caption below the ring
    var caption: String? = nil
    /// When true, the ring breathes subtly (reassures user that work is ongoing)
    var isAnimating: Bool = true

    @State private var breathPhase: Bool = false

    private var resolvedLineWidth: CGFloat {
        lineWidth ?? max(4, size * 0.08)
    }

    private var clampedProgress: Double {
        // Use smallestNonzeroMagnitude lower bound so the round cap renders
        // immediately on first draw instead of popping in
        max(.leastNonzeroMagnitude, min(progress, 1.0))
    }

    var body: some View {
        VStack(spacing: LisnSpacing.sm) {
            ZStack {
                // Track — barely visible
                Circle()
                    .stroke(
                        LisnColors.accent.opacity(0.10),
                        style: StrokeStyle(lineWidth: resolvedLineWidth, lineCap: .round)
                    )

                // Active progress arc
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        AngularGradient(
                            colors: [LisnColors.orbLight, LisnColors.orbDark, LisnColors.orbLight],
                            center: .center,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(270)
                        ),
                        style: StrokeStyle(lineWidth: resolvedLineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 0.85), value: clampedProgress)
            }
            .frame(width: size, height: size)
            .scaleEffect(isAnimating && breathPhase ? 1.02 : 1.0)
            .shadow(
                color: LisnColors.accent.opacity(isAnimating ? 0.25 : 0),
                radius: 12,
                x: 0,
                y: 0
            )
            .onAppear {
                guard isAnimating else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    breathPhase = true
                }
            }

            if let caption {
                Text(caption)
                    .font(LisnFont.bodySmall())
                    .foregroundColor(LisnColors.textTertiary)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id(caption)
                    .animation(.easeInOut(duration: 0.35), value: caption)
            }
        }
    }
}

// MARK: - Preview

#Preview("Ring states") {
    VStack(spacing: 40) {
        LisnProgressRing(progress: 0.3, size: 80, caption: "Analyzing…")
        LisnProgressRing(progress: 0.7, size: 100, caption: "Extracting insights")
        LisnProgressRing(progress: 1.0, size: 64, caption: nil, isAnimating: false)
    }
    .padding(40)
    .background(LisnColors.bgPrimary)
}

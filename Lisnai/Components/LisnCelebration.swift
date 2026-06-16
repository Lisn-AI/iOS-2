import SwiftUI

/// A restrained "premium pulse" celebration moment.
///
/// Per DESIGN.md Part 3, this REPLACES Vortex confetti everywhere in the app.
/// Six layered stages:
///   1. Card scales 0.97 → 1.0 (spring, ~800ms)
///   2. Inner glow opacity 0 → 0.3 → 0.15 (ease-out, ~1200ms)
///   3. Border accent stroke draws clockwise from 12 o'clock (~600ms)
///   4. 3-5 ambient orbs drift upward from bottom (accent.opacity 0.2, 60pt blur, 2-3s)
///   5. Subtle checkmark badge fades in at top-right corner (~200ms)
///   6. Hold ~1.5s after all stages, then everything releases
///
/// No confetti. No downward particles. Premium ≠ noisy.
///
/// Usage:
/// ```swift
/// VStack { ... }
///   .lisnCelebration(isActive: $celebrate, showCheckmark: true)
/// ```
struct LisnCelebrationModifier: ViewModifier {
    @Binding var isActive: Bool
    var showCheckmark: Bool = true
    var cornerRadius: CGFloat = LisnRadius.lg

    @State private var cardScale: CGFloat = 1.0
    @State private var innerGlowOpacity: Double = 0
    @State private var borderProgress: CGFloat = 0
    @State private var orbs: [DriftingOrb] = []
    @State private var checkmarkScale: CGFloat = 0
    @State private var checkmarkOpacity: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(cardScale)
            .overlay(innerGlow)
            .overlay(borderStroke)
            .overlay(checkmark, alignment: .topTrailing)
            .background(orbField, alignment: .bottom)
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    runCelebration()
                } else {
                    reset()
                }
            }
    }

    // MARK: - Layers

    private var innerGlow: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                RadialGradient(
                    colors: [
                        LisnColors.accent.opacity(innerGlowOpacity),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 10,
                    endRadius: 200
                )
            )
            .allowsHitTesting(false)
    }

    private var borderStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .trim(from: 0, to: borderProgress)
            .stroke(
                LinearGradient(
                    colors: [LisnColors.orbLight, LisnColors.accent, LisnColors.orbDark],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )
            .rotationEffect(.degrees(-90))  // start from 12 o'clock
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var checkmark: some View {
        if showCheckmark {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, LisnColors.success)
                .font(.system(size: 22, weight: .semibold))
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)
                .padding(LisnSpacing.sm)
                .allowsHitTesting(false)
        }
    }

    private var orbField: some View {
        ZStack {
            ForEach(orbs) { orb in
                Circle()
                    .fill(LisnColors.accent.opacity(0.18))
                    .frame(width: orb.size, height: orb.size)
                    .blur(radius: 30)
                    .offset(x: orb.xOffset, y: orb.yOffset)
                    .opacity(orb.opacity)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Choreography

    private func runCelebration() {
        guard !reduceMotion else {
            // Reduced motion: instant glow + checkmark, no movement
            innerGlowOpacity = 0.15
            borderProgress = 1.0
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
            return
        }

        // Stage 1: card scale
        cardScale = 0.97
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            cardScale = 1.0
        }

        // Stage 2: inner glow (asymmetric — rise then settle)
        withAnimation(.easeOut(duration: 0.5)) {
            innerGlowOpacity = 0.30
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeInOut(duration: 0.5)) {
                innerGlowOpacity = 0.15
            }
        }

        // Stage 3: border draws clockwise
        withAnimation(.easeInOut(duration: 0.6).delay(0.1)) {
            borderProgress = 1.0
        }

        // Stage 4: launch ambient orbs from bottom
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            launchOrbs()
        }

        // Stage 5: checkmark badge appears
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                checkmarkScale = 1.0
                checkmarkOpacity = 1.0
            }
        }
    }

    private func launchOrbs() {
        let count = Int.random(in: 3...5)
        orbs = (0..<count).map { _ in
            DriftingOrb(
                id: UUID(),
                size: CGFloat.random(in: 50...90),
                xOffset: CGFloat.random(in: -80...80),
                yOffset: 40,  // start below
                opacity: 0
            )
        }

        // Animate each orb drifting up + fading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            for index in orbs.indices {
                let duration = Double.random(in: 2.0...3.0)
                withAnimation(.easeOut(duration: 0.4)) {
                    orbs[index].opacity = 0.9
                }
                withAnimation(.easeOut(duration: duration).delay(0.05)) {
                    orbs[index].yOffset = -CGFloat.random(in: 60...140)
                }
                withAnimation(.easeIn(duration: 1.2).delay(duration - 1.2)) {
                    orbs[index].opacity = 0
                }
            }
        }

        // Cleanup orbs after they finish
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            orbs.removeAll()
        }
    }

    private func reset() {
        withAnimation(.easeOut(duration: 0.3)) {
            innerGlowOpacity = 0
            borderProgress = 0
            checkmarkScale = 0
            checkmarkOpacity = 0
        }
        orbs.removeAll()
    }
}

// MARK: - Drifting orb model

private struct DriftingOrb: Identifiable {
    let id: UUID
    var size: CGFloat
    var xOffset: CGFloat
    var yOffset: CGFloat
    var opacity: Double
}

// MARK: - View extension

extension View {
    /// Apply the LisnCelebration premium-pulse effect. Triggered by a Binding<Bool>
    /// so you can toggle it on completion of any moment that deserves celebration.
    func lisnCelebration(
        isActive: Binding<Bool>,
        showCheckmark: Bool = true,
        cornerRadius: CGFloat = LisnRadius.lg
    ) -> some View {
        modifier(LisnCelebrationModifier(
            isActive: isActive,
            showCheckmark: showCheckmark,
            cornerRadius: cornerRadius
        ))
    }
}

// MARK: - Preview

#Preview("Celebration toggle") {
    struct PreviewHost: View {
        @State private var celebrate = false
        var body: some View {
            VStack(spacing: 40) {
                VStack(alignment: .leading, spacing: LisnSpacing.md) {
                    Text("Analysis Complete")
                        .font(LisnFont.titleLarge())
                        .foregroundColor(LisnColors.textPrimary)
                    Text("Lisn found 2 insights and 2 actions in your recording.")
                        .font(LisnFont.bodyMedium())
                        .foregroundColor(LisnColors.textSecondary)
                }
                .padding(LisnSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LisnColors.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg))
                .lisnCelebration(isActive: $celebrate)

                Button("Toggle celebration") {
                    celebrate.toggle()
                }
                .padding()
            }
            .padding(40)
            .background(LisnColors.bgPrimary)
        }
    }
    return PreviewHost()
}

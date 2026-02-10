import SwiftUI

/// Premium recording button with animated gradient, shimmer, and audio-reactive pulsing.
struct RecordingOrb: View {
    let isRecording: Bool
    let audioLevel: CGFloat
    let isPaused: Bool
    let action: () -> Void

    @State private var isPressed = false
    @State private var breathe = false
    @State private var shimmerAngle: Double = 0
    @State private var glowPulse = false

    private let orbSize: CGFloat = 120

    private var iconName: String {
        if isPaused {
            return "phone.fill"
        } else if isRecording {
            return "stop.fill"
        } else {
            return "waveform"
        }
    }

    /// Audio-driven scale for the orb — pulsates with voice
    private var liveScale: CGFloat {
        if isRecording && !isPaused {
            return 1.0 + audioLevel * 0.12
        } else if !isRecording {
            return breathe ? 1.08 : 0.95
        }
        return 1.0
    }

    /// Audio-driven shadow radius
    private var liveGlowRadius: CGFloat {
        if isRecording && !isPaused {
            return 16 + audioLevel * 22
        }
        return breathe ? 20 : 8
    }

    /// Audio-driven glow opacity
    private var liveGlowOpacity: Double {
        if isRecording && !isPaused {
            return 0.3 + Double(audioLevel) * 0.3
        }
        return breathe ? 0.4 : 0.15
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // === IDLE: Breathing ambient rings ===
                if !isRecording {
                    // Inner ring — more visible, pulses with orb
                    Circle()
                        .stroke(LisnColors.accent.opacity(breathe ? 0.12 : 0.04), lineWidth: 1.5)
                        .frame(width: orbSize + 30, height: orbSize + 30)
                        .scaleEffect(breathe ? 1.12 : 0.95)

                    // Outer ring — wider reach, slower feel
                    Circle()
                        .stroke(LisnColors.accent.opacity(breathe ? 0.07 : 0.02), lineWidth: 1)
                        .frame(width: orbSize + 60, height: orbSize + 60)
                        .scaleEffect(breathe ? 1.15 : 0.92)

                    // Soft radial glow that breathes
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    LisnColors.orbGlow.opacity(breathe ? 0.12 : 0.03),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: orbSize * 0.5,
                                endRadius: orbSize * (breathe ? 1.1 : 0.8)
                            )
                        )
                        .frame(width: orbSize * 2.4, height: orbSize * 2.4)
                }

                // === RECORDING: Audio-reactive radial glow ===
                if isRecording && !isPaused {
                    // Outer pulsating halo
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    LisnColors.accent.opacity(0.18 + Double(audioLevel) * 0.25),
                                    LisnColors.orbLight.opacity(0.06 + Double(audioLevel) * 0.12),
                                    Color.clear
                                ],
                                center: .center,
                                startRadius: orbSize * 0.4,
                                endRadius: orbSize * 1.2
                            )
                        )
                        .frame(width: orbSize * 2.6, height: orbSize * 2.6)
                        .scaleEffect(1.0 + audioLevel * 0.15 + (glowPulse ? 0.05 : 0.0))
                }

                // === MAIN CIRCLE ===
                Circle()
                    .fill(orbGradient)
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(liveScale)
                    .shadow(
                        color: LisnColors.orbGlow.opacity(isPaused ? 0 : liveGlowOpacity),
                        radius: liveGlowRadius,
                        x: 0,
                        y: isRecording ? 2 : 6
                    )

                // Shimmer — rotating angular highlight
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(isRecording ? 0.18 : 0.10),
                                .white.opacity(0.0),
                                .white.opacity(0.0),
                                .white.opacity(isRecording ? 0.08 : 0.04),
                                .white.opacity(0.0)
                            ],
                            center: .center,
                            angle: .degrees(shimmerAngle)
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(liveScale)
                    .blendMode(.overlay)

                // Specular highlight — glass reflection
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white.opacity(0.22),
                                .white.opacity(0.0)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.28),
                            startRadius: 0,
                            endRadius: orbSize * 0.45
                        )
                    )
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(liveScale)
                    .blendMode(.softLight)

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 1)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: orbSize * 2.6, height: orbSize * 2.6)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                        isPressed = false
                    }
                }
        )
        .scaleEffect(isPressed ? 0.88 : 1.0)
        // Fast spring for audio reactivity — makes pulsation feel alive
        .animation(.spring(response: 0.12, dampingFraction: 0.65), value: audioLevel)
        .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: breathe)
        .onAppear {
            breathe = true
            startShimmer()
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startGlowPulse()
            } else {
                glowPulse = false
            }
        }
    }

    // MARK: - Gradient

    private var orbGradient: some ShapeStyle {
        if isPaused {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [LisnColors.paused, LisnColors.paused.opacity(0.75)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [LisnColors.orbLight, LisnColors.accent, LisnColors.orbDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    // MARK: - Animations

    private func startShimmer() {
        withAnimation(.linear(duration: 5.0).repeatForever(autoreverses: false)) {
            shimmerAngle = 360
        }
    }

    private func startGlowPulse() {
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }
}

import SwiftUI

/// Audio-reactive aurora shimmer background.
/// Soft blurred color blobs drift organically and pulse with voice input,
/// creating an ambient atmosphere during recording.
struct EdgeGlowEffect: View {
    let isActive: Bool
    let audioLevel: CGFloat

    // Phase drivers for organic movement
    @State private var phase: Double = 0
    @State private var colorPhase: Double = 0

    /// Audio-driven intensity (0.3 at silence → 1.0 at loud)
    private var intensity: Double {
        0.3 + Double(audioLevel) * 0.7
    }

    /// Audio-driven scale pulse
    private var audioPulse: CGFloat {
        1.0 + audioLevel * 0.15
    }

    // MARK: - Color Palette
    // Warm tones that complement the #FFFDF7 background and sage green accent

    private var blobColors: [Color] {
        let hueShift = colorPhase * 0.08 // subtle hue drift over time
        return [
            // Soft lavender
            Color(
                hue: 0.72 + hueShift,
                saturation: 0.35,
                brightness: 0.92
            ),
            // Warm peach
            Color(
                hue: 0.05 + hueShift * 0.5,
                saturation: 0.30,
                brightness: 0.95
            ),
            // Sage mint (matches app accent family)
            Color(
                hue: 0.42 + hueShift * 0.3,
                saturation: 0.28,
                brightness: 0.88
            ),
            // Soft amber/gold
            Color(
                hue: 0.10 + hueShift * 0.4,
                saturation: 0.32,
                brightness: 0.94
            ),
            // Dusty rose
            Color(
                hue: 0.95 + hueShift * 0.6,
                saturation: 0.25,
                brightness: 0.90
            ),
        ]
    }

    var body: some View {
        if isActive {
            let screenW = UIScreen.main.bounds.width
            let screenH = UIScreen.main.bounds.height

            Canvas { context, size in
                // Draw nothing — we use overlay blobs instead for animation
            }
            .frame(width: screenW, height: screenH)
            .background(Color.clear)
            .overlay {
                ZStack {
                    // Blob 1 — top-left drift
                    shimmerBlob(
                        color: blobColors[0],
                        size: 280 * audioPulse,
                        x: screenW * (0.15 + 0.12 * sin(phase * 0.7)),
                        y: screenH * (0.18 + 0.08 * cos(phase * 0.5)),
                        blur: 70
                    )

                    // Blob 2 — center-right drift
                    shimmerBlob(
                        color: blobColors[1],
                        size: 240 * audioPulse,
                        x: screenW * (0.78 + 0.10 * cos(phase * 0.6)),
                        y: screenH * (0.35 + 0.10 * sin(phase * 0.8)),
                        blur: 65
                    )

                    // Blob 3 — bottom-center drift
                    shimmerBlob(
                        color: blobColors[2],
                        size: 300 * audioPulse,
                        x: screenW * (0.45 + 0.15 * sin(phase * 0.9)),
                        y: screenH * (0.72 + 0.08 * cos(phase * 0.4)),
                        blur: 80
                    )

                    // Blob 4 — top-right accent
                    shimmerBlob(
                        color: blobColors[3],
                        size: 200 * audioPulse,
                        x: screenW * (0.85 + 0.08 * sin(phase * 1.1)),
                        y: screenH * (0.12 + 0.06 * cos(phase * 0.7)),
                        blur: 60
                    )

                    // Blob 5 — bottom-left accent
                    shimmerBlob(
                        color: blobColors[4],
                        size: 220 * audioPulse,
                        x: screenW * (0.20 + 0.10 * cos(phase * 0.5)),
                        y: screenH * (0.82 + 0.06 * sin(phase * 0.9)),
                        blur: 70
                    )
                }
            }
            .opacity(intensity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.15), value: audioLevel)
            .onAppear {
                // Slow continuous drift
                withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                    phase = .pi * 2
                }
                // Even slower color cycling
                withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
                    colorPhase = 1.0
                }
            }
        }
    }

    // MARK: - Shimmer Blob

    private func shimmerBlob(
        color: Color,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat
    ) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        color.opacity(0.6),
                        color.opacity(0.25),
                        color.opacity(0.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: blur)
            .position(x: x, y: y)
    }
}

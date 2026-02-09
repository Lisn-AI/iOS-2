import SwiftUI

/// A clean, flat 2D recording button with ripple animations.
struct RecordingOrb: View {
    let isRecording: Bool
    let audioLevel: CGFloat
    let isPaused: Bool
    let action: () -> Void

    @State private var isPressed = false
    @State private var breathe = false
    @State private var ripple1: CGFloat = 0
    @State private var ripple2: CGFloat = 0
    @State private var ripple3: CGFloat = 0

    private let orbSize: CGFloat = 120

    private var fillColor: Color {
        if isPaused {
            return .orange
        } else if isRecording {
            return LisnColors.accent
        } else {
            return LisnColors.accent.opacity(0.85)
        }
    }

    private var iconName: String {
        if isPaused {
            return "phone"
        } else if isRecording {
            return "stop.fill"
        } else {
            return "mic"
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Ripple rings (recording only)
                if isRecording && !isPaused {
                    rippleRing(scale: ripple1, opacity: rippleOpacity(ripple1))
                    rippleRing(scale: ripple2, opacity: rippleOpacity(ripple2))
                    rippleRing(scale: ripple3, opacity: rippleOpacity(ripple3))
                }

                // Main circle
                Circle()
                    .fill(fillColor)
                    .frame(width: orbSize, height: orbSize)
                    .scaleEffect(breatheScale)

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: orbSize * 2, height: orbSize * 2)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .onAppear { startBreathing() }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startRipples()
            }
        }
    }

    // MARK: - Breathing

    private var breatheScale: CGFloat {
        if isRecording && !isPaused {
            return 1.0 + audioLevel * 0.08
        } else if !isRecording {
            return breathe ? 1.04 : 1.0
        } else {
            return 1.0
        }
    }

    private func startBreathing() {
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            breathe = true
        }
    }

    // MARK: - Ripples

    private func rippleRing(scale: CGFloat, opacity: Double) -> some View {
        Circle()
            .stroke(fillColor, lineWidth: 2)
            .frame(width: orbSize, height: orbSize)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    private func rippleOpacity(_ scale: CGFloat) -> Double {
        let audioBoost = Double(audioLevel) * 0.3
        let baseOpacity = max(0, 1.0 - Double((scale - 1.0) / 0.8))
        return baseOpacity * (0.3 + audioBoost)
    }

    private func startRipples() {
        ripple1 = 1.0
        ripple2 = 1.0
        ripple3 = 1.0

        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            ripple1 = 1.8
        }
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(0.6)) {
            ripple2 = 1.8
        }
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(1.2)) {
            ripple3 = 1.8
        }
    }
}

import SwiftUI
import Lottie

/// Animated processing card shown while a recording is being processed.
/// Cycles through 3 Lottie animations with staggered status text.
struct ProcessingAnimationCard: View {
    @State private var statusIndex = 0
    @State private var lottieIndex = 0
    @State private var appeared = false

    private let statuses = [
        "Transcribing your voice...",
        "Extracting key insights...",
        "Building your summary...",
        "Almost there...",
    ]

    private let lottieNames = [
        "planet-orbit",
        "cat-playing",
        "vintage-car",
    ]

    var body: some View {
        VStack(spacing: LisnSpacing.md) {
            // Lottie animation — cycles every 6 seconds
            LottieView(animation: .named(lottieNames[lottieIndex]))
                .playing(loopMode: .loop)
                .frame(width: 80, height: 80)
                .id(lottieIndex)
                .transition(.opacity)

            // Status text — changes every 4 seconds
            VStack(spacing: LisnSpacing.xxxs) {
                Text("Processing")
                    .font(LisnFont.labelLarge())
                    .foregroundColor(LisnColors.textPrimary)

                Text(statuses[statusIndex])
                    .font(LisnFont.caption())
                    .foregroundColor(LisnColors.textSecondary)
                    .transition(.opacity)
                    .id(statusIndex)
                    .animation(.easeInOut(duration: 0.3), value: statusIndex)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LisnSpacing.lg)
        .padding(.horizontal, LisnSpacing.md)
        .background(LisnColors.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: LisnRadius.lg, style: .continuous))
        .shadow(
            color: LisnShadow.md.color,
            radius: LisnShadow.md.radius,
            x: LisnShadow.md.x,
            y: LisnShadow.md.y
        )
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            startCycling()
        }
    }

    private func startCycling() {
        // Cycle status text every 4 seconds
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    statusIndex = (statusIndex + 1) % statuses.count
                }
            }
        }

        // Cycle Lottie animation every 6 seconds
        Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.4)) {
                    lottieIndex = (lottieIndex + 1) % lottieNames.count
                }
            }
        }
    }
}

#Preview {
    ProcessingAnimationCard()
        .padding()
        .background(LisnColors.bgPrimary)
}

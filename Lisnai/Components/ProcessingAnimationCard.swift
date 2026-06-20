import SwiftUI
import Lottie

/// Full-screen processing animation shown while a recording is being processed.
/// Big standalone Lottie animation with cycling status text — no card, no box.
struct ProcessingAnimationCard: View {
    @State private var statusIndex = 0
    @State private var lottieIndex = 0
    @State private var appeared = false
    @State private var pulseScale: CGFloat = 1.0

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
        VStack(spacing: LisnSpacing.xl) {
            Spacer()

            // Big standalone Lottie animation — no card, no box
            LottieView(animation: .named(lottieNames[lottieIndex]))
                .playing(loopMode: .loop)
                .frame(width: 200, height: 200)
                .scaleEffect(pulseScale)
                .id(lottieIndex)

            // Status text — large, centered
            VStack(spacing: LisnSpacing.xs) {
                Text("Processing")
                    .font(.custom("Inter-Bold", size: 22))
                    .foregroundColor(LisnColors.textPrimary)

                Text(statuses[statusIndex])
                    .font(.custom("Inter-Regular", size: 16))
                    .foregroundColor(LisnColors.textSecondary)
                    .id(statusIndex)
                    .transition(.opacity)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) { appeared = true }
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.05
            }
            startCycling()
        }
    }

    private func startCycling() {
        Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    statusIndex = (statusIndex + 1) % statuses.count
                }
            }
        }

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
        .background(LisnColors.bgPrimary)
}

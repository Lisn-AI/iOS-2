import SwiftUI
import Lottie

private let iconToSFSymbol: [String: String] = [
    "airplane": "airplane",
    "ambulance": "cross.case.fill",
    "apple": "apple.logo",
    "atom": "atom",
    "basket": "basket.fill",
    "broadcast": "antenna.radiowaves.left.and.right",
    "broom": "leaf.fill",
    "bulb": "lightbulb.fill",
    "cat": "cat.fill",
    "champagne": "party.popper.fill",
    "coffee": "cup.and.saucer.fill",
    "computer": "desktopcomputer",
    "concert": "music.mic",
    "delivery": "shippingbox.fill",
    "department": "building.2.fill",
    "digger": "hammer.fill",
    "doctor": "stethoscope",
    "edit-document": "doc.text.fill",
    "eye": "eye.fill",
    "face-id": "faceid",
    "fastfood": "fork.knife",
    "gears": "gearshape.2.fill",
    "globe": "globe",
    "gym": "dumbbell.fill",
    "handshake": "hand.raised.fill",
    "headphones": "headphones",
    "hospital": "cross.case.fill",
    "investment": "chart.line.uptrend.xyaxis",
    "key": "key.fill",
    "map": "map.fill",
    "meeting": "person.3.fill",
    "microphone": "mic.fill",
    "microscope": "magnifyingglass",
    "money-bag": "dollarsign.circle.fill",
    "music-album": "opticaldisc.fill",
    "music-note": "music.note",
    "neighborhood": "house.fill",
    "piggy-bank": "banknote.fill",
    "project-management": "list.clipboard.fill",
    "pushups": "figure.strengthtraining.traditional",
    "rain": "cloud.rain.fill",
    "receipt": "receipt",
    "responsive": "iphone",
    "rocket": "paperplane.fill",
    "sleep": "moon.zzz.fill",
    "smartphone": "phone.fill",
    "social-media": "bubble.left.and.bubble.right.fill",
    "speaker": "speaker.wave.3.fill",
    "sun": "sun.max.fill",
    "train": "tram.fill",
    "travel": "suitcase.fill",
    "typewriter": "keyboard",
    "virus": "allergens",
    "windmill": "wind",
    "wine": "wineglass.fill",
    "x-ray": "xray",
    "yoga": "figure.yoga",
]

struct LottieIconView: View {
    let iconName: String
    var size: CGFloat = 44
    var loopMode: LottieLoopMode = .playOnce

    var body: some View {
        if LottieAnimation.named(iconName, bundle: .main) != nil {
            LottieView(animation: .named(iconName, bundle: .main))
                .playbackMode(.playing(.fromProgress(0, toProgress: 1, loopMode: loopMode)))
                .animationSpeed(0.7)
                .frame(width: size, height: size)
        } else {
            fallbackIcon
        }
    }

    private var sfSymbol: String {
        iconToSFSymbol[iconName] ?? "waveform"
    }

    private var fallbackIcon: some View {
        ZStack {
            Circle()
                .fill(LisnColors.bgSecondary)
                .frame(width: size, height: size)

            Image(systemName: sfSymbol)
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundColor(LisnColors.accent)
                .symbolEffect(.pulse.byLayer, options: .repeating.speed(0.3))
        }
    }
}

struct RecordingIconView: View {
    let recording: Recording
    var size: CGFloat = 44

    var body: some View {
        LottieIconView(iconName: recording.icon ?? "microphone", size: size)
    }
}

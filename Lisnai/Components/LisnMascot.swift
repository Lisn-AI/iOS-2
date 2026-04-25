import SwiftUI
import RiveRuntime

// MARK: - Emotion States

enum MascotEmotion: String, CaseIterable {
    case idle
    case greeting
    case encouraging
    case thoughtful
    case listening
    case excited
    case celebrating
    case inviting
    case reading
    case smirking
    case pointing
}

// MARK: - Rive Input Names (from mascot-upy.riv state machine)

private enum RiveInput {
    static let xBody = "X body"
    static let yBody = "Y body"
    static let xHead = "X tete"
    static let yHead = "Y tete"
    static let xBrows = "X sourcils"
    static let yBrows = "Y sourcils"
    static let eyeLash = "rotation cil"
    static let detectMouse = "detect mouse"
    static let idleWelcome = "idle accueil"
    static let followEye0 = "follow eye 0"
    static let followEye1 = "follow eye 1"
}

// MARK: - Lisn Mascot (Rive-Powered)

/// Interactive mascot powered by a Rive state machine.
/// Controls body tilt, head direction, eyebrow expression,
/// and eye tracking via numeric inputs.
struct LisnMascot: View {
    let emotion: MascotEmotion
    let size: CGFloat

    @StateObject private var riveVM = RiveViewModel(
        fileName: "lisn_mascot",
        stateMachineName: "State Machine 1",
        autoPlay: true
    )

    @State private var started = false

    var body: some View {
        riveVM.view()
            .frame(width: size, height: size)
            .onAppear {
                guard !started else { return }
                started = true
                configureInitialState()
                applyEmotion(emotion)
                scheduleEyeWander()
            }
            .onChange(of: emotion) { _, newEmotion in
                applyEmotion(newEmotion)
            }
    }

    // MARK: - Initial Setup

    private func configureInitialState() {
        riveVM.setInput(RiveInput.detectMouse, value: true)
        riveVM.setInput(RiveInput.followEye1, value: 1.0)
    }

    // MARK: - Eye Wander (keeps mascot feeling alive)

    private func scheduleEyeWander() {
        let delay = Double.random(in: 1.5...3.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard started else { return }

            // Don't override emotion-specific gaze
            guard emotion == .idle || emotion == .greeting || emotion == .inviting else {
                scheduleEyeWander()
                return
            }

            let x = Double.random(in: -20...20)
            let y = Double.random(in: -12...12)

            riveVM.setInput(RiveInput.xHead, value: x)
            riveVM.setInput(RiveInput.yHead, value: y)

            // Occasionally snap back to center
            if Bool.random() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    riveVM.setInput(RiveInput.xHead, value: Double.random(in: -3...3))
                    riveVM.setInput(RiveInput.yHead, value: Double.random(in: -2...2))
                }
            }

            scheduleEyeWander()
        }
    }

    // MARK: - Emotion Presets

    /// Maps each emotion to a combination of Rive inputs that create
    /// distinct poses — body lean, head direction, eyebrow expression.
    private func applyEmotion(_ emotion: MascotEmotion) {
        resetPose()

        switch emotion {
        case .idle:
            // Default state — idle animation handles breathing + blinking
            break

        case .greeting:
            // Friendly wave — eyebrows up, slight body tilt
            riveVM.setInput(RiveInput.yBrows, value: 10.0)
            riveVM.setInput(RiveInput.xBody, value: 3.0)
            riveVM.setInput(RiveInput.yBody, value: -3.0)

        case .encouraging:
            // Supportive nod — brows up, lean forward
            riveVM.setInput(RiveInput.yBrows, value: 8.0)
            riveVM.setInput(RiveInput.yBody, value: -5.0)
            riveVM.setInput(RiveInput.xHead, value: 5.0)

        case .thoughtful:
            // Pondering — head tilted, looking up-left
            riveVM.setInput(RiveInput.xHead, value: -12.0)
            riveVM.setInput(RiveInput.yHead, value: -5.0)
            riveVM.setInput(RiveInput.yBrows, value: -3.0)
            riveVM.setInput(RiveInput.xBrows, value: -4.0)

        case .listening:
            // Attentive — head slightly down, leaning in
            riveVM.setInput(RiveInput.yHead, value: 6.0)
            riveVM.setInput(RiveInput.yBody, value: 3.0)
            riveVM.setInput(RiveInput.eyeLash, value: 12.0)

        case .excited:
            // Surprise — brows way up, body bounces up
            riveVM.setInput(RiveInput.yBrows, value: 18.0)
            riveVM.setInput(RiveInput.yBody, value: -10.0)
            riveVM.setInput(RiveInput.xBody, value: 2.0)

        case .celebrating:
            // Party — brows up, body sway, bouncy
            riveVM.setInput(RiveInput.yBrows, value: 14.0)
            riveVM.setInput(RiveInput.xBody, value: 6.0)
            riveVM.setInput(RiveInput.yBody, value: -7.0)

        case .inviting:
            // Welcoming — open lean, friendly brows
            riveVM.setInput(RiveInput.xBody, value: -4.0)
            riveVM.setInput(RiveInput.yBrows, value: 6.0)
            riveVM.setInput(RiveInput.yBody, value: -3.0)

        case .reading:
            // Eyes down at book, focused brows
            riveVM.setInput(RiveInput.yHead, value: 18.0)
            riveVM.setInput(RiveInput.xHead, value: -4.0)
            riveVM.setInput(RiveInput.yBrows, value: -2.0)

        case .smirking:
            // Sly confidence — head tilted, one-brow-up effect
            riveVM.setInput(RiveInput.xHead, value: 10.0)
            riveVM.setInput(RiveInput.yBrows, value: 5.0)
            riveVM.setInput(RiveInput.xBrows, value: 8.0)
            riveVM.setInput(RiveInput.yBody, value: -2.0)

        case .pointing:
            // Directing attention — head turned, body follows
            riveVM.setInput(RiveInput.xHead, value: 20.0)
            riveVM.setInput(RiveInput.xBody, value: 8.0)
            riveVM.setInput(RiveInput.yBrows, value: 5.0)
        }
    }

    private func resetPose() {
        riveVM.setInput(RiveInput.xBody, value: 0.0)
        riveVM.setInput(RiveInput.yBody, value: 0.0)
        riveVM.setInput(RiveInput.xHead, value: 0.0)
        riveVM.setInput(RiveInput.yHead, value: 0.0)
        riveVM.setInput(RiveInput.xBrows, value: 0.0)
        riveVM.setInput(RiveInput.yBrows, value: 0.0)
        riveVM.setInput(RiveInput.eyeLash, value: 0.0)
    }
}

// MARK: - Preview

#Preview("All Emotions") {
    ScrollView {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 20) {
            ForEach(MascotEmotion.allCases, id: \.rawValue) { emotion in
                VStack(spacing: 6) {
                    LisnMascot(emotion: emotion, size: 150)
                        .frame(height: 170)

                    Text(emotion.rawValue)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(LisnColors.textSecondary)
                }
                .padding(.vertical, 6)
            }
        }
        .padding()
    }
    .background(LisnColors.bgPrimary)
}

#Preview("Interactive") {
    struct InteractivePreview: View {
        @State private var emotion: MascotEmotion = .idle

        var body: some View {
            VStack(spacing: 30) {
                LisnMascot(emotion: emotion, size: 250)
                    .onTapGesture {
                        emotion = .excited
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            emotion = .greeting
                        }
                    }

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(MascotEmotion.allCases, id: \.rawValue) { e in
                            Button(e.rawValue) { emotion = e }
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(emotion == e
                                              ? LisnColors.accent
                                              : LisnColors.bgElevated)
                                )
                                .foregroundColor(emotion == e ? .white : LisnColors.textPrimary)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LisnColors.bgPrimary)
        }
    }
    return InteractivePreview()
}

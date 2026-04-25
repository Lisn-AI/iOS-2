import SwiftUI

// MARK: - Rive Mascot Wrapper (Future)
//
// When the Rive .riv file is created in the Rive editor, uncomment
// the RiveRuntime import and RiveLisnMascot below, then switch
// OnboardingWelcomeScreen (and other screens) to use it.
//
// Rive Editor Setup Guide:
// ========================
// 1. Create artboard "LisnMascot" (300x300)
//
// 2. Design character layers:
//    - body (rounded rectangle, amber gradient)
//    - head (larger rounded rectangle, amber gradient)
//    - left_eye_white, right_eye_white (white rounded rects)
//    - left_pupil, right_pupil (dark circles)
//    - left_brow, right_brow (thin dark rectangles)
//    - mouth_smile, mouth_open, mouth_o, mouth_flat (shape-key variants)
//    - left_arm, right_arm (rounded rectangles with circle hands)
//    - left_leg, right_leg (rounded rectangles with wider feet)
//    - cheek_left, cheek_right (soft pink ellipses, low opacity)
//    - pixel_texture (scattered dark dots overlay)
//
// 3. Rig bones:
//    - root -> body_bone -> head_bone
//    - head_bone -> left_eye_ctrl, right_eye_ctrl
//    - head_bone -> mouth_ctrl
//    - body_bone -> left_arm_bone, right_arm_bone
//    - body_bone -> left_leg_bone, right_leg_bone
//
// 4. Create animations:
//    - "idle" (loop): breathing (2% scale), subtle sway, random blinks
//    - "greeting" (loop): wave right arm, body lean
//    - "encouraging" (loop): thumbs up pose, gentle nod
//    - "thoughtful" (loop): hand to chin, head tilt left
//    - "listening" (loop): half-closed eyes, subtle nod
//    - "excited" (one-shot -> idle): squash-stretch bounce, arms up
//    - "celebrating" (loop): dance (alternating legs/arms), bounce
//    - "inviting" (loop): both arms open, welcoming sway
//
// 5. State Machine "MascotSM":
//    Inputs:
//    - emotion (Number): 0=idle, 1=greeting, 2=encouraging,
//      3=thoughtful, 4=listening, 5=excited, 6=celebrating, 7=inviting
//    - lookX (Number): -1.0 to 1.0 (pupil horizontal offset)
//    - lookY (Number): -1.0 to 1.0 (pupil vertical offset)
//    - tapReact (Trigger): plays excited one-shot
//
//    States: idle, greeting, encouraging, thoughtful, listening,
//            excited, celebrating, inviting
//    Transitions: emotion number matches -> transition to state
//
// 6. Export as "lisn_mascot.riv"
// 7. Add to Xcode project bundle
//

/*
import RiveRuntime

/// Rive-powered Lisn mascot with state machine control
struct LisnRiveMascot: View {
    let emotion: MascotEmotion
    let size: CGFloat

    @StateObject private var viewModel = RiveViewModel(
        fileName: "lisn_mascot",
        stateMachineName: "MascotSM",
        autoPlay: true
    )

    var body: some View {
        viewModel.view()
            .frame(width: size, height: size)
            .onChange(of: emotion) { _, newEmotion in
                setEmotion(newEmotion)
            }
            .onAppear {
                setEmotion(emotion)
            }
    }

    private func setEmotion(_ emotion: MascotEmotion) {
        let value: Double = switch emotion {
        case .idle: 0
        case .greeting: 1
        case .encouraging: 2
        case .thoughtful: 3
        case .listening: 4
        case .excited: 5
        case .celebrating: 6
        case .inviting: 7
        }
        viewModel.setInput("emotion", value: value)
    }

    /// Set pupil look direction from external input (e.g., scroll position)
    func setLookDirection(x: CGFloat, y: CGFloat) {
        viewModel.setInput("lookX", value: Float(x))
        viewModel.setInput("lookY", value: Float(y))
    }

    /// Fire tap reaction trigger
    func triggerTapReact() {
        viewModel.triggerInput("tapReact")
    }
}
*/

import UIKit
import SwiftUI
import SpriteKit

// MARK: - Animation Phase State Machine

private enum SplashPhase: Int, CaseIterable {
    case blackout        // 0.0s  — black screen, logo invisible
    case burstStart      // 0.2s  — golden particles burst from center
    case logoFadeIn      // 0.5s  — logo fades in, particles intensify
    case sandDust        // 0.8s  — fine golden particles radiate outward
    case logoFull        // 1.2s  — logo at full size, particles slow
    case shimmer         // 1.5s  — smaller brighter gold sparkles
    case dramaticZoom    // 2.0s  — scale 1.0 -> 1.4, subtle screen flash
    case fadeOut         // 2.5s  — fade to main app
}

// MARK: - Programmatic Particle Texture

private func makeParticleTexture(size: CGFloat = 32, softness: CGFloat = 0.6) -> SKTexture {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    let image = renderer.image { ctx in
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius = size / 2
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let colors: [CGColor] = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(softness).cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ]
        let locations: [CGFloat] = [0.0, 0.3, 1.0]

        if let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: colors as CFArray,
            locations: locations
        ) {
            ctx.cgContext.drawRadialGradient(
                gradient,
                startCenter: center,
                startRadius: 0,
                endCenter: center,
                endRadius: radius,
                options: .drawsAfterEndLocation
            )
        }
    }
    return SKTexture(image: image)
}

// MARK: - SpriteKit Particle Scene

final class GoldenParticleScene: SKScene {

    // Gold color palette
    private let goldLight  = UIColor(red: 0.878, green: 0.624, blue: 0.322, alpha: 1.0)   // #E09F52
    private let goldMid    = UIColor(red: 0.769, green: 0.506, blue: 0.239, alpha: 1.0)    // #C4813D
    private let goldDark   = UIColor(red: 0.667, green: 0.416, blue: 0.176, alpha: 1.0)    // #AA6A2D
    private let goldBright = UIColor(red: 0.95,  green: 0.78,  blue: 0.45,  alpha: 1.0)    // Bright sparkle

    private var burstEmitter: SKEmitterNode?
    private var dustEmitter: SKEmitterNode?
    private var shimmerEmitter: SKEmitterNode?
    private var flashNode: SKSpriteNode?

    private let particleTexture = makeParticleTexture(size: 32, softness: 0.5)
    private let smallTexture = makeParticleTexture(size: 16, softness: 0.4)

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        scaleMode = .resizeFill
        view.allowsTransparency = true

        let center = CGPoint(x: size.width / 2, y: size.height / 2)

        // ── Phase 1: Golden Burst (t=0.2s) ──
        scheduleBurst(at: center, delay: 0.2)

        // ── Phase 2: Sand Dust (t=0.8s) ──
        scheduleDust(at: center, delay: 0.8)

        // ── Phase 3: Shimmer (t=1.5s) ──
        scheduleShimmer(at: center, delay: 1.5)

        // ── Phase 4: Screen Flash (t=2.0s) ──
        scheduleFlash(delay: 2.0)
    }

    // MARK: - Burst Emitter

    private func scheduleBurst(at center: CGPoint, delay: TimeInterval) {
        let emitter = SKEmitterNode()

        emitter.particleTexture = particleTexture
        emitter.particleBirthRate = 0                     // starts paused
        emitter.numParticlesToEmit = 0                    // continuous until stopped
        emitter.particleLifetime = 2.0
        emitter.particleLifetimeRange = 0.8
        emitter.particleSpeed = 200
        emitter.particleSpeedRange = 120
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2              // full 360 degrees
        emitter.particleScale = 0.15
        emitter.particleScaleRange = 0.1
        emitter.particleScaleSpeed = -0.04
        emitter.particleAlpha = 0.9
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.35
        emitter.particleColor = goldLight
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        emitter.position = center

        // Color ramp: gold light -> gold mid -> transparent
        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [goldLight, goldMid, goldDark, UIColor.clear],
            times: [0.0, 0.3, 0.7, 1.0]
        )

        // Slight radial acceleration outward
        emitter.xAcceleration = 0
        emitter.yAcceleration = 0
        emitter.particlePositionRange = CGVector(dx: 8, dy: 8)

        addChild(emitter)
        burstEmitter = emitter

        // Activate after delay
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 300
            },
            // Intensify at logo fade-in (t=0.5s)
            SKAction.wait(forDuration: 0.3),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 450
                emitter?.particleSpeed = 260
            },
            // Begin slowing at t=1.2s
            SKAction.wait(forDuration: 0.7),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 120
                emitter?.particleSpeed = 80
            },
            // Wind down
            SKAction.wait(forDuration: 0.8),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 0
            }
        ]))
    }

    // MARK: - Sand Dust Emitter

    private func scheduleDust(at center: CGPoint, delay: TimeInterval) {
        let emitter = SKEmitterNode()

        emitter.particleTexture = smallTexture
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 1.6
        emitter.particleLifetimeRange = 0.5
        emitter.particleSpeed = 140
        emitter.particleSpeedRange = 80
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.06
        emitter.particleScaleRange = 0.04
        emitter.particleScaleSpeed = -0.015
        emitter.particleAlpha = 0.7
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.3
        emitter.particleColor = goldMid
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        emitter.position = center
        emitter.particlePositionRange = CGVector(dx: 30, dy: 30)

        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [goldLight, goldDark, UIColor.clear],
            times: [0.0, 0.5, 1.0]
        )

        addChild(emitter)
        dustEmitter = emitter

        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 200
            },
            SKAction.wait(forDuration: 1.2),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 60
            },
            SKAction.wait(forDuration: 0.5),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 0
            }
        ]))
    }

    // MARK: - Shimmer Emitter

    private func scheduleShimmer(at center: CGPoint, delay: TimeInterval) {
        let emitter = SKEmitterNode()

        emitter.particleTexture = smallTexture
        emitter.particleBirthRate = 0
        emitter.particleLifetime = 0.8
        emitter.particleLifetimeRange = 0.3
        emitter.particleSpeed = 60
        emitter.particleSpeedRange = 40
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleScale = 0.08
        emitter.particleScaleRange = 0.05
        emitter.particleScaleSpeed = -0.05
        emitter.particleAlpha = 1.0
        emitter.particleAlphaRange = 0.2
        emitter.particleAlphaSpeed = -0.8
        emitter.particleColor = goldBright
        emitter.particleColorBlendFactor = 1.0
        emitter.particleBlendMode = .add
        emitter.position = center
        emitter.particlePositionRange = CGVector(dx: 100, dy: 100)

        emitter.particleColorSequence = SKKeyframeSequence(
            keyframeValues: [UIColor.white, goldBright, goldLight, UIColor.clear],
            times: [0.0, 0.2, 0.6, 1.0]
        )

        addChild(emitter)
        shimmerEmitter = emitter

        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 100
            },
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 30
            },
            SKAction.wait(forDuration: 0.5),
            SKAction.run { [weak emitter] in
                emitter?.particleBirthRate = 0
            }
        ]))
    }

    // MARK: - Screen Flash

    private func scheduleFlash(delay: TimeInterval) {
        run(SKAction.sequence([
            SKAction.wait(forDuration: delay),
            SKAction.run { [weak self] in
                guard let self else { return }
                let flash = SKSpriteNode(color: UIColor(red: 0.95, green: 0.85, blue: 0.6, alpha: 0.0), size: self.size)
                flash.position = CGPoint(x: self.size.width / 2, y: self.size.height / 2)
                flash.zPosition = 100
                flash.blendMode = .add
                self.addChild(flash)
                self.flashNode = flash

                flash.run(SKAction.sequence([
                    SKAction.fadeAlpha(to: 0.25, duration: 0.15),
                    SKAction.fadeAlpha(to: 0.0, duration: 0.35),
                    SKAction.removeFromParent()
                ]))
            }
        ]))
    }
}

// MARK: - UIViewRepresentable SpriteKit Wrapper (eliminates _UIReparentingView warning)

private struct SpriteKitView: UIViewRepresentable {
    let scene: SKScene

    func makeUIView(context: Context) -> SKView {
        let skView = SKView()
        skView.allowsTransparency = true
        skView.backgroundColor = .clear
        skView.presentScene(scene)
        return skView
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}

// MARK: - SplashLogoView

struct SplashLogoView: View {

    // Animation state
    @State private var phase: SplashPhase = .blackout
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.3
    @State private var textOpacity: Double = 0
    @State private var flashOpacity: Double = 0
    @State private var overallOpacity: Double = 1.0

    // SpriteKit scene
    @State private var particleScene: GoldenParticleScene = {
        let scene = GoldenParticleScene()
        scene.scaleMode = .resizeFill
        scene.backgroundColor = .clear
        return scene
    }()

    // Gold gradient colors
    private let goldGradient = LinearGradient(
        colors: [
            Color(red: 0.878, green: 0.624, blue: 0.322),  // #E09F52
            Color(red: 0.769, green: 0.506, blue: 0.239),  // #C4813D
            Color(red: 0.667, green: 0.416, blue: 0.176)   // #AA6A2D
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    var body: some View {
        ZStack {
            // Black background
            Color.black
                .ignoresSafeArea()

            // SpriteKit particle layer — UIViewRepresentable avoids _UIReparentingView constraint
            SpriteKitView(scene: particleScene)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Logo + text overlay
            VStack(spacing: 12) {
                Image("SplashLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 180, height: 180)
                    .shadow(
                        color: Color(red: 0.878, green: 0.624, blue: 0.322).opacity(0.6),
                        radius: phase.rawValue >= SplashPhase.shimmer.rawValue ? 30 : 12,
                        x: 0, y: 0
                    )

                VStack(spacing: 6) {
                    Text("LisnAI")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(goldGradient)

                    Text("Your Digital Diary")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.769, green: 0.506, blue: 0.239).opacity(0.8))
                }
                .opacity(textOpacity)
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)

            // Screen flash overlay
            Color(red: 0.95, green: 0.85, blue: 0.6)
                .ignoresSafeArea()
                .opacity(flashOpacity)
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
        }
        .opacity(overallOpacity)
        .onAppear(perform: runAnimation)
    }

    // MARK: - Choreographed Animation Sequence

    private func runAnimation() {
        // ── 0.0s: Blackout — already set via defaults ──
        phase = .blackout

        // ── 0.2s: Burst starts (particles handled by SpriteKit) ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            phase = .burstStart
        }

        // ── 0.5s: Logo fades in ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            phase = .logoFadeIn
            withAnimation(.easeOut(duration: 0.5)) {
                logoOpacity = 1.0
                logoScale = 0.7
            }
            withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
                textOpacity = 1.0
            }
        }

        // ── 0.8s: Sand dust radiates ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            phase = .sandDust
            withAnimation(.easeInOut(duration: 0.4)) {
                logoScale = 0.85
            }
        }

        // ── 1.2s: Logo at full size ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            phase = .logoFull
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7, blendDuration: 0.1)) {
                logoScale = 1.0
            }
        }

        // ── 1.5s: Shimmer ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            phase = .shimmer
        }

        // ── 2.0s: Dramatic zoom + screen flash ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            phase = .dramaticZoom
            withAnimation(.easeInOut(duration: 0.45)) {
                logoScale = 1.4
            }
            // Flash in
            withAnimation(.easeOut(duration: 0.12)) {
                flashOpacity = 0.18
            }
            // Flash out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeIn(duration: 0.3)) {
                    flashOpacity = 0.0
                }
            }
        }

        // ── 2.5s: Fade out ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            phase = .fadeOut
            withAnimation(.easeIn(duration: 0.5)) {
                overallOpacity = 0.0
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SplashLogoView()
}

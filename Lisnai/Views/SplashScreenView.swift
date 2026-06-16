import SwiftUI

// MARK: - Splash Animation Phases

private enum SplashPhase {
    case initial      // 0.0s — everything invisible
    case logoReveal   // 0.1s — logo scales in with glass effect
    case textReveal   // 0.4s — text fades in below logo
    case hold         // 0.8s — brief hold at full presentation
    case fadeOut       // 1.5s — fade everything out
}

// MARK: - Animated Mesh Background

/// Warm-toned animated mesh gradient (iOS 18+) with LinearGradient fallback
private struct AnimatedMeshBackground: View {
    @State private var animating = false

    // Muted warm palette — colors close enough that movement is barely perceptible
    private let cream    = Color(red: 1.0,   green: 0.992, blue: 0.969)  // #FFFDF8
    private let offWhite = Color(red: 0.984, green: 0.961, blue: 0.925)  // #FBF5EC
    private let sand     = Color(red: 0.973, green: 0.941, blue: 0.890)  // #F8F0E3
    private let linen    = Color(red: 0.961, green: 0.929, blue: 0.878)  // #F5EDE0

    var body: some View {
        if #available(iOS 18.0, *) {
            meshGradientView
        } else {
            fallbackGradient
        }
    }

    @available(iOS 18.0, *)
    private var meshGradientView: some View {
        MeshGradient(
            width: 3, height: 3,
            points: [
                // Top row
                SIMD2(0.0, 0.0),
                SIMD2(animating ? 0.6 : 0.4, 0.0),
                SIMD2(1.0, 0.0),
                // Middle row — animates for organic movement
                SIMD2(0.0, animating ? 0.6 : 0.4),
                SIMD2(animating ? 0.55 : 0.45, animating ? 0.55 : 0.45),
                SIMD2(1.0, animating ? 0.4 : 0.6),
                // Bottom row
                SIMD2(0.0, 1.0),
                SIMD2(animating ? 0.4 : 0.6, 1.0),
                SIMD2(1.0, 1.0)
            ],
            colors: [
                cream,    offWhite, sand,
                offWhite, cream,    offWhite,
                sand,     linen,    offWhite
            ]
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .easeInOut(duration: 6.0)
                .repeatForever(autoreverses: true)
            ) {
                animating = true
            }
        }
    }

    private var fallbackGradient: some View {
        LinearGradient(
            colors: [cream, offWhite, sand, linen],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

// MARK: - Floating Logo

/// Renders the cutout book logo floating directly on the background — no container box
private struct FloatingLogoView: View {
    let logoScale: CGFloat
    let logoOpacity: Double

    private let accentColor = Color(red: 0.769, green: 0.506, blue: 0.239)

    var body: some View {
        Image("SplashLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 140, height: 140)
            .shadow(
                color: accentColor.opacity(0.4),
                radius: 20, x: 0, y: 10
            )
            .shadow(
                color: accentColor.opacity(0.15),
                radius: 40, x: 0, y: 4
            )
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
    }
}

// MARK: - SplashLogoView

struct SplashLogoView: View {

    // Animation state
    @State private var phase: SplashPhase = .initial
    @State private var logoOpacity: Double = 0
    @State private var logoScale: CGFloat = 0.6
    @State private var textOpacity: Double = 0
    @State private var subtitleOpacity: Double = 0
    @State private var overallOpacity: Double = 1.0

    // Brand gradient for text
    private let brandGradient = LinearGradient(
        colors: [
            Color(red: 0.878, green: 0.624, blue: 0.322),  // #E09F52
            Color(red: 0.769, green: 0.506, blue: 0.239),  // #C4813D
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        ZStack {
            // Animated warm mesh gradient background
            AnimatedMeshBackground()

            // Subtle radial glow behind logo
            RadialGradient(
                colors: [
                    Color(red: 0.878, green: 0.624, blue: 0.322).opacity(0.3),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: 200
            )
            .frame(width: 400, height: 400)
            .blur(radius: 30)
            .opacity(logoOpacity)

            // Logo + text stack
            VStack(spacing: 20) {
                FloatingLogoView(
                    logoScale: logoScale,
                    logoOpacity: logoOpacity
                )

                VStack(spacing: 6) {
                    Text("LisnAI")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(brandGradient)
                        .opacity(textOpacity)

                    Text("Your Digital Diary")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(
                            Color(red: 0.667, green: 0.416, blue: 0.176).opacity(0.7)
                        )
                        .opacity(subtitleOpacity)
                }
            }
        }
        .opacity(overallOpacity)
        .onAppear(perform: runAnimation)
    }

    // MARK: - Animation Sequence (~2s total)

    private func runAnimation() {
        // ── 0.1s: Logo scales in with spring ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            phase = .logoReveal
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75)) {
                logoOpacity = 1.0
                logoScale = 1.0
            }
        }

        // ── 0.4s: Text fades in ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            phase = .textReveal
            withAnimation(.easeOut(duration: 0.35)) {
                textOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.35).delay(0.1)) {
                subtitleOpacity = 1.0
            }
        }

        // ── 0.8s: Hold ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            phase = .hold
        }

        // ── 1.5s: Fade out ──
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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

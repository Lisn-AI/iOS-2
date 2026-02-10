import SwiftUI

struct SplashLogoView: View {
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0

    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.992, blue: 0.969)
                .ignoresSafeArea()

            VStack(spacing: 8) {
                Image("SplashLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 220)

                VStack(spacing: 6) {
                    Text("Listen AI")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.2))

                    Text("Your Digital Diary")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.45))
                }
            }
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    logoScale = 1.0
                    logoOpacity = 1.0
                }
            }
        }
    }
}

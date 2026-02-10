import SwiftUI

/// Raised calendar button overlay that covers the native tab bar's center slot.
struct RaisedCalendarButton: View {
    @Binding var selectedTab: MainTabView.Tab

    @State private var isPressed = false

    var body: some View {
        Button {
            LisnHaptics.light()
            selectedTab = .calendar
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    // Outer ambient ring
                    Circle()
                        .fill(LisnColors.accent.opacity(0.08))
                        .frame(width: 60, height: 60)

                    // Main circle — warm dark brown
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.22, green: 0.18, blue: 0.14),
                                    Color(red: 0.15, green: 0.12, blue: 0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                        .shadow(
                            color: Color.black.opacity(0.2),
                            radius: 10,
                            x: 0,
                            y: 3
                        )

                    VStack(spacing: -2) {
                        Text(todayMonthAbbrev)
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundColor(LisnColors.accent.opacity(0.8))

                        Text(todayDayNumber)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                }

                Text("Calendar")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(selectedTab == .calendar ? LisnColors.textPrimary : LisnColors.textTertiary)
            }
        }
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                        isPressed = false
                    }
                }
        )
        .offset(y: 14)
    }

    // MARK: - Date Helpers

    private var todayDayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: Date())
    }

    private var todayMonthAbbrev: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"
        return formatter.string(from: Date()).uppercased()
    }
}

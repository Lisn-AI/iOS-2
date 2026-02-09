import SwiftUI

/// Raised calendar button overlay that covers the native tab bar's center slot.
/// The circle extends upward and a "Calendar" label sits at the tab bar text level,
/// making it look like one enlarged tab bar button.
struct RaisedCalendarButton: View {
    @Binding var selectedTab: MainTabView.Tab

    var body: some View {
        Button {
            LisnHaptics.light()
            selectedTab = .calendar
        } label: {
            VStack(spacing: 1) {
                // Large raised circle — spans above and across the tab bar
                ZStack {
                    Circle()
                        .fill(LisnColors.accent)
                        .frame(width: 72, height: 72)
                        .shadow(
                            color: LisnShadow.glow.color,
                            radius: LisnShadow.glow.radius,
                            x: LisnShadow.glow.x,
                            y: LisnShadow.glow.y
                        )

                    VStack(spacing: -2) {
                        Text(todayMonthAbbrev)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(.white.opacity(0.85))

                        Text(todayDayNumber)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                // Label aligned with other tab bar labels
                Text("Calendar")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(selectedTab == .calendar ? LisnColors.textPrimary : LisnColors.textTertiary)
            }
        }
        // Push down so circle extends well into the tab bar, covering icons area
        .offset(y: 16)
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

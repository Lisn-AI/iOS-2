import SwiftUI

// MARK: - Colors

enum LisnColors {
    // Backgrounds
    static let bgPrimary = Color("BGPrimary")
    static let bgSecondary = Color("BGSecondary")
    static let bgElevated = Color("BGElevated")

    // Text
    static let textPrimary = Color("TextPrimary")
    static let textSecondary = Color("TextSecondary")
    static let textTertiary = Color("TextTertiary")

    // Borders
    static let border = Color("Border")
    static let borderSubtle = Color("BorderSubtle")

    // Accent
    static let accent = Color("Accent")

    // Semantic
    static let success = Color("Success")
    static let warning = Color("Warning")
    static let error = Color("Error")
    static let info = Color("Info")

    // Recording states
    static let recording = accent
    static let paused = Color.orange
}

// MARK: - Spacing (8pt grid)

enum LisnSpacing {
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
    static let xxxxl: CGFloat = 48
}

// MARK: - Corner Radius

enum LisnRadius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let pill: CGFloat = 9999
}

// MARK: - Shadows

struct LisnShadowValue {
    let color: Color
    let radius: CGFloat
    let x: CGFloat
    let y: CGFloat
}

enum LisnShadow {
    static let sm = LisnShadowValue(
        color: Color.black.opacity(0.06),
        radius: 4,
        x: 0,
        y: 2
    )
    static let md = LisnShadowValue(
        color: Color.black.opacity(0.08),
        radius: 8,
        x: 0,
        y: 4
    )
    static let lg = LisnShadowValue(
        color: Color.black.opacity(0.12),
        radius: 16,
        x: 0,
        y: 8
    )
    static let glow = LisnShadowValue(
        color: LisnColors.accent.opacity(0.35),
        radius: 12,
        x: 0,
        y: 4
    )
}

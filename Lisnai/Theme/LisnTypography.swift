import SwiftUI

enum LisnFont {
    // MARK: - Display

    static func displayLarge() -> Font {
        .custom("Inter-Bold", size: 34, relativeTo: .largeTitle)
    }

    static func displayMedium() -> Font {
        .custom("Inter-SemiBold", size: 28, relativeTo: .title)
    }

    // MARK: - Title

    static func titleLarge() -> Font {
        .custom("Inter-SemiBold", size: 22, relativeTo: .title2)
    }

    static func titleMedium() -> Font {
        .custom("Inter-SemiBold", size: 20, relativeTo: .title3)
    }

    static func titleSmall() -> Font {
        .custom("Inter-Medium", size: 17, relativeTo: .headline)
    }

    // MARK: - Body

    static func bodyLarge() -> Font {
        .custom("Inter-Regular", size: 17, relativeTo: .body)
    }

    static func bodyMedium() -> Font {
        .custom("Inter-Regular", size: 15, relativeTo: .subheadline)
    }

    static func bodySmall() -> Font {
        .custom("Inter-Regular", size: 13, relativeTo: .footnote)
    }

    // MARK: - Label

    static func labelLarge() -> Font {
        .custom("Inter-Medium", size: 15, relativeTo: .subheadline)
    }

    static func labelMedium() -> Font {
        .custom("Inter-Medium", size: 13, relativeTo: .footnote)
    }

    static func labelSmall() -> Font {
        .custom("Inter-Medium", size: 11, relativeTo: .caption2)
    }

    // MARK: - Caption

    static func caption() -> Font {
        .custom("Inter-Regular", size: 12, relativeTo: .caption)
    }

    static func captionBold() -> Font {
        .custom("Inter-SemiBold", size: 12, relativeTo: .caption)
    }

    // MARK: - Mono (for timers)

    static func mono() -> Font {
        .system(size: 17, design: .monospaced)
    }
}

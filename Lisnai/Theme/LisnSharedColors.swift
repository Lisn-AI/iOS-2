import SwiftUI

/// Minimal color subset shared with the widget extension target.
/// No UIKit imports - safe for WidgetKit extensions.
enum LisnSharedColors {
    // Rich Amber #C4813D
    static let accent = Color(red: 0.769, green: 0.506, blue: 0.239)
    static let paused = Color(red: 0.85, green: 0.45, blue: 0.25)
    static let success = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let error = Color(red: 0.94, green: 0.27, blue: 0.27)
}

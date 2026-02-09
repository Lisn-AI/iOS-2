import SwiftUI

/// Minimal color subset shared with the widget extension target.
/// No UIKit imports - safe for WidgetKit extensions.
enum LisnSharedColors {
    // Light: #6B9080, Dark: #7DAF9A
    static let accent = Color(red: 0.42, green: 0.565, blue: 0.502)
    static let paused = Color.orange
    static let success = Color(red: 0.2, green: 0.78, blue: 0.35)
    static let warning = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let error = Color(red: 0.94, green: 0.27, blue: 0.27)
}

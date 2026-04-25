import SwiftUI
import UIKit

/// SwiftUI wrapper for UIActivityViewController to share note content
/// Since Apple Notes has no public API, we use the system share sheet
/// which includes "Save to Notes" as a target.
struct NoteShareSheet: UIViewControllerRepresentable {
    let text: String
    let onShared: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )

        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            if completed {
                onShared()
            }
        }

        return activityVC
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

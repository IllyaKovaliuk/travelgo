import SwiftUI
import UIKit

/// The system share sheet for an item that only exists after an async step
/// (an invite code minted on tap), which `ShareLink` can't wait for.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    /// Called when the sheet closes: `completed` is false if it was dismissed
    /// without sending anything; `activity` is the chosen share target.
    var onComplete: ((_ completed: Bool, _ activity: String?) -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            onComplete?(completed, activity?.rawValue)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

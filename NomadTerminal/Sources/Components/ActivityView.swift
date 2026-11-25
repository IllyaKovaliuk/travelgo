import SwiftUI
import UIKit

/// The system share sheet for an item that only exists after an async step
/// (an invite code minted on tap), which `ShareLink` can't wait for.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

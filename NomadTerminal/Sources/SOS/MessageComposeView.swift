import SwiftUI
import MessageUI

/// Wraps the real system Messages compose sheet — the actual, honest
/// mechanism behind SOSView's "message your contacts" action. No paid
/// SMS/backend gateway involved (and none needed): this is Apple's own
/// `MFMessageComposeViewController`, pre-addressed and pre-filled, handed
/// to the person to review and hit send themselves. Real device only —
/// `MFMessageComposeViewController.canSendText()` is false in Simulator
/// (no cellular/iMessage stack there), which `SOSView` checks before ever
/// presenting this.
struct MessageComposeView: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    /// The real outcome (`.sent`/`.cancelled`/`.failed`) — callers (SOSView)
    /// rely on this being accurate to decide whether they're allowed to
    /// say anything resembling "sent."
    var onFinish: (MessageComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageComposeResult) -> Void
        init(onFinish: @escaping (MessageComposeResult) -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) { [onFinish] in onFinish(result) }
        }
    }
}

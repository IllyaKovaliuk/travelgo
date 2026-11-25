import Foundation
import Observation

/// Holds a GPX/KML file handed to the app from *outside* it — Files'
/// "Open In"/"Copy to Nomad" (see `CFBundleDocumentTypes`/
/// `UTImportedTypeDeclarations` in `project.yml`) or another app's Share
/// Sheet — until `RootTabView` is actually up and can act on it.
///
/// A plain singleton, not threaded through `NomadTerminalApp`'s own view
/// hierarchy, specifically because the file can arrive before sign-in
/// finishes (`RootTabView` doesn't exist yet while `RootView` is still
/// showing onboarding/`AuthView`) — `.onOpenURL` just records it here, and
/// whichever view reads `pendingFileURL` next (once the signed-in shell is
/// actually mounted) picks it up. Same `@Observable` singleton pattern this
/// app already uses for `ThemeManager`/`SubscriptionManager`.
@MainActor
@Observable
final class PendingImportCoordinator {
    static let shared = PendingImportCoordinator()
    private init() {}

    var pendingFileURL: URL?
    /// A route opened from a shared link (`RouteLinks`) — same hand-off as
    /// the file above: recorded here, acted on once `RootTabView` exists.
    var pendingRouteID: String?

    /// A crew invite code from a link or the "Join with a code" field.
    /// Kept in UserDefaults too: someone who taps an invite before they have
    /// an account goes through onboarding + sign-up first, and quitting the
    /// app in the middle shouldn't lose the invitation.
    var pendingInviteCode: String? {
        didSet { UserDefaults.standard.set(pendingInviteCode, forKey: Self.inviteKey) }
    }
    private static let inviteKey = "io.nomadterminal.pendingCrewInvite"

    /// Called once at launch so an invite saved by a previous run is picked up.
    func restorePendingInvite() {
        if pendingInviteCode == nil, let saved = UserDefaults.standard.string(forKey: Self.inviteKey), CrewLinks.isValidCode(saved) {
            pendingInviteCode = saved
        }
    }
}

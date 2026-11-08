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
}

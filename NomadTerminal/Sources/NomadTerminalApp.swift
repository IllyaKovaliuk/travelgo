import SwiftUI

/// Exists solely to give `VisitsMonitor` a launch hook that fires before
/// any SwiftUI view does — including a headless background relaunch iOS
/// triggers purely to deliver a pending `CLVisit`, which has no view
/// hierarchy at all. See `VisitsMonitor.applicationDidLaunch()`.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        Task { @MainActor in VisitsMonitor.shared.applicationDidLaunch() }
        return true
    }
}

@main
struct NomadTerminalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                // A GPX shared in from Files' "Open In"/"Copy to Nomad" or
                // another app's Share Sheet (Strava, Garmin Connect,
                // Komoot — see `UTImportedTypeDeclarations`/
                // `CFBundleDocumentTypes` in project.yml) lands here. Just
                // records it — `RootTabView` is what actually acts on it,
                // once (if) the signed-in shell is up; see
                // `PendingImportCoordinator`'s own doc comment for why this
                // can't act on it directly at this level.
                .onOpenURL { url in
                    // A shared route link (universal link or the custom
                    // scheme) opens that route; anything else is a file.
                    if let routeID = RouteLinks.routeID(from: url) {
                        PendingImportCoordinator.shared.pendingRouteID = routeID
                    } else {
                        PendingImportCoordinator.shared.pendingFileURL = url
                    }
                }
        }
    }
}

/// Real "signed in? show feed : show onboarding" switch — a persisted,
/// non-anonymous session (real email account) skips straight to the feed;
/// everyone else (first launch, or a session old enough to force a
/// re-login) sees onboarding, which now always ends at a mandatory
/// `AuthView` — there's no browse-without-an-account path left, so landing
/// here means signing in or signing up for real.
///
/// A signed-in session is also capped at `maxSessionAge` — Supabase's
/// refresh token would otherwise keep renewing silently forever. Real
/// expiry (rejecting the refresh token itself) is a server-side control we
/// don't have on the free tier, so this is enforced client-side: `AuthView`
/// stamps `authSessionStartedAt` the moment a real sign-in/sign-up
/// succeeds, and past `maxSessionAge` this signs the session out itself and
/// falls through to onboarding, instead of trusting Supabase to still
/// consider it valid.
struct RootView: View {
    /// ~3 weeks — inside the "every 2 weeks to a month" range asked for.
    private static let maxSessionAge: TimeInterval = 21 * 24 * 60 * 60

    @State private var isCheckingSession = true
    @State private var finishedOnboarding = false
    @State private var languageManager = LanguageManager.shared

    var body: some View {
        Group {
            if isCheckingSession {
                NTColor.pine.ignoresSafeArea()
            } else if finishedOnboarding {
                RootTabView()
            } else {
                OnboardingContainer(onFinished: { finishedOnboarding = true })
                    .readableColumn(maxWidth: 560)
            }
        }
        // Applied once, at the single root every screen in the app
        // descends from (onboarding and the whole signed-in tab flow
        // alike) — same reasoning `.preferredColorScheme` already gets
        // applied per-flow-root for Pine/Milk. Live, no relaunch needed:
        // changing `languageManager.current` in Settings re-renders this
        // and everything below it in the new language immediately.
        .environment(\.locale, languageManager.locale)
        .task {
            if let session = try? await supabase.auth.session, session.user.isAnonymous == false {
                let startedAt = UserDefaults.standard.object(forKey: "authSessionStartedAt") as? Date
                let isExpired = startedAt.map { Date().timeIntervalSince($0) > Self.maxSessionAge } ?? false
                if isExpired {
                    try? await supabase.auth.signOut()
                    UserDefaults.standard.removeObject(forKey: "authSessionStartedAt")
                } else {
                    // Pre-existing session from before this stamp shipped —
                    // back-fill it now rather than treating "no stamp" as
                    // "already expired" and bouncing someone who was
                    // legitimately signed in.
                    if startedAt == nil {
                        UserDefaults.standard.set(Date(), forKey: "authSessionStartedAt")
                    }
                    finishedOnboarding = true
                }
            }
            isCheckingSession = false
        }
    }
}

import SwiftUI

@main
struct NomadTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
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

    var body: some View {
        Group {
            if isCheckingSession {
                NTColor.pine.ignoresSafeArea()
            } else if finishedOnboarding {
                RootTabView()
            } else {
                OnboardingContainer(onFinished: { finishedOnboarding = true })
            }
        }
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

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
/// everyone else (first launch, or an anonymous session picked up only from
/// liking/saving pre-signup) sees onboarding.
struct RootView: View {
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
                finishedOnboarding = true
            }
            isCheckingSession = false
        }
    }
}

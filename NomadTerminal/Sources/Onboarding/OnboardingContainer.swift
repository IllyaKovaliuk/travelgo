import SwiftUI

/// Drives the three onboarding screens as a native swipeable page flow,
/// with the doc's own PageDots overlaid instead of the system indicator.
struct OnboardingContainer: View {
    var onFinished: () -> Void

    @State private var page = 0
    @State private var selectedInterests: Set<Interest> = [.overland, .hiking]
    @State private var showAuth = false

    var body: some View {
        TabView(selection: $page) {
            WelcomeView(onStart: { advance() }, onSignIn: { showAuth = true })
                .tag(0)
            InterestsView(selected: $selectedInterests, onContinue: { advance() })
                .tag(1)
            PermissionsView(onFinished: onFinished)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.spring(response: 0.55, dampingFraction: 0.86), value: page)
        .background(NTColor.pine.ignoresSafeArea())
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .fullScreenCover(isPresented: $showAuth) {
            AuthView(onDone: { showAuth = false; onFinished() })
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            page = min(page + 1, 2)
        }
    }
}

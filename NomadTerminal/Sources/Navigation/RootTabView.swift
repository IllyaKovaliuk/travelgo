import SwiftUI

/// Post-onboarding shell — swaps the visible screen by tab and floats the
/// glass pill nav bar over all of them (matching every "primary" screen
/// in the doc, which shares this exact bottom bar).
struct RootTabView: View {
    @State private var tab: RootTab = .home
    /// Real fix for a real bug: `FloatingTabBar` had a hardcoded "SK"
    /// fallback for the profile tab's initials bubble that nothing ever
    /// overrode — nobody passed it the real signed-in user's name, so
    /// literally every account saw "SK" there regardless of who they
    /// were. Same initials logic `ProfileView`'s own avatar uses, fetched
    /// once here since the tab bar floats over every screen, not just
    /// Profile.
    @State private var profileInitials: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .home: HomeFeedView()
            case .search: SearchView()
            case .guide: GuideView()
            case .activity: NotificationsView()
            case .saved: SavedView()
            case .profile: ProfileView()
            }

            FloatingTabBar(selection: $tab, profileInitials: profileInitials ?? "?")
                .padding(.bottom, 12)
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .task {
            if let profile = try? await RouteRepository.shared.fetchMyProfile() {
                let name = profile.displayName ?? profile.username
                profileInitials = name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
            }
        }
    }
}

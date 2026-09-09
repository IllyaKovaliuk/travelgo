import SwiftUI

/// Post-onboarding shell — swaps the visible screen by tab and floats the
/// glass pill nav bar over all of them (matching every "primary" screen
/// in the doc, which shares this exact bottom bar).
struct RootTabView: View {
    @State private var tab: RootTab = .home

    var body: some View {
        ZStack(alignment: .bottom) {
            switch tab {
            case .home: HomeFeedView()
            case .search: SearchView()
            case .guide: GuideView()
            case .saved: SavedView()
            case .profile: ProfileView()
            }

            FloatingTabBar(selection: $tab)
                .padding(.bottom, 12)
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }
}

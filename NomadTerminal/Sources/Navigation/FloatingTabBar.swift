import SwiftUI

enum RootTab: Int, CaseIterable {
    // Compass used to be its own tab; it's reached from a route's
    // "Navigate" button now (with a plain-compass toggle right there,
    // next to SOS) since a standalone tab for it didn't earn its keep
    // visually against the other primary destinations.
    //
    // Activity (the social/follow feed — comments, likes, badges, new
    // routes from people you follow) used to be a bell button opening a
    // modal from Home. Promoted to a real tab: it's a whole browsing
    // surface in its own right (a normal vertical list, same pattern
    // Strava uses for its feed), not a one-off notification tray.
    case home, search, guide, activity, saved, profile

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .guide: return "book.closed.fill"
        case .activity: return "bell.fill"
        case .saved: return "bookmark.fill"
        case .profile: return ""
        }
    }
}

/// The glass pill bottom bar that floats over every primary screen —
/// matches the frosted capsule with the accent "you are here" bubble.
struct FloatingTabBar: View {
    @Binding var selection: RootTab
    var profileInitials: String = "SK"

    var body: some View {
        HStack(spacing: 5) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                Button {
                    let generator = UISelectionFeedbackGenerator()
                    generator.selectionChanged()
                    withAnimation(NTMotion.spring) {
                        selection = tab
                    }
                } label: {
                    ZStack {
                        if selection == tab {
                            Circle()
                                .fill(tab == .profile ? NTColor.sage : NTColor.accent)
                                .frame(width: 48, height: 48)
                                .shadow(color: (tab == .profile ? NTColor.sage : NTColor.accent).opacity(0.5), radius: 10, y: 6)
                        }
                        if tab == .profile {
                            Text(profileInitials)
                                .font(NTFont.mono(12, .semibold))
                                .foregroundStyle(selection == tab ? Color(hex: 0x0B2716) : NTColor.milk(0.8))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().stroke(NTColor.milk(0.3), lineWidth: selection == tab ? 0 : 1)
                                )
                        } else {
                            Image(systemName: tab.icon)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(selection == tab ? Color(hex: 0x231007) : NTColor.milk(0.72))
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .background(
            Capsule().fill(NTColor.milk(0.13))
        )
        .overlay(Capsule().stroke(NTColor.milk(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
    }
}

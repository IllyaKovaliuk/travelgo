import SwiftUI

enum RootTab: Int, CaseIterable {
    // Compass used to be its own tab; it's reached from a route's
    // "Navigate" button now (with a plain-compass toggle right there,
    // next to SOS) since a standalone tab for it didn't earn its keep
    // visually against the other primary destinations.
    //
    // Order is deliberate: five slots so the Field Guide (the thing you
    // reach for when something goes wrong) sits dead centre, in the easiest
    // thumb position — Home and Places on its left, Saved and Profile on
    // its right. Activity (the social/notification feed) is the bell on
    // Home's top bar rather than a tab: a sixth slot would push the Guide
    // off-centre.
    case home, search, guide, saved, profile

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .guide: return "book.closed.fill"
        case .saved: return "bookmark.fill"
        case .profile: return ""
        }
    }
}

/// The glass pill bottom bar that floats over every primary screen —
/// matches the frosted capsule with the accent "you are here" bubble.
struct FloatingTabBar: View {
    @Binding var selection: RootTab
    /// Real fix for a real bug: this used to default to a hardcoded "SK"
    /// that nothing ever overrode — every account saw the same fake
    /// initials here regardless of who was actually signed in. No default
    /// now, on purpose — `RootTabView` is the one real call site and must
    /// pass the real signed-in user's own initials explicitly, so this
    /// can't silently go stale/unset again the way the old default did.
    var profileInitials: String

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

import SwiftUI

enum RootTab: Int, CaseIterable {
    // Compass used to be its own tab; it's reached from a route's
    // "Navigate" button now (with a plain-compass toggle right there,
    // next to SOS) since a standalone tab for it didn't earn its keep
    // visually against the other primary destinations.
    //
    // Five slots. The Field Guide used to be the centre tab; it now lives in
    // Profile ("Field guide") to make room for Expeditions. Activity (the
    // social/notification feed) is the bell on Home's top bar.
    case home, search, crews, expeditions, profile

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .crews: return "person.3.fill"
        case .expeditions: return "suitcase.fill"
        case .profile: return ""
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .home: return "Home"
        case .search: return "Places"
        case .crews: return "Crews"
        case .expeditions: return "Trips"
        case .profile: return "Profile"
        }
    }
}

/// Wide-screen (iPad, the Duo's inner display) counterpart of the floating
/// pill: the same five destinations as a vertical rail down the leading
/// edge, with labels, since a bottom pill floating mid-screen on a 13" panel
/// is hard to reach and wastes the room a sidebar is made for.
struct SidebarTabBar: View {
    @Binding var selection: RootTab
    var profileInitials: String

    var body: some View {
        VStack(spacing: 6) {
            ForEach(RootTab.allCases, id: \.self) { tab in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(NTMotion.spring) { selection = tab }
                } label: {
                    VStack(spacing: 5) {
                        ZStack {
                            if selection == tab {
                                Circle()
                                    .fill(tab == .profile ? NTColor.sage : NTColor.accent)
                                    .frame(width: 44, height: 44)
                            }
                            if tab == .profile {
                                Text(profileInitials)
                                    .font(NTFont.mono(12, .semibold))
                                    .foregroundStyle(selection == tab ? Color(hex: 0x0B2716) : NTColor.milk(0.8))
                            } else {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(selection == tab ? Color(hex: 0x231007) : NTColor.milk(0.72))
                            }
                        }
                        .frame(width: 44, height: 44)

                        Text(tab.title)
                            .font(NTFont.mono(10, .medium))
                            .foregroundStyle(selection == tab ? NTColor.milk : NTColor.milk(0.6))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 24)
        .padding(.horizontal, 8)
        .frame(width: 92)
        .frame(maxHeight: .infinity)
        .background(NTColor.milk(0.05).ignoresSafeArea())
        .overlay(alignment: .trailing) {
            Rectangle().fill(NTColor.milk(0.1)).frame(width: 1).ignoresSafeArea()
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
        // See-through frosted capsule: material only, no opaque fill, so the
        // content behind shows through. (An iOS 26 `glassEffect` version
        // made the tab buttons stop receiving taps, so it's deliberately
        // not used here.)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(NTColor.milk(0.22), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
    }
}

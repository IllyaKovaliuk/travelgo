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
        bar
            .modifier(GlassBarBackground())
    }

    private var bar: some View {
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
                                .fill(.clear)
                                .frame(width: 48, height: 48)
                                .modifier(SelectedBubble(tint: tab == .profile ? NTColor.sage : NTColor.accent))
                        }
                        if tab == .profile {
                            Text(profileInitials)
                                .font(NTFont.mono(12, .semibold))
                                .foregroundStyle(selection == tab ? Color(hex: 0x0B2716) : NTColor.milk(0.85))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle().stroke(NTColor.milk(0.3), lineWidth: selection == tab ? 0 : 1)
                                )
                        } else {
                            Image(systemName: tab.icon)
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(selection == tab ? Color(hex: 0x231007) : NTColor.milk(0.85))
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(9)
    }
}

/// Capsule behind the bar: real Liquid Glass on iOS 26+, a see-through
/// material before that (no opaque fill either way, so content shows through).
private struct GlassBarBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                content
            }
            .glassEffect(.regular.interactive(), in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        } else {
            content
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().stroke(NTColor.milk(0.22), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
        }
    }
}

/// The "you are here" bubble: tinted glass on iOS 26+, soft solid before.
private struct SelectedBubble: ViewModifier {
    let tint: Color
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.9)).interactive(), in: Circle())
        } else {
            content
                .background(Circle().fill(tint.opacity(0.92)))
                .shadow(color: tint.opacity(0.45), radius: 8, y: 4)
        }
    }
}

import SwiftUI

/// 08 · Profile & badges — real data throughout (was entirely hardcoded
/// "Sana Kadyrova" mock content before). Anonymous sessions (never signed
/// up with a real email) see a sign-in prompt instead of a fake identity.
struct ProfileView: View {
    enum Tab: String, CaseIterable { case routes = "My routes", activity = "Activity", badges = "Badges" }
    @State private var tab: Tab = .badges
    @State private var showSettings = false
    @State private var showAuth = false
    @State private var showEditProfile = false

    @State private var profile: RouteRepository.MyProfile?
    @State private var badges: [RouteRepository.MyBadge] = []
    @State private var myRoutes: [RouteRepository.MyRoute] = []
    @State private var activity: [RouteRepository.PointsLedgerEntry] = []
    @State private var isLoading = true

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if profile?.isAnonymous == true {
                        anonymousPrompt
                    } else {
                        HStack(spacing: 0) {
                            statBlock(formatKM(profile?.kmLogged ?? 0), "KM LOGGED")
                            statBlock("\(profile?.routesCompleted ?? 0)", "COMPLETED")
                            statBlock("\(badges.filter(\.earned).count)", "BADGES")
                        }
                        .padding(.vertical, 18)
                        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .top)
                        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .bottom)
                        .padding(.top, 24)

                        HStack(spacing: 4) {
                            ForEach(Tab.allCases, id: \.self) { t in
                                Button {
                                    withAnimation(NTMotion.spring) { tab = t }
                                } label: {
                                    Text(t.rawValue)
                                        .font(NTFont.body(13, .semibold))
                                        .foregroundStyle(tab == t ? NTColor.pine : NTColor.milk(0.7))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 42)
                                        .background(Capsule().fill(tab == t ? NTColor.milk : .clear))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(5)
                        .background(Capsule().fill(NTColor.milk(0.08)))
                        .padding(.top, 22)

                        Group {
                            switch tab {
                            case .badges: badgeGrid
                            case .routes: routesList
                            case .activity: activityList
                            }
                        }
                        .padding(.top, 26)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
                .padding(.bottom, 100)
            }
        }
        .foregroundStyle(NTColor.milk)
        .sheet(isPresented: $showSettings, onDismiss: { Task { await load() } }) { SettingsView() }
        .fullScreenCover(isPresented: $showAuth) { AuthView(onDone: { showAuth = false; Task { await load() } }) }
        .sheet(isPresented: $showEditProfile) {
            if let profile {
                EditProfileView(current: profile, onSaved: { Task { await load() } })
            }
        }
        .task { await load() }
    }

    /// Bumped on every `load()` call so a slow, now-stale fetch can't
    /// clobber a newer one. Real bug this fixes: ProfileView's initial
    /// `.task` kicks off a load while still anonymous; signing up while
    /// that's in flight starts a second load with the real account. Both
    /// are independent `Task`s with no ordering guarantee — if the first
    /// (anonymous) one happened to resolve *after* the second (real
    /// account) one, its stale "New Nomad" result silently overwrote the
    /// correct name. Confirmed via the DB: the real name was always
    /// stored correctly — this was purely a client-side race, not a
    /// signup/backend bug.
    @State private var profileLoadToken = 0

    private func load() async {
        profileLoadToken += 1
        let myToken = profileLoadToken
        async let profileResult = try? RouteRepository.shared.fetchMyProfile()
        async let badgesResult = (try? RouteRepository.shared.fetchMyBadges()) ?? []
        async let routesResult = (try? RouteRepository.shared.fetchMyRoutes()) ?? []
        async let activityResult = (try? RouteRepository.shared.fetchPointsLedger(limit: 20)) ?? []
        let resolvedProfile = await profileResult
        let resolvedBadges = await badgesResult
        let resolvedRoutes = await routesResult
        let resolvedActivity = await activityResult
        guard myToken == profileLoadToken else { return } // a newer load already superseded this one
        profile = resolvedProfile
        badges = resolvedBadges
        myRoutes = resolvedRoutes
        activity = resolvedActivity
        isLoading = false
    }

    private var initials: String {
        guard let name = profile?.displayName, !name.isEmpty else { return "?" }
        return name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var header: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(LinearGradient(colors: [NTColor.accent, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .overlay(Text(initials).font(NTFont.heading(28, .semibold)).foregroundStyle(NTColor.milk))
                if profile?.routesCompleted ?? 0 > 0 {
                    Text("\(profile?.routesCompleted ?? 0)")
                        .font(NTFont.mono(10, .semibold))
                        .foregroundStyle(Color(hex: 0x2B1B05))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(NTColor.gold))
                        .overlay(Circle().stroke(NTColor.pine, lineWidth: 3))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(profile?.isAnonymous == true ? "Anonymous nomad" : (profile?.displayName ?? "—"))
                    .font(NTFont.heading(26, .extraBold)).foregroundStyle(NTColor.milk)
                if profile?.isAnonymous != true {
                    Text("@\(profile?.username ?? "") · \((profile?.homeLocation ?? "NO HOME SET").uppercased())")
                        .font(NTFont.mono(11.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                }
            }
            if profile?.isAnonymous == false {
                Button { showEditProfile = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(NTColor.milk(0.7))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(NTColor.milk(0.1)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(NTColor.milk(0.75))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    private var anonymousPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("You're browsing without an account — routes you like or save stick around, but nothing syncs to another device and there's no name to show here yet.")
                .font(NTFont.body(13.5, .light))
                .foregroundStyle(NTColor.milk(0.65))
            Button { showAuth = true } label: {
                Text("Sign in or create an account")
                    .font(NTFont.body(14, .semibold))
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(NTColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        .padding(.top, 22)
    }

    private func formatKM(_ km: Double) -> String {
        km >= 1000 ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value).font(NTFont.mono(24, .semibold))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badgeGrid: some View {
        Group {
            if badges.isEmpty && !isLoading {
                emptyState("No badges yet", "Publish routes and log distance to start earning them.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(badges) { b in
                        VStack(spacing: 9) {
                            ZStack {
                                if !b.earned {
                                    Circle().fill(NTColor.milk(0.12)).overlay(Circle().stroke(NTColor.milk(0.16), lineWidth: 1))
                                } else {
                                    let colors = [Color(hexString: b.colorStart), Color(hexString: b.colorEnd)]
                                    Circle().fill(RadialGradient(colors: colors, center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: 50))
                                        .overlay(Circle().stroke(NTColor.milk(0.3), lineWidth: 1.5))
                                        .shadow(color: colors.last!.opacity(0.6), radius: 10, y: 6)
                                }
                                Image(systemName: b.earned ? b.icon : "lock.fill")
                                    .font(.system(size: 26))
                                    .foregroundStyle(b.earned ? NTColor.milk : NTColor.milk(0.5))
                            }
                            .frame(width: 84, height: 84)

                            Text(b.title).font(NTFont.body(11, .semibold)).multilineTextAlignment(.center)
                                .foregroundStyle(b.earned ? NTColor.milk : NTColor.milk(0.5))
                            Text(b.subtitle).font(NTFont.mono(8.5, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.45))
                        }
                    }
                }
            }
        }
    }

    private var routesList: some View {
        Group {
            if myRoutes.isEmpty && !isLoading {
                emptyState("No routes published", "Log a route to see it here.")
            } else {
                VStack(spacing: 12) {
                    ForEach(myRoutes) { r in
                        routeRow(title: r.title, meta: r.meta, likes: formatCount(r.likes), downloads: formatCount(r.saves))
                    }
                }
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private func routeRow(title: String, meta: String, likes: String, downloads: String) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                .fill(LinearGradient(colors: [NTColor.pineRaised, NTColor.pineShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(NTFont.heading(16, .bold))
                Text(meta).font(NTFont.mono(10.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                HStack(spacing: 14) {
                    Label(likes, systemImage: "heart").font(NTFont.mono(10.5, .medium))
                    Label(downloads, systemImage: "arrow.down").font(NTFont.mono(10.5, .medium))
                }
                .foregroundStyle(NTColor.milk(0.7))
            }
            Spacer()
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    /// Repurposes the NomadPoints ledger (real earn/spend events, already
    /// timestamped and audited — see RewardsView) as the Activity feed,
    /// instead of a separate invented activity log.
    private var activityList: some View {
        Group {
            if activity.isEmpty && !isLoading {
                emptyState("No activity yet", "Publish a route or get a follower and it'll show up here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(activity) { entry in
                        activityRow(entry)
                    }
                }
            }
        }
    }

    private func activityRow(_ entry: RouteRepository.PointsLedgerEntry) -> some View {
        let (icon, tint) = iconAndTint(for: entry.reason)
        return HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.2)))
            VStack(alignment: .leading, spacing: 7) {
                Text(activityLabel(entry.reason)).font(NTFont.body(14.5, .medium)).foregroundStyle(NTColor.milk)
                Text(relativeTime(entry.createdAt)).font(NTFont.mono(10, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.5))
            }
            Spacer()
            Text(entry.delta >= 0 ? "+\(entry.delta)" : "\(entry.delta)")
                .font(NTFont.mono(11, .semibold))
                .foregroundStyle(entry.delta >= 0 ? NTColor.sage : Color(hex: 0xE58272))
        }
        .padding(.vertical, 15)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
    }

    private func iconAndTint(for reason: String) -> (String, Color) {
        switch reason {
        case "route_published": return ("checkmark", NTColor.accent)
        case "new_follower": return ("person.badge.plus", NTColor.sage)
        case "route_liked": return ("heart.fill", Color(hex: 0xE58272))
        case "route_saved": return ("bookmark.fill", NTColor.sage)
        case "route_commented": return ("bubble.left.fill", NTColor.water)
        default:
            if reason.hasPrefix("redeemed_") { return ("star.fill", NTColor.gold) }
            return ("location.circle", NTColor.sage)
        }
    }

    private func activityLabel(_ reason: String) -> String {
        switch reason {
        case "route_published": return "Published a route"
        case "segment_added": return "Added a segment"
        case "requirement_added": return "Added gear/requirement"
        case "poi_added": return "Dropped a pin"
        case "cover_photo_added": return "Added a cover photo"
        case "route_liked": return "Someone liked your route"
        case "route_unliked": return "A like was removed"
        case "route_saved": return "Someone saved your route"
        case "route_unsaved": return "A save was removed"
        case "route_commented": return "Someone commented on your route"
        case "new_follower": return "Gained a follower"
        case "unfollowed": return "Lost a follower"
        default:
            if reason.hasPrefix("redeemed_") { return "Redeemed a reward" }
            return reason
        }
    }

    private func relativeTime(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "JUST NOW" }
        if seconds < 3600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86400 { return "\(Int(seconds / 3600))H AGO" }
        return "\(Int(seconds / 86400))D AGO"
    }

    private func emptyState(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(NTFont.body(14.5, .semibold)).foregroundStyle(NTColor.milk(0.7))
            Text(subtitle).font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.45))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

private extension Color {
    /// Local helper — badge colors come from the DB as "#RRGGBB" strings.
    init(hexString: String) {
        var s = hexString
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt32(s, radix: 16) ?? 0x5FA777
        self = Color(hex: value)
    }
}

#Preview {
    ProfileView()
}

import SwiftUI
import PhotosUI
import WidgetKit

/// 08 · Profile & badges — a data-terminal reading of "your account", not a
/// social-media one. The visual hero is real numbers (km/countries/routes/
/// streak), not the avatar+bio block; followers/likes are still here but
/// de-emphasized into the same muted-mono treatment as everything else
/// rather than living as their own decorative UI language. Anonymous
/// sessions (never signed up with a real email) see a sign-in prompt
/// instead of a fake identity.
///
/// Color note: this pass was asked to keep the *existing* status-color ramp
/// rather than invent a new one — as of this file, `NTColor.sage`/`.water`/
/// etc already run at the vivid/saturated values a previous pass moved them
/// to (see `NTColor.swift`'s own doc comments), not the muted values an
/// earlier design language used. The heatmap and verified badge below both
/// read `NTColor.sage` directly for exactly that reason: reusing today's
/// real ramp, not reintroducing a muted one.
struct ProfileView: View {
    enum Tab: String, CaseIterable { case routes = "Routes", leaderboard = "Leaderboard", activity = "Activity", badges = "Badges" }
    @State private var tab: Tab = .routes
    @State private var showSettings = false
    @State private var showAuth = false
    @State private var showEditProfile = false

    @State private var profile: RouteRepository.MyProfile?
    @State private var badges: [RouteRepository.MyBadge] = []
    /// Every one of this session's own routes, any status/visibility —
    /// `fetchMyRoutesFull()`, not the old lightweight `fetchMyRoutes()`. The
    /// stats hero, heatmap, streak and verified badge all need the real
    /// `trackPoints`/`createdAt`/`place`/`distanceKM` this carries.
    @State private var myRoutes: [Route] = []
    /// Every publicly-published route, any author — for the leaderboard and
    /// for the verified-badge rarity check ("how many other tracked routes
    /// exist at this place"). Not scoped to "my" anything.
    @State private var allRoutes: [Route] = []
    @State private var activity: [RouteRepository.PointsLedgerEntry] = []
    @State private var followerCount = 0
    @State private var isLoading = true
    /// This session's own real user id — needed to highlight "my" row on
    /// the leaderboard. `MyProfile` doesn't carry one, so it's fetched
    /// alongside everything else in `load()` rather than read synchronously
    /// (there's no synchronous session accessor anywhere in this codebase —
    /// every read of `supabase.auth.session` elsewhere is `await`ed).
    @State private var myUserId: String?

    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarPreview: UIImage?
    @State private var isUploadingAvatar = false
    @State private var avatarError: String?

    @State private var leaderboardWindow: LeaderboardWindow = .week
    @State private var leaderboardScope: LeaderboardScope = .global

    private var totalLikes: Int { myRoutes.reduce(0) { $0 + $1.likeCount } }

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if let avatarError {
                        Text(avatarError)
                            .font(NTFont.body(11.5, .medium))
                            .foregroundStyle(NTColor.hardBright)
                            .padding(.top, 8)
                    }

                    if profile?.isAnonymous == true {
                        anonymousPrompt
                    } else {
                        statsHero
                        secondaryCounters
                        referralCard

                        HStack(spacing: 4) {
                            ForEach(Tab.allCases, id: \.self) { t in
                                Button {
                                    withAnimation(NTMotion.spring) { tab = t }
                                } label: {
                                    Text(t.rawValue)
                                        .font(NTFont.body(12.5, .semibold))
                                        .foregroundStyle(tab == t ? NTColor.pine : NTColor.milk(0.7))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 40)
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
                            case .routes: routesList
                            case .leaderboard: leaderboard
                            case .activity: activitySection
                            case .badges: badgeGrid
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
        async let routesResult = (try? RouteRepository.shared.fetchMyRoutesFull()) ?? []
        async let allRoutesResult = (try? RouteRepository.shared.fetchRoutes()) ?? []
        async let activityResult = (try? RouteRepository.shared.fetchPointsLedger(limit: 20)) ?? []
        let resolvedProfile = await profileResult
        let resolvedBadges = await badgesResult
        let resolvedRoutes = await routesResult
        let resolvedAllRoutes = await allRoutesResult
        let resolvedActivity = await activityResult
        // Needs the real user id, which only exists once `profile` itself
        // resolved — can't run alongside the `async let`s above.
        let session = try? await supabase.auth.session
        let resolvedFollowers = await (session != nil ? RouteRepository.shared.fetchFollowerCount(userId: session!.user.id.uuidString) : 0)
        guard myToken == profileLoadToken else { return } // a newer load already superseded this one
        profile = resolvedProfile
        badges = resolvedBadges
        myRoutes = resolvedRoutes
        allRoutes = resolvedAllRoutes
        activity = resolvedActivity
        followerCount = resolvedFollowers
        myUserId = session?.user.id.uuidString
        isLoading = false

        if profile?.isAnonymous == false {
            pushWidgetSnapshot()
        }
    }

    /// Hands the Home Screen/Lock Screen widgets a fresh snapshot — same
    /// real numbers this screen itself just computed and is about to
    /// display, nothing recomputed specially for the widget. Silently
    /// skipped for an anonymous session (no real stats to show yet).
    private func pushWidgetSnapshot() {
        let snapshot = WidgetSnapshot(
            totalKM: totalKM,
            countriesVisited: countriesVisited,
            streakWeeks: currentStreak,
            heatmapWeeks: heatmapWeeks,
            displayName: profile?.displayName ?? "",
            lastUpdated: Date()
        )
        WidgetSnapshotStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var initials: String {
        guard let name = profile?.displayName, !name.isEmpty else { return "?" }
        return name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    // MARK: - Header (compact now — stats below are the real hero)

    private var header: some View {
        HStack(spacing: 14) {
            avatarPicker
            VStack(alignment: .leading, spacing: 5) {
                Text(profile?.isAnonymous == true ? "Anonymous nomad" : (profile?.displayName ?? "—"))
                    .font(NTFont.heading(20, .extraBold)).foregroundStyle(NTColor.milk)
                if profile?.isAnonymous != true {
                    Text("@\(profile?.username ?? "") · \((profile?.homeLocation ?? "NO HOME SET").uppercased())")
                        .font(NTFont.mono(10.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                }
            }
            if profile?.isAnonymous == false {
                Button { showEditProfile = true } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NTColor.milk(0.7))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(NTColor.milk(0.1)))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(NTColor.milk(0.75))
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(NTColor.milk(0.1)))
            }
            .buttonStyle(.plain)
        }
    }

    /// Tap-to-change, same as most apps — real upload via `PhotosPicker`
    /// (already the established pattern in this codebase for route cover
    /// photos, just aimed at `profiles.avatar_url`/a fixed per-user
    /// storage path instead). Anonymous sessions don't get the picker —
    /// there's no real account to attach a photo to yet. Shrunk from the
    /// old 84pt hero size — the stats header below is the visual hero now.
    private var avatarPicker: some View {
        let isReal = profile?.isAnonymous == false
        return PhotosPicker(selection: $avatarPickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let avatarPreview {
                        Image(uiImage: avatarPreview).resizable().aspectRatio(contentMode: .fill)
                    } else if let urlString = profile?.avatarUrl, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                avatarFallback
                            }
                        }
                    } else {
                        avatarFallback
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                if isReal {
                    ZStack {
                        Circle().fill(NTColor.pine)
                        if isUploadingAvatar {
                            ProgressView().tint(NTColor.milk).scaleEffect(0.5)
                        } else {
                            Image(systemName: "camera.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(NTColor.milk)
                        }
                    }
                    .frame(width: 20, height: 20)
                    .overlay(Circle().stroke(NTColor.pine, lineWidth: 2))
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!isReal || isUploadingAvatar)
        .onChange(of: avatarPickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadAvatar(newItem) }
        }
    }

    private var avatarFallback: some View {
        ZStack {
            LinearGradient(colors: [NTColor.accent, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials).font(NTFont.heading(18, .semibold)).foregroundStyle(NTColor.milk)
        }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        avatarError = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            avatarError = "Couldn't load that photo — try another."
            return
        }
        withAnimation(NTMotion.spring) { avatarPreview = image }
        let resized = image.resized(maxDimension: 600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.85) else { return }

        isUploadingAvatar = true
        do {
            let url = try await RouteRepository.shared.uploadAvatarImage(jpeg)
            try await RouteRepository.shared.updateMyAvatarUrl(url)
            profile = profile.map {
                RouteRepository.MyProfile(
                    username: $0.username, displayName: $0.displayName, homeLocation: $0.homeLocation,
                    kmLogged: $0.kmLogged, routesCompleted: $0.routesCompleted, badgeCount: $0.badgeCount,
                    avatarUrl: url, isAnonymous: $0.isAnonymous
                )
            }
        } catch {
            avatarError = "Upload failed — check your connection and try again."
            avatarPreview = nil
        }
        isUploadingAvatar = false
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

    // MARK: - Stats hero

    /// Real, dynamically computed from `myRoutes` — deliberately not read
    /// off `profiles.km_logged`/`routes_completed`, which are real columns
    /// nothing in the app actually writes to (see `RouteRepository`'s own
    /// doc comments on `PublicProfile`). "Countries" reads the country off
    /// the tail of each route's own `place` string ("SVANETI, GEORGIA" →
    /// "GEORGIA") rather than a network reverse-geocode — it's real data
    /// already sitting on the row, not an approximation.
    private var statsHero: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                heroStat(formatKM(totalKM), "KM LOGGED")
                heroStat("\(countriesVisited)", "COUNTRIES")
            }
            HStack(spacing: 0) {
                heroStat("\(myRoutes.count)", "ROUTES LOGGED")
                heroStat("\(currentStreak)W", "STREAK")
            }
        }
        .padding(.vertical, 20)
        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .bottom)
        .padding(.top, 22)
    }

    private func heroStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value).font(NTFont.mono(30, .semibold))
            Text(label).font(NTFont.mono(9.5, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    /// Followers/likes — kept, per spec, but folded down into the same
    /// small muted-mono treatment as every other number here instead of
    /// staying their own decorative "social" row.
    private var secondaryCounters: some View {
        HStack(spacing: 18) {
            secondaryCounter("\(followerCount)", "FOLLOWERS")
            secondaryCounter(formatCount(totalLikes), "LIKES")
            Spacer()
        }
        .padding(.top, 14)
    }

    private func secondaryCounter(_ value: String, _ label: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Text(value).font(NTFont.mono(13, .semibold)).foregroundStyle(NTColor.milk(0.85))
            Text(label).font(NTFont.mono(9, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.45))
        }
    }

    private var totalKM: Double { myRoutes.reduce(0) { $0 + $1.distanceKM } }

    private var countriesVisited: Int {
        Set(myRoutes.map { Self.countryTag(from: $0.place) }).count
    }

    /// Consecutive weeks, walking back from the current week, with at least
    /// one real `createdAt` among this session's own routes. The current
    /// week doesn't have to have a route in it yet to keep a prior streak
    /// alive — same "grace on today" convention most streak counters use —
    /// but a genuinely broken chain (a week fully skipped) stops the count.
    private var currentStreak: Int {
        Self.computeStreak(myRoutes.compactMap { $0.createdAt })
    }

    static func computeStreak(_ dates: [Date], now: Date = Date()) -> Int {
        guard !dates.isEmpty else { return 0 }
        let cal = Calendar.current
        func weekKey(_ d: Date) -> Int {
            cal.component(.yearForWeekOfYear, from: d) * 100 + cal.component(.weekOfYear, from: d)
        }
        let weeks = Set(dates.map(weekKey))
        var cursor = now
        if !weeks.contains(weekKey(cursor)) {
            guard let prior = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = prior
        }
        var streak = 0
        while weeks.contains(weekKey(cursor)) {
            streak += 1
            guard let prior = cal.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prior
        }
        return streak
    }

    /// "SVANETI, GEORGIA" → "GEORGIA". Falls back to the whole string,
    /// uppercased, if there's no comma to split on.
    static func countryTag(from place: String) -> String {
        guard let last = place.split(separator: ",").last else { return place.uppercased() }
        return last.trimmingCharacters(in: .whitespaces).uppercased()
    }

    // MARK: - Verified badge

    /// Ties directly to real GPS-track presence — the same `trackPoints`
    /// data Route Detail's own map draws from — rather than a separate
    /// invented "verification" flag. A route with 0 or 1 recorded points
    /// has no real track to verify against.
    private func isVerified(_ route: Route) -> Bool { route.detail.trackPoints.count > 1 }

    /// How many other real tracked routes exist at this same place —
    /// there's no "completed by N people" data anywhere in this schema (no
    /// per-user completion tracking at all), so this is the honest real
    /// substitute: distinct verified routes logged at the same `place`
    /// string, this one included.
    private func rarityCount(_ route: Route) -> Int {
        allRoutes.filter { $0.place == route.place && isVerified($0) }.count
    }

    @ViewBuilder
    private func verifiedBadge(_ route: Route) -> some View {
        if isVerified(route) {
            let rarity = rarityCount(route)
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 9))
                if rarity < 10 {
                    Text("VERIFIED · \(rarity) TRACKED HERE")
                } else {
                    Text("VERIFIED")
                }
            }
            .font(NTFont.mono(8.5, .semibold))
            .tracking(0.4)
            .foregroundStyle(NTColor.sage)
        }
    }

    // MARK: - Referral / invite card

    /// Styled as an invite, not a payout — no point count, no monetary
    /// framing, single card, terracotta CTA (the one accent use on this
    /// screen). Same real `ShareLink` pattern Route Detail's own share
    /// button already uses, plain text rather than a deep link this app
    /// doesn't have.
    private var referralCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NTColor.accent)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(NTColor.accent.opacity(0.15)))
                Text("Invite a friend").font(NTFont.body(14.5, .semibold)).foregroundStyle(NTColor.milk)
                Spacer()
            }
            Text("You both unlock early access to the next region we open up.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.6))
            ShareLink(item: "Come log real routes with me on NomadCompass.") {
                Text("Send invite")
                    .font(NTFont.body(13, .semibold))
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(NTColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.1), lineWidth: 1))
        .padding(.top, 18)
    }

    private func formatKM(_ km: Double) -> String {
        km >= 1000 ? String(format: "%.0f", km) : String(format: "%.1f", km)
    }

    // MARK: - Badges tab (unchanged)

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

    // MARK: - Routes tab

    private var routesList: some View {
        Group {
            if myRoutes.isEmpty && !isLoading {
                emptyState("No routes published", "Log a route to see it here.")
            } else {
                VStack(spacing: 12) {
                    ForEach(myRoutes) { r in
                        routeRow(r)
                    }
                }
            }
        }
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private func routeRow(_ route: Route) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                .fill(LinearGradient(colors: [NTColor.pineRaised, NTColor.pineShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 8) {
                Text(route.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.heading(16, .bold))
                Text("\(String(format: "%.1f", route.distanceKM)) KM · \(route.transportLabel)")
                    .font(NTFont.mono(10.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                verifiedBadge(route)
                HStack(spacing: 14) {
                    Label(formatCount(route.likeCount), systemImage: "heart").font(NTFont.mono(10.5, .medium))
                    Label(formatCount(route.saveCount), systemImage: "arrow.down").font(NTFont.mono(10.5, .medium))
                }
                .foregroundStyle(NTColor.milk(0.7))
            }
            Spacer()
        }
        .padding(14)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    // MARK: - Leaderboard tab

    enum LeaderboardWindow: String, CaseIterable { case week = "This week", month = "This month" }
    enum LeaderboardScope: String, CaseIterable { case global = "Global", region = "My region" }

    private struct LeaderboardEntry: Identifiable {
        let id: String
        let author: Author
        let km: Double
        let routeCount: Int
    }

    /// Client-side aggregation over `allRoutes` (already-fetched published
    /// routes) — same "fine at the current real data volume, would want
    /// server-side aggregation if it grows a lot" tradeoff already made and
    /// documented for `RegionMapPickerView.loadCountryPins()`.
    private var leaderboardEntries: [LeaderboardEntry] {
        let cal = Calendar.current
        let windowStart: Date? = {
            switch leaderboardWindow {
            case .week: return cal.date(byAdding: .day, value: -7, to: Date())
            case .month: return cal.date(byAdding: .day, value: -30, to: Date())
            }
        }()
        let myCountry = profile?.homeLocation.map { Self.countryTag(from: $0) }

        var byAuthor: [String: (author: Author, km: Double, count: Int)] = [:]
        for route in allRoutes {
            guard let created = route.createdAt, let windowStart, created >= windowStart else { continue }
            if leaderboardScope == .region, let myCountry, Self.countryTag(from: route.place) != myCountry { continue }
            var entry = byAuthor[route.author.id] ?? (author: route.author, km: 0, count: 0)
            entry.km += route.distanceKM
            entry.count += 1
            byAuthor[route.author.id] = entry
        }
        return byAuthor.values
            .map { LeaderboardEntry(id: $0.author.id, author: $0.author, km: $0.km, routeCount: $0.count) }
            .sorted { $0.km > $1.km }
    }

    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                segmentedPicker(LeaderboardWindow.allCases, selection: $leaderboardWindow) { $0.rawValue }
                segmentedPicker(LeaderboardScope.allCases, selection: $leaderboardScope) { $0.rawValue }
            }

            if leaderboardScope == .region && profile?.homeLocation == nil {
                emptyState("No home location set", "Set one in Edit Profile to see your regional ranking.")
            } else if leaderboardEntries.isEmpty && !isLoading {
                emptyState("Nothing logged in this window", "Be the first — publish a route to appear here.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(leaderboardEntries.enumerated()), id: \.element.id) { index, entry in
                        leaderboardRow(rank: index + 1, entry: entry)
                    }
                }
            }
        }
    }

    private func segmentedPicker<T: Hashable & CaseIterable>(_ cases: [T], selection: Binding<T>, label: @escaping (T) -> String) -> some View where T.AllCases: RandomAccessCollection {
        HStack(spacing: 2) {
            ForEach(Array(cases), id: \.self) { c in
                Button { withAnimation(NTMotion.spring) { selection.wrappedValue = c } } label: {
                    Text(label(c))
                        .font(NTFont.mono(9.5, .medium))
                        .tracking(0.3)
                        .foregroundStyle(selection.wrappedValue == c ? NTColor.pine : NTColor.milk(0.6))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Capsule().fill(selection.wrappedValue == c ? NTColor.milk : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(NTColor.milk(0.08)))
    }

    private func leaderboardRow(rank: Int, entry: LeaderboardEntry) -> some View {
        let isMe = myUserId != nil && entry.id == myUserId
        return HStack(spacing: 12) {
            Text("\(rank)")
                .font(NTFont.mono(12, .semibold))
                .foregroundStyle(isMe ? NTColor.accent : NTColor.milk(0.45))
                .frame(width: 20, alignment: .leading)
            AvatarView(author: entry.author, size: 30)
            Text(entry.author.name)
                .font(NTFont.body(13.5, .medium))
                .foregroundStyle(isMe ? NTColor.accent : NTColor.milk(0.9))
                .lineLimit(1)
            Spacer()
            Text("\(entry.routeCount)")
                .font(NTFont.mono(11, .medium))
                .foregroundStyle(NTColor.milk(0.45))
                .frame(width: 26, alignment: .trailing)
            Text(formatKM(entry.km) + " KM")
                .font(NTFont.mono(12.5, .semibold))
                .foregroundStyle(isMe ? NTColor.accent : NTColor.milk(0.85))
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.vertical, 12)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Activity tab (heatmap + real ledger)

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("ACTIVITY").font(NTFont.mono(9.5, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.5))
                heatmap
            }
            activityList
        }
    }

    /// GitHub-contribution-style grid — real `createdAt` weeks from this
    /// session's own routes, intensity via the existing (vivid) sage rather
    /// than a new heat-color scale. Horizontally scrollable since 20 weeks
    /// doesn't fit most phone widths at a legible cell size.
    private var heatmap: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 3) {
                ForEach(Array(heatmapWeeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: 3) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, count in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(heatColor(count))
                                .frame(width: 11, height: 11)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func heatColor(_ count: Int) -> Color {
        switch count {
        case 0: return NTColor.milk(0.08)
        case 1: return NTColor.sage.opacity(0.35)
        case 2: return NTColor.sage.opacity(0.65)
        default: return NTColor.sage
        }
    }

    /// `[week][weekday]` counts, oldest week first, current week last —
    /// last 20 weeks (~5 months), which is what reasonably fits on-screen.
    private var heatmapWeeks: [[Int]] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let startOfThisWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)) else { return [] }

        var counts: [Date: Int] = [:]
        for date in myRoutes.compactMap({ $0.createdAt }) {
            counts[cal.startOfDay(for: date), default: 0] += 1
        }

        var weeks: [[Int]] = []
        for w in stride(from: 19, through: 0, by: -1) {
            guard let weekStart = cal.date(byAdding: .weekOfYear, value: -w, to: startOfThisWeek) else { continue }
            var days: [Int] = []
            for d in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: d, to: weekStart) else { days.append(0); continue }
                days.append(counts[day] ?? 0)
            }
            weeks.append(days)
        }
        return weeks
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
                .foregroundStyle(entry.delta >= 0 ? NTColor.sage : NTColor.hardBright)
        }
        .padding(.vertical, 15)
        .overlay(Rectangle().fill(NTColor.milk(0.1)).frame(height: 1), alignment: .bottom)
    }

    private func iconAndTint(for reason: String) -> (String, Color) {
        switch reason {
        case "route_published": return ("checkmark", NTColor.accent)
        case "new_follower": return ("person.badge.plus", NTColor.sage)
        case "route_liked": return ("heart.fill", NTColor.hardBright)
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

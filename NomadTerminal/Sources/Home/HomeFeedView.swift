import SwiftUI

/// 04 · Home feed — a dense, scannable list, not a one-at-a-time swipe.
/// Used to page full-screen through routes Reels-style, which physically
/// prevents comparing more than one route at once — exactly the opposite
/// of how someone planning a trip actually decides (Strava/AllTrails/komoot/
/// onX all use this same list-of-cards pattern for that reason). Following/
/// Nearby/Wild are filter chips now, not full-screen tabs.
struct HomeFeedView: View {
    enum FeedTab: String, CaseIterable {
        case following = "Following", nearby = "Nearby", wild = "Wild"

        /// Chip label — decoupled from `rawValue` on purpose. `.nearby`
        /// displays as "All" per an explicit ask, while the case's own
        /// identity/fetch behind it (real GPS-proximity filtering via
        /// `fetchNearbyRoutes`, not the actual full catalog — that's
        /// `.wild`) stays exactly what it was; only the chip's own text
        /// changed.
        var label: LocalizedStringKey { self == .nearby ? "All" : LocalizedStringKey(rawValue) }
    }

    /// `.nearby`, not `.following`, is what a new install lands on — most
    /// people haven't followed anyone yet, so `.following` defaulted to an
    /// empty state on first open.
    @State private var feedTab: FeedTab = .nearby
    @State private var openRoute: Route?
    @State private var openAuthor: String?
    @State private var routes: [Route] = []
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var showLogRoute = false
    @State private var showActivity = false
    @State private var locationSearcher = PlaceSearcher()
    @State private var loadToken = 0

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            if routes.isEmpty && !isLoading {
                emptyTabState.padding(.top, 130)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        ForEach(routes) { route in
                            routeRow(route)
                                .scrollTransition { content, phase in
                                    // Cheap, system-driven depth-on-scroll —
                                    // no per-frame GeometryReader math: cards
                                    // ease in as they enter the viewport
                                    // instead of just appearing.
                                    content
                                        .opacity(phase.isIdentity ? 1 : 0.6)
                                        .scaleEffect(phase.isIdentity ? 1 : 0.96)
                                }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 118)
                    .padding(.bottom, 110)
                }
                .transition(.opacity)
            }

            topBar

            if isOffline {
                offlineBanner
            }

            if isLoading {
                ProgressView()
                    .tint(NTColor.milk)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .allowsHitTesting(false)
            }
        }
        .fullScreenCover(item: $openRoute) { route in
            RouteDetailFlow(route: route)
        }
        .fullScreenCover(isPresented: Binding(get: { openAuthor != nil }, set: { if !$0 { openAuthor = nil } }), onDismiss: { Task { await loadRoutes() } }) {
            if let openAuthor {
                AuthorProfileView(userId: openAuthor, onClose: { self.openAuthor = nil })
            }
        }
        .fullScreenCover(isPresented: $showActivity) {
            NotificationsView(onClose: { showActivity = false })
        }
        .fullScreenCover(isPresented: $showLogRoute, onDismiss: { Task { await loadRoutes() } }) {
            LogRouteFlow()
        }
        .task { await loadRoutes() }
        .onChange(of: feedTab) { _, _ in Task { await loadRoutes() } }
    }

    private var emptyTabState: some View {
        VStack(spacing: 10) {
            Image(systemName: feedTab == .following ? "person.2" : "location.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(NTColor.milk(0.4))
            Text(feedTab == .following ? "Not following anyone yet" : "Nothing near you yet")
                .font(NTFont.body(15, .semibold))
                .foregroundStyle(NTColor.milk(0.8))
            Text(feedTab == .following
                 ? "Follow someone from a route you like and their routes show up here."
                 : "\"All\" still means routes near you — it needs your location and a real recorded track nearby. Check Wild for everything published so far.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
    }

    private func loadRoutes() async {
        // Used to start `routes` pre-filled with the mock feed, then swap
        // it for live data once the fetch resolved — which meant every
        // launch briefly showed the mock "Zagar Pass" card and then visibly
        // replaced it with the real first route a moment later (the "one
        // route pops up and immediately gets covered by another" bug).
        // Starting empty and only setting `routes` once, after we actually
        // know which data we're showing, makes that swap impossible.
        loadToken += 1
        let myToken = loadToken
        withAnimation(NTMotion.spring) { isLoading = true }
        do {
            try await RouteRepository.shared.ensureSession()
            let live: [Route]
            switch feedTab {
            case .following:
                // Real subset — routes authored by people this session
                // actually follows. Used to just silently show the same
                // content as every other tab regardless of selection.
                live = try await RouteRepository.shared.fetchFollowingRoutes()
            case .nearby:
                live = try await fetchNearby()
            case .wild:
                live = try await RouteRepository.shared.fetchRoutes()
            }
            if myToken != loadToken { return } // a newer tab switch already superseded this fetch
            withAnimation(NTMotion.spring) {
                routes = feedTab == .wild && live.isEmpty ? Route.mock : live
            }
            isOffline = false
        } catch {
            // Offline or backend hiccup — fall back to the mock feed so the
            // app stays usable, matching the "cache tiles… survives four
            // days without a bar of service" promise from onboarding.
            print("Route fetch failed, falling back to mock feed: \(error)")
            if myToken != loadToken { return }
            withAnimation(NTMotion.spring) {
                routes = feedTab == .wild ? Route.mock : []
            }
            isOffline = feedTab == .wild
        }
        if myToken == loadToken { withAnimation(NTMotion.spring) { isLoading = false } }
    }

    /// Waits briefly for a real GPS fix before falling back to "no location
    /// yet" — `CLLocationManager.requestLocation()` is async/delegate-based,
    /// so the first call after granting permission can't be read synchronously.
    private func fetchNearby() async throws -> [Route] {
        if locationSearcher.currentLocation == nil {
            locationSearcher.requestLocation()
            for _ in 0..<20 {
                if locationSearcher.currentLocation != nil || locationSearcher.authorizationDenied { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        guard let here = locationSearcher.currentLocation else { return [] }
        return try await RouteRepository.shared.fetchNearbyRoutes(from: here.coordinate)
    }

    private var offlineBanner: some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash").font(.system(size: 12, weight: .semibold))
                Text("No signal — showing offline data").font(NTFont.body(12, .semibold))
            }
            .foregroundStyle(NTColor.milk)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(NTColor.gold.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(NTColor.gold.opacity(0.5), lineWidth: 1))
            .padding(.top, 118)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    // MARK: - Top bar + filter chips

    private var topBar: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Home").font(NTFont.heading(24, .extraBold)).foregroundStyle(NTColor.milk)
                Spacer()
                Button { showActivity = true } label: {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(NTColor.milk)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(NTColor.milk(0.08)))
                        .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .ntPressable()
                .accessibilityLabel(Text("Activity"))
                Button { showLogRoute = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x231007))
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(NTColor.accent))
                        .shadow(color: NTColor.accent.opacity(0.5), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .ntPressable()
            }

            HStack(spacing: 8) {
                ForEach(FeedTab.allCases, id: \.self) { tab in
                    filterChip(tab)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .background(
            LinearGradient(colors: [NTColor.pine, NTColor.pine.opacity(0.94), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
        )
    }

    private func filterChip(_ tab: FeedTab) -> some View {
        let selected = feedTab == tab
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(NTMotion.spring) { feedTab = tab }
        } label: {
            Text(tab.label)
                .font(NTFont.body(13, .semibold))
                .foregroundStyle(selected ? NTColor.pine : NTColor.milk(0.7))
                .padding(.horizontal, 16)
                .frame(height: 38)
                .background(Capsule().fill(selected ? NTColor.milk : NTColor.milk(0.08)))
                .overlay(Capsule().stroke(NTColor.milk(0.16), lineWidth: selected ? 0 : 1))
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: nil)
    }

    // MARK: - Route row

    // Plain view + `.onTapGesture`, deliberately NOT a real `Button` (with
    // or without a custom `ButtonStyle`) — the previous fix swapped
    // `.ntPressable()`'s competing `DragGesture` for a `ButtonStyle`, which
    // should have been gesture-safe in principle but evidently still wasn't
    // enough in practice (reported still broken after that fix). This is
    // the one interaction pattern already proven, in this exact codebase,
    // to coexist with a `ScrollView`/`LazyVGrid` without eating its scroll
    // gesture — `SavedView`'s grid tiles use the identical pattern. Trading
    // the scale-on-press visual for a guaranteed-correct scroll.
    private func routeRow(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    RouteCoverImage(url: route.coverImageUrl, tint: route.transport.color)
                        .aspectRatio(16 / 10, contentMode: .fill)
                        .frame(height: 190)
                        .clipped()

                    // A bottom-only scrim so the place pill stays legible —
                    // never a wash over the whole photo.
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center, endPoint: .bottom
                    )
                    .frame(height: 190)
                    .allowsHitTesting(false)

                    HStack(spacing: 6) {
                        Image(systemName: "location.fill").font(.system(size: 10))
                        Text(route.place)
                            .font(NTFont.mono(10, .semibold))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                    .background(Capsule().fill(.black.opacity(0.2)))
                    .padding(12)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(route.title.replacingOccurrences(of: "\n", with: " "))
                        .font(NTFont.heading(18, .bold))
                        .foregroundStyle(NTColor.milk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(route.difficulty.rawValue))
                            .font(NTFont.mono(9.5, .semibold))
                            .tracking(0.6)
                            .foregroundStyle(NTColor.pine)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(route.difficulty.color))
                        HStack(spacing: 5) {
                            Image(systemName: route.transport.icon).font(.system(size: 10))
                            Text(LocalizedStringKey(route.transportLabel)).font(NTFont.mono(9.5, .semibold)).tracking(0.4)
                        }
                        .foregroundStyle(NTColor.milk(0.75))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .overlay(Capsule().stroke(NTColor.milk(0.2), lineWidth: 1))
                    }

                    HStack {
                        HStack(spacing: 8) {
                            AvatarView(author: route.author, size: 24)

                            Text(route.author.name)
                                .font(NTFont.body(12.5, .medium))
                                .foregroundStyle(NTColor.milk(0.7))
                                .lineLimit(1)
                        }
                        // A real, separate tap target from the card's own
                        // "open this route" tap — was previously just inert
                        // text with nowhere to go.
                        .contentShape(Rectangle())
                        .onTapGesture { openAuthor = route.author.id }

                        Spacer(minLength: 8)

                        Text(String(format: "%.1f KM", route.distanceKM))
                            .font(NTFont.mono(11, .semibold))
                            .tracking(0.4)
                            .foregroundStyle(NTColor.milk(0.55))
                    }
                }
                .padding(14)
            }
        .background(NTColor.pineRaised, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.08), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { openRoute = route }
    }
}

#Preview {
    HomeFeedView()
}

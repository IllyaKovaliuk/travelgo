import SwiftUI

/// 04 · Home feed — vertical Reels-style paging through routes.
struct HomeFeedView: View {
    enum FeedTab: String, CaseIterable { case following = "Following", nearby = "Nearby", wild = "Wild" }

    @State private var feedTab: FeedTab = .following
    @State private var scrollPosition: String?
    @State private var openRoute: Route?
    @State private var routes: [Route] = []
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var showLogRoute = false
    @State private var showNotifications = false
    @State private var locationSearcher = PlaceSearcher()
    @State private var loadToken = 0

    var body: some View {
        ZStack(alignment: .top) {
            if routes.isEmpty && !isLoading {
                emptyTabState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(routes) { route in
                            RouteCard(route: route, onOpen: { openRoute = route })
                                .containerRelativeFrame(.vertical)
                                .id(route.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $scrollPosition)
                .scrollTargetBehavior(.paging)
                .ignoresSafeArea()
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
        .background(NTColor.pineDeep)
        .fullScreenCover(item: $openRoute) { route in
            RouteDetailFlow(route: route)
        }
        .fullScreenCover(isPresented: $showLogRoute, onDismiss: { Task { await loadRoutes() } }) {
            LogRouteFlow()
        }
        .fullScreenCover(isPresented: $showNotifications) {
            NotificationsView(onClose: { showNotifications = false })
        }
        .task { await loadRoutes() }
        .onChange(of: feedTab) { _, _ in Task { await loadRoutes() } }
    }

    private var emptyTabState: some View {
        VStack(spacing: 10) {
            Image(systemName: feedTab == .following ? "person.2" : "location.slash")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(NTColor.milk(0.4))
            Text(feedTab == .following ? "Not following anyone yet" : "No nearby routes yet")
                .font(NTFont.body(15, .semibold))
                .foregroundStyle(NTColor.milk(0.8))
            Text(feedTab == .following
                 ? "Follow someone from a route you like and their routes show up here."
                 : "Nearby needs your location and routes with a real recorded track — check Wild for everything published so far.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        withAnimation { isLoading = true }
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
            routes = feedTab == .wild && live.isEmpty ? Route.mock : live
            isOffline = false
        } catch {
            // Offline or backend hiccup — fall back to the mock feed so the
            // app stays usable, matching the "cache tiles… survives four
            // days without a bar of service" promise from onboarding.
            print("Route fetch failed, falling back to mock feed: \(error)")
            if myToken != loadToken { return }
            routes = feedTab == .wild ? Route.mock : []
            isOffline = feedTab == .wild
        }
        if myToken == loadToken { withAnimation { isLoading = false } }
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
            .padding(.top, 62)
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 20) {
                ForEach(FeedTab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { feedTab = tab }
                    } label: {
                        Text(tab.rawValue)
                            .font(NTFont.body(14, .semibold))
                            .foregroundStyle(feedTab == tab ? NTColor.milk : NTColor.milk(0.55))
                            .overlay(alignment: .bottom) {
                                if feedTab == tab {
                                    Rectangle().fill(NTColor.milk).frame(height: 2).offset(y: 7)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            Button { showNotifications = true } label: {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(NTColor.milk(0.85))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .ntPressable(haptic: nil)

            Button { showLogRoute = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(NTColor.accent))
                    .shadow(color: NTColor.accent.opacity(0.6), radius: 12, y: 4)
            }
            .buttonStyle(.plain)
            .ntPressable()
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }
}

#Preview {
    HomeFeedView()
}

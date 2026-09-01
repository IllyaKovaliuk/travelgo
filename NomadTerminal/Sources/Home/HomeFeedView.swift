import SwiftUI

/// 04 · Home feed — vertical Reels-style paging through routes.
struct HomeFeedView: View {
    enum FeedTab: String, CaseIterable { case following = "Following", nearby = "Nearby", wild = "Wild" }

    @State private var feedTab: FeedTab = .following
    @State private var scrollPosition: String?
    @State private var openRoute: Route?
    @State private var routes: [Route] = Route.mock
    @State private var isLoading = true
    @State private var isOffline = false
    @State private var showLogRoute = false
    @State private var showNotifications = false

    var body: some View {
        ZStack(alignment: .top) {
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
    }

    private func loadRoutes() async {
        do {
            try await RouteRepository.shared.ensureSession()
            let live = try await RouteRepository.shared.fetchRoutes()
            if !live.isEmpty {
                withAnimation(.easeInOut(duration: 0.3)) { routes = live }
                isOffline = false
            }
        } catch {
            // Offline or backend hiccup — the mock feed already on screen
            // keeps the app usable, matching the "cache tiles… survives
            // four days without a bar of service" promise from onboarding.
            print("Route fetch failed, staying on mock feed: \(error)")
            withAnimation { isOffline = true }
        }
        withAnimation { isLoading = false }
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

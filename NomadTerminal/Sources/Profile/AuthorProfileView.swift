import SwiftUI

/// A real page for someone else's account — tap an author's name/avatar
/// anywhere in the app (a route card, Route Detail) and land here instead
/// of nowhere. Previously there was no such screen at all: `ProfileView`
/// only ever reads the *current* session's own profile, so an author's
/// name was just inert text everywhere it appeared.
///
/// Shows their real published routes ("routes he created" — a real,
/// queryable list), a real Follow button, real follower count, and the
/// real total likes across everything they've published.
///
/// `profile.kmLogged` (below) used to be a dead column — real schema,
/// nothing ever wrote to it, so this stat silently read 0 for every
/// account. Now server-maintained by a trigger on `routes` (see
/// `20260929000001_profile_route_stats_trigger.sql`), scoped to this
/// author's published + public routes, kept in sync on every
/// insert/update/delete rather than summed client-side on every profile
/// view. Same trigger also finally populates `routes_completed` — this
/// screen still counts "routes created" from the real fetched list
/// (`routes.count`) rather than that column, since the list is fetched
/// here anyway for display; the two now agree.
struct AuthorProfileView: View {
    let userId: String
    var onClose: () -> Void

    @State private var profile: RouteRepository.PublicProfile?
    @State private var routes: [Route] = []
    @State private var isLoading = true
    @State private var isFollowing = false
    @State private var isOwnProfile = false
    @State private var followerCount = 0
    @State private var isBlocked = false
    @State private var showBlockConfirm = false
    @State private var blockFailed = false

    /// Real sum across their published routes — `fetchUserRoutes` already
    /// embeds each route's real `likes:route_likes(count)`, so this is
    /// totalling data already on hand, not a second query.
    private var totalLikes: Int { routes.reduce(0) { $0 + $1.likeCount } }
    /// Opens its own `RouteDetailFlow` rather than bouncing the tap back up
    /// to whoever presented this screen — self-contained, so any call site
    /// (a route card, Route Detail's author row, …) can present this the
    /// same simple way.
    @State private var openRoute: Route?

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topBar

                    if isLoading {
                        ProgressView().tint(NTColor.milk).padding(.top, 80).frame(maxWidth: .infinity)
                    } else if let profile {
                        header(profile)
                        statsRow(profile)
                        if !isOwnProfile {
                            followButton.padding(.top, 18)
                        }
                        routesSection.padding(.top, 30)
                    } else {
                        notFoundState.padding(.top, 80)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(NTColor.milk)
        .fullScreenCover(item: $openRoute, onDismiss: { Task { await load() } }) { route in
            RouteDetailFlow(route: route)
        }
        .task { await load() }
        .alert("Block this user?", isPresented: $showBlockConfirm) {
            Button("Block", role: .destructive) { block() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their routes, comments and photos will be hidden from you everywhere in Nomad. You can unblock them any time in Settings.")
        }
        .alert("Couldn't update the block list", isPresented: $blockFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Check your connection and try again.")
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.08)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            if profile != nil && !isOwnProfile {
                Menu {
                    if isBlocked {
                        Button { unblock() } label: { Label("Unblock user", systemImage: "hand.raised.slash") }
                    } else {
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("Block user", systemImage: "hand.raised")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(NTColor.milk(0.08)))
                        .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                }
                .accessibilityLabel(Text("More"))
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private func block() {
        Task {
            do {
                try await RouteRepository.shared.blockUser(userId)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isBlocked = true
                onClose()
            } catch {
                blockFailed = true
            }
        }
    }

    private func unblock() {
        Task {
            do {
                try await RouteRepository.shared.unblockUser(userId)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                isBlocked = false
                await load()
            } catch {
                blockFailed = true
            }
        }
    }

    private func header(_ profile: RouteRepository.PublicProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if let urlString = profile.avatarUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            avatarFallback(profile)
                        }
                    }
                } else {
                    avatarFallback(profile)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(profile.displayName).font(NTFont.heading(26, .extraBold)).foregroundStyle(NTColor.milk)
                Text("@\(profile.username) · \((profile.homeLocation ?? "NO HOME SET").uppercased())")
                    .font(NTFont.mono(11.5, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
            }
        }
    }

    private func avatarFallback(_ profile: RouteRepository.PublicProfile) -> some View {
        ZStack {
            LinearGradient(colors: [NTColor.accent, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(profile.initials).font(NTFont.heading(28, .semibold)).foregroundStyle(.white)
        }
    }

    private func statsRow(_ profile: RouteRepository.PublicProfile) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                statBlock(formatKM(profile.kmLogged), "KM LOGGED")
                statBlock("\(routes.count)", "ROUTES CREATED")
            }
            HStack(spacing: 0) {
                statBlock("\(followerCount)", "FOLLOWERS")
                statBlock(formatCount(totalLikes), "LIKES")
            }
        }
        .padding(.vertical, 18)
        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .top)
        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .bottom)
        .padding(.top, 22)
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private func statBlock(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(NTFont.mono(22, .semibold))
            Text(label).font(NTFont.mono(9.5, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var followButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(NTMotion.spring) {
                isFollowing.toggle()
                // Real, immediate local update — was previously stuck at
                // whatever `load()` last fetched until this whole screen
                // was torn down and re-created (leave, come back), same
                // bug `RouteDetailView`'s own like counter had until it
                // got this exact fix.
                followerCount += isFollowing ? 1 : -1
            }
            let newValue = isFollowing
            Task { try? await RouteRepository.shared.setFollowing(authorId: userId, following: newValue) }
        } label: {
            Text(isFollowing ? "Following" : "Follow")
                .font(NTFont.body(14.5, .semibold))
                .foregroundStyle(isFollowing ? NTColor.milk : NTColor.pine)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(isFollowing ? .clear : NTColor.milk))
                .overlay(Capsule().stroke(NTColor.milk(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .ntPressable(haptic: nil)
    }

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Routes").font(NTFont.heading(18, .bold)).foregroundStyle(NTColor.milk)

            if routes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "map").font(.system(size: 26)).foregroundStyle(NTColor.milk(0.3))
                    Text("Nothing published yet").font(NTFont.body(13.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            } else {
                VStack(spacing: 12) {
                    ForEach(routes) { route in
                        routeRow(route)
                            .contentShape(Rectangle())
                            .onTapGesture { openRoute = route }
                    }
                }
            }
        }
    }

    private func routeRow(_ route: Route) -> some View {
        HStack(spacing: 12) {
            RouteCoverImage(url: route.coverImageUrl, tint: route.transport.color)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(route.title.replacingOccurrences(of: "\n", with: " "))
                    .font(NTFont.body(14.5, .semibold))
                    .foregroundStyle(NTColor.milk)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(route.difficulty.rawValue))
                    Text("·")
                    Text(String(format: "%.1f KM", route.distanceKM))
                }
                .font(NTFont.mono(10.5, .medium))
                .foregroundStyle(NTColor.milk(0.55))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(NTColor.milk(0.4))
        }
        .padding(10)
        .background(NTColor.pineRaised, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.08), lineWidth: 1))
    }

    private var notFoundState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.slash").font(.system(size: 28)).foregroundStyle(NTColor.milk(0.3))
            Text("Couldn't load this profile").font(NTFont.body(14.5, .semibold))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatKM(_ km: Double) -> String {
        km >= 1000 ? String(format: "%.1fK", km / 1000) : String(format: "%.0f", km)
    }

    private func load() async {
        async let profileResult: RouteRepository.PublicProfile? = try? RouteRepository.shared.fetchPublicProfile(userId: userId)
        async let routesResult: [Route] = (try? RouteRepository.shared.fetchUserRoutes(authorId: userId)) ?? []
        async let followingResult: Bool = RouteRepository.shared.isFollowing(authorId: userId)
        async let followerResult: Int = RouteRepository.shared.fetchFollowerCount(userId: userId)
        async let blockedResult: Bool = RouteRepository.shared.isBlocked(userId)
        isBlocked = await blockedResult
        profile = await profileResult
        routes = await routesResult
        isFollowing = await followingResult
        followerCount = await followerResult
        if let session = try? await supabase.auth.session {
            isOwnProfile = session.user.id.uuidString == userId
        }
        isLoading = false
    }
}

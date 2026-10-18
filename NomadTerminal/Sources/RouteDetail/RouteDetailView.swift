import SwiftUI
import MapboxMaps

/// 05 · Route detail — scrolls.
struct RouteDetailView: View {
    @State private var route: Route
    var onNavigate: () -> Void

    init(route: Route, onNavigate: @escaping () -> Void) {
        _route = State(initialValue: route)
        self.onNavigate = onNavigate
    }

    @Environment(\.dismiss) private var dismiss
    @State private var savedOffline = false
    @State private var isDownloading = false
    /// Real fraction from `OfflineMapStore`'s tile-region progress callback,
    /// not a spinner pretending — the tile download is the slow part (style
    /// packs are small and finish before this starts moving).
    @State private var downloadProgress: Double = 0
    @State private var cachedSnapshot: UIImage?
    @State private var showFullMap = false
    @State private var routeHazards = HazardStore()
    @State private var showEditExtras = false
    @State private var showPaywall = false
    @State private var subscription = SubscriptionManager.shared
    /// Lives here, not inside `RouteMapHeader`, so the itinerary panel below
    /// can drive the same camera when a leg is tapped — one connected
    /// experience, not a map and a list that don't know about each other.
    @State private var mapViewport: Viewport = .styleDefault
    /// Real ownership check (real session's user id vs. this route's real
    /// author id) — the Edit entry point below only shows for the actual
    /// author, not decided by anything client-fakeable.
    @State private var isOwner = false
    @State private var currentUserId: String?
    // Route Detail had zero way to like or open comments — only the Home
    // feed card did. Same real actions, same real counts, just reachable
    // from the screen people actually read the route on.
    @State private var liked = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var showComments = false
    @State private var downloadToast: String?
    @State private var showAuthorProfile = false

    private var detail: RouteDetailInfo { route.detail }
    /// A computed property, not something cached once — `route` is
    /// `@State` here and really does get reassigned after a real edit
    /// (`EditRouteExtrasView`'s `route = updated` below), so this has to
    /// stay reactive to that or the map would keep showing pre-edit
    /// segments. The smoothing pass itself is cheap at this app's real
    /// point counts.
    private var segmentStretches: [MapSegmentStretch] {
        MapSegmentStretch.compute(trackPoints: detail.trackPoints, segments: detail.segments)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    RouteMapHeader(
                        segments: detail.segments, trackPoints: detail.trackPoints, pois: detail.pois,
                        cachedSnapshot: cachedSnapshot, viewport: $mapViewport, onBack: { dismiss() },
                        onOpenFullMap: { showFullMap = true }
                    )

                    VStack(alignment: .leading, spacing: 0) {
                        Capsule().fill(NTColor.milk(0.25)).frame(width: 44, height: 4)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 20)

                        Text(detail.coordinates)
                            .font(NTFont.mono(11, .medium))
                            .tracking(0.8)
                            .foregroundStyle(NTColor.milk(0.55))

                        Text(route.title.replacingOccurrences(of: "\n", with: " "))
                            .font(NTFont.heading(30, .extraBold))
                            .foregroundStyle(NTColor.milk)
                            .padding(.top, 10)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            pill(route.difficulty.rawValue, filled: route.difficulty.color)
                            pill(detail.season, filled: nil)
                            pill(detail.duration, filled: nil)
                        }
                        .padding(.top, 14)

                        if !routeHazards.hazards.isEmpty {
                            Button { showFullMap = true } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                    Text("\(routeHazards.hazards.count) hazard(s) reported on this route")
                                        .font(NTFont.body(13, .semibold))
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 12)
                                .background(NTColor.hard.opacity(0.9), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 14)
                        }

                        authorRow.padding(.top, 16)

                        engagementRow.padding(.top, 16)

                        HStack(spacing: 0) {
                            statBlock(String(format: "%.1f", route.distanceKM), "KM TOTAL")
                            statBlock("+\(detail.ascentM)", "M ASCENT")
                            statBlock("\(detail.highPointM)", "M HIGH PT")
                        }
                        .padding(.vertical, 16)
                        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .top)
                        .overlay(Rectangle().fill(NTColor.milk(0.14)).frame(height: 1), alignment: .bottom)
                        .padding(.top, 22)

                        requirementsCard.padding(.top, 22)

                        elevationSection.padding(.top, 26)

                        quoteCard.padding(.top, 26)

                        itineraryPanel.padding(.top, 26)

                        RoutePhotosSection(routeId: route.id, currentUserId: currentUserId, isOwner: isOwner)
                            .padding(.top, 26)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 26)
                    .padding(.bottom, 24)
                    .background(
                        UnevenRoundedRectangle(topLeadingRadius: 34, topTrailingRadius: 34)
                            .fill(NTColor.pine)
                    )
                    .offset(y: -34)
                }
            }
            .background(NTColor.pine)

            bottomBar
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if let downloadToast {
                Text(LocalizedStringKey(downloadToast))
                    .font(NTFont.body(13, .semibold))
                    .foregroundStyle(NTColor.pine)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(NTColor.milk, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                    .padding(.horizontal, 30)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            RouteFullMapView(route: route, onClose: { showFullMap = false })
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false })
        }
        .fullScreenCover(isPresented: $showAuthorProfile) {
            AuthorProfileView(userId: route.author.id, onClose: { showAuthorProfile = false })
        }
        .fullScreenCover(isPresented: $showComments, onDismiss: {
            Task { commentCount = (try? await RouteRepository.shared.fetchComments(routeId: route.id).count) ?? commentCount }
        }) {
            CommentsView(route: route)
        }
        .sheet(isPresented: $showEditExtras) {
            EditRouteExtrasView(routeId: route.id, segments: detail.segments, requirements: detail.requirements) { updated in
                route = updated
            }
        }
        .task { await routeHazards.loadAlongRoute(detail.trackPoints) }
        .task {
            savedOffline = await RouteRepository.shared.isSaved(routeId: route.id)
            cachedSnapshot = await OfflineRouteStore.shared.snapshotImage(routeId: route.id)
            liked = await RouteRepository.shared.isLiked(routeId: route.id)
            likeCount = route.likeCount
            commentCount = route.commentCount
            if let session = try? await supabase.auth.session {
                currentUserId = session.user.id.uuidString
                isOwner = session.user.id.uuidString == route.author.id
            }
        }
    }

    // MARK: Sections

    // `text` stays `String` — call sites mix fixed vocabulary
    // (`route.difficulty.rawValue`, a real translation candidate) with
    // genuine free-text route data (`detail.season`/`.duration`, never
    // translated). Wrapping in `LocalizedStringKey` here rather than typing
    // the parameter that way handles both at once: a value that matches a
    // catalog entry (the difficulty vocabulary) translates, anything else
    // just falls back to showing itself, which `Text(String)` alone could
    // never do (that overload never touches the catalog at all).
    private func pill(_ text: String, filled: Color?) -> some View {
        Text(LocalizedStringKey(text))
            .font(NTFont.mono(11, .semibold))
            .tracking(0.6)
            .foregroundStyle(filled != nil ? NTColor.milk : NTColor.milk(0.85))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(
                Capsule().fill(filled ?? .clear)
            )
            .overlay(Capsule().stroke(NTColor.milk(0.28), lineWidth: filled == nil ? 1 : 0))
    }

    private func statBlock(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(NTFont.mono(20, .semibold))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var engagementRow: some View {
        HStack(spacing: 22) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                liked.toggle()
                likeCount += liked ? 1 : -1
                let newValue = liked
                Task { try? await RouteRepository.shared.setLiked(routeId: route.id, liked: newValue) }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: liked ? "heart.fill" : "heart").font(.system(size: 17))
                        .foregroundStyle(liked ? NTColor.accent : NTColor.milk(0.8))
                    Text(formatCount(likeCount)).font(NTFont.mono(12.5, .semibold)).foregroundStyle(NTColor.milk(0.8))
                }
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showComments = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bubble.left").font(.system(size: 16)).foregroundStyle(NTColor.milk(0.8))
                    Text(formatCount(commentCount)).font(NTFont.mono(12.5, .semibold)).foregroundStyle(NTColor.milk(0.8))
                }
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up").font(.system(size: 16)).foregroundStyle(NTColor.milk(0.8))
            }
            .simultaneousGesture(TapGesture().onEnded { UIImpactFeedbackGenerator(style: .light).impactOccurred() })

            Spacer()
        }
    }

    /// Route Detail never showed who actually made the route — real name
    /// data was already sitting right there on `route.author`, just never
    /// rendered or made tappable. Real entry point into `AuthorProfileView`
    /// now, not inert text.
    private var authorRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAuthorProfile = true
        } label: {
            HStack(spacing: 10) {
                AvatarView(author: route.author, size: 34)

                VStack(alignment: .leading, spacing: 1) {
                    Text(route.author.name).font(NTFont.body(13.5, .semibold)).foregroundStyle(NTColor.milk)
                    Text("\(route.author.handle) · \(route.author.routeCount) routes")
                        .font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.5))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(NTColor.milk(0.4))
            }
        }
        .buttonStyle(.plain)
    }

    private var shareText: String {
        "Check out \"\(route.title.replacingOccurrences(of: "\n", with: " "))\" on Nomad — \(String(format: "%.1f", route.distanceKM))km in \(route.place)."
    }

    private func formatCount(_ n: Int) -> String {
        n >= 1000 ? String(format: "%.1fK", Double(n) / 1000) : "\(n)"
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color(hex: 0xA8721F))
                Text("Requirements & gear")
                    .font(NTFont.heading(17, .bold))
                    .foregroundStyle(NTColor.ink)
                Spacer()
                Text("\(detail.requirements.count) CHECKS")
                    .font(NTFont.mono(10, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(Color(hex: 0xA8721F))
            }

            VStack(spacing: 14) {
                ForEach(detail.requirements) { req in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(req.tint.opacity(0.16))
                            Image(systemName: req.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(req.tint)
                        }
                        .frame(width: 34, height: 34)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(req.title).font(NTFont.body(14, .semibold)).foregroundStyle(NTColor.ink)
                            Text(req.subtitle).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.ink.opacity(0.55))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, 16)
        }
        .padding(22)
        // milkSurface (fixed), not milk (theme-reactive) — this card's text
        // is NTColor.ink, which is also fixed dark; pairing it with the
        // reactive `milk` would go dark-on-dark once Milk theme flips it.
        .background(NTColor.milkSurface, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.gold, lineWidth: 2))
        .shadow(color: NTColor.gold.opacity(0.16), radius: 0, x: 0, y: 0)
    }

    private var elevationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("Elevation").font(NTFont.heading(18, .bold)).foregroundStyle(NTColor.milk)
                Text("SRTM 30M").font(NTFont.mono(10, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
            }
            VStack(spacing: 6) {
                ElevationChart(samples: detail.elevationProfile, peakLabel: detail.elevationPeakLabel)
                HStack {
                    Text("0 KM").font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.5))
                    Spacer()
                    Text(String(format: "%.1f", route.distanceKM)).font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.5))
                }
            }
            .padding(14)
            .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.1), lineWidth: 1))
        }
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FROM THE AUTHOR")
                .font(NTFont.mono(10, .medium))
                .tracking(0.9)
                .foregroundStyle(NTColor.milk(0.5))
            Text(detail.quote)
                .font(NTFont.body(17, .light))
                .foregroundStyle(NTColor.milk(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Text(detail.quoteAuthor)
                .font(NTFont.mono(11, .medium))
                .tracking(0.5)
                .foregroundStyle(NTColor.milk(0.55))
        }
        .padding(20)
        .background(NTColor.milk(0.06))
        .overlay(Rectangle().fill(NTColor.sage).frame(width: 2), alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private var itineraryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                if isOwner {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showEditExtras = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                            .font(NTFont.body(12.5, .semibold))
                            .foregroundStyle(NTColor.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            RouteItineraryPanel(
                stretches: segmentStretches.isEmpty ? fallbackStretches : segmentStretches,
                isPro: subscription.isPro,
                onSelect: { stretch in focusMap(on: stretch) },
                onUnlockTapped: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showPaywall = true
                }
            )
        }
    }

    /// Routes with no real recorded track (a single reference point, or
    /// mock data predating live recording) have segments but no polyline
    /// to split — the itinerary panel still needs *something* to show, so
    /// each segment becomes its own zero-length "stretch" centered on the
    /// route's one known point rather than the panel just being empty.
    private var fallbackStretches: [MapSegmentStretch] {
        guard let anchor = detail.trackPoints.first?.coordinate else { return [] }
        return detail.segments.enumerated().map { i, seg in
            MapSegmentStretch(
                id: "fallback-\(i)", coordinates: [anchor], tint: seg.tint, icon: seg.icon, label: seg.name,
                midpoint: anchor, transport: seg.transport, distanceKM: seg.distanceKM
            )
        }
    }

    private func focusMap(on stretch: MapSegmentStretch) {
        let target = Viewport.fitting(stretch.coordinates, padding: EdgeInsets(top: 60, leading: 40, bottom: 60, trailing: 40))
        withViewportAnimation(.easeInOut(duration: 0.7)) { mapViewport = target }
    }

    private func toggleOffline() {
        if savedOffline {
            withAnimation(NTMotion.spring) { savedOffline = false }
            Task {
                await OfflineRouteStore.shared.remove(routeId: route.id)
                await OfflineMapStore.shared.remove(routeId: route.id)
                try? await RouteRepository.shared.setSaved(routeId: route.id, saved: false, downloadedOffline: false)
            }
            return
        }
        // Real offline map TILES (not just this route's own data) are Pro —
        // without them, "Save offline" used to leave the live map needing
        // real network the moment signal actually dropped, exactly the fake
        // offline this replaces. `OfflineRouteStore` (route data + a static
        // preview) still runs for everyone below; Pro adds the genuinely
        // working interactive map + navigation tiles via `OfflineMapStore`.
        guard subscription.isPro else {
            showPaywall = true
            return
        }
        isDownloading = true
        downloadProgress = 0
        Task {
            do {
                let downloaded = try await OfflineRouteStore.shared.download(routeId: route.id, wifiOnly: AppPreferences.wifiOnlyDownloads)
                cachedSnapshot = await OfflineRouteStore.shared.snapshotImage(routeId: route.id)
                let coordinates = downloaded.detail.trackPoints.map(\.coordinate) + downloaded.detail.pois.map(\.coordinate)
                try await OfflineMapStore.shared.download(routeId: route.id, coordinates: coordinates) { fraction in
                    Task { @MainActor in downloadProgress = fraction }
                }
                try await RouteRepository.shared.setSaved(routeId: route.id, saved: true, downloadedOffline: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(NTMotion.spring) { savedOffline = true }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showDownloadToast((error as? OfflineDownloadError)?.errorDescription ?? "Couldn't save offline — try again.")
            }
            isDownloading = false
        }
    }

    /// A real percentage during download, not a bare spinner — split into
    /// a localized phrase plus a plain-digit number, same pattern used
    /// everywhere else in this app a localized string wraps a live number
    /// (e.g. `SavedView.savedTile`'s distance): the number itself doesn't
    /// need translating, only "Downloading" does.
    private var downloadButtonLabel: Text {
        if isDownloading {
            return Text("Downloading…") + Text(" \(Int(downloadProgress * 100))%")
        }
        if savedOffline {
            return Text("Saved offline")
        }
        if !subscription.isPro {
            return Text("Save offline") + Text(" · PRO")
        }
        return Text("Save offline")
    }

    private func showDownloadToast(_ text: String) {
        withAnimation { downloadToast = text }
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            withAnimation { downloadToast = nil }
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                toggleOffline()
            } label: {
                HStack(spacing: 9) {
                    if isDownloading {
                        ProgressView().tint(Color(hex: 0x231007))
                    } else if !savedOffline && !subscription.isPro {
                        Image(systemName: "crown.fill").font(.system(size: 14))
                    } else {
                        Image(systemName: savedOffline ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 17))
                    }
                    downloadButtonLabel
                        .font(NTFont.body(15, .semibold))
                }
                .foregroundStyle(Color(hex: 0x231007))
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(NTColor.accent, in: Capsule())
                .shadow(color: NTColor.accent.opacity(0.5), radius: 14, y: 8)
            }
            .buttonStyle(.plain)
            .ntPressable()
            .disabled(isDownloading)

            Button(action: onNavigate) {
                HStack(spacing: 9) {
                    Image(systemName: "location.north.line.fill").font(.system(size: 15))
                    Text("Navigate").font(NTFont.body(15, .semibold))
                }
                .foregroundStyle(NTColor.milk)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .overlay(Capsule().stroke(NTColor.milk(0.5), lineWidth: 1.6))
            }
            .buttonStyle(.plain)
            .ntPressable()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(NTColor.pine)
    }
}

#Preview {
    RouteDetailView(route: Route.mock[0], onNavigate: {})
}

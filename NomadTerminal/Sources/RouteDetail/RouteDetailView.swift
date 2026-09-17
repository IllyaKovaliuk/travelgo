import SwiftUI

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
    @State private var cachedSnapshot: UIImage?
    @State private var showFullMap = false
    @State private var showEditExtras = false
    /// Real ownership check (real session's user id vs. this route's real
    /// author id) — the Edit entry point below only shows for the actual
    /// author, not decided by anything client-fakeable.
    @State private var isOwner = false
    // Route Detail had zero way to like or open comments — only the Home
    // feed card did. Same real actions, same real counts, just reachable
    // from the screen people actually read the route on.
    @State private var liked = false
    @State private var likeCount = 0
    @State private var commentCount = 0
    @State private var showComments = false
    @State private var downloadToast: String?

    private var detail: RouteDetailInfo { route.detail }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    RouteMapHeader(
                        segments: detail.segments, trackPoints: detail.trackPoints, pois: detail.pois,
                        cachedSnapshot: cachedSnapshot, onBack: { dismiss() },
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

                        segmentsSection.padding(.top, 26)
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
                Text(downloadToast)
                    .font(NTFont.body(13, .semibold))
                    .foregroundStyle(NTColor.pine)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .background(NTColor.milk, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 30)
                    .padding(.bottom, 90)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showFullMap) {
            RouteFullMapView(route: route, onClose: { showFullMap = false })
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
        .task {
            savedOffline = await RouteRepository.shared.isSaved(routeId: route.id)
            cachedSnapshot = await OfflineRouteStore.shared.snapshotImage(routeId: route.id)
            liked = await RouteRepository.shared.isLiked(routeId: route.id)
            likeCount = route.likeCount
            commentCount = route.commentCount
            if let session = try? await supabase.auth.session {
                isOwner = session.user.id.uuidString == route.author.id
            }
        }
    }

    // MARK: Sections

    private func pill(_ text: String, filled: Color?) -> some View {
        Text(text)
            .font(NTFont.mono(11, .semibold))
            .tracking(0.6)
            .foregroundStyle(filled != nil ? NTColor.milk : NTColor.milk(0.85))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(
                Capsule().fill(filled ?? .clear)
            )
            .overlay(Capsule().stroke(NTColor.milk(0.28), lineWidth: filled == nil ? 1 : 0))
    }

    private func statBlock(_ value: String, _ label: String) -> some View {
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

    private var shareText: String {
        "Check out \"\(route.title.replacingOccurrences(of: "\n", with: " "))\" on NomadTerminal — \(String(format: "%.1f", route.distanceKM))km in \(route.place)."
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
        .background(NTColor.milkSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(NTColor.gold, lineWidth: 2))
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
            .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NTColor.milk(0.1), lineWidth: 1))
        }
    }

    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FROM THE AUTHOR")
                .font(NTFont.mono(10, .medium))
                .tracking(0.9)
                .foregroundStyle(NTColor.milk(0.5))
            Text(detail.quote)
                .font(NTFont.quote(18))
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
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Segments").font(NTFont.heading(18, .bold)).foregroundStyle(NTColor.milk)
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
            .padding(.bottom, 10)
            ForEach(Array(detail.segments.enumerated()), id: \.offset) { i, seg in
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(seg.tint.opacity(0.2))
                        Image(systemName: seg.icon).font(.system(size: 14)).foregroundStyle(seg.tint)
                    }
                    .frame(width: 30, height: 30)
                    Text(seg.name).font(NTFont.body(14.5, .medium)).foregroundStyle(NTColor.milk)
                    Spacer()
                    Text(String(format: "%.1f KM", seg.distanceKM))
                        .font(NTFont.mono(12.5, .semibold))
                        .foregroundStyle(NTColor.milk(0.7))
                }
                .padding(.vertical, 14)
                .overlay(
                    Rectangle().fill(NTColor.milk(0.12)).frame(height: 1),
                    alignment: .bottom
                )
                .opacity(i == detail.segments.count - 1 ? 1 : 1)
            }
        }
    }

    private func toggleOffline() {
        if savedOffline {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { savedOffline = false }
            Task {
                await OfflineRouteStore.shared.remove(routeId: route.id)
                try? await RouteRepository.shared.setSaved(routeId: route.id, saved: false, downloadedOffline: false)
            }
            return
        }
        isDownloading = true
        Task {
            do {
                _ = try await OfflineRouteStore.shared.download(routeId: route.id, wifiOnly: AppPreferences.wifiOnlyDownloads)
                cachedSnapshot = await OfflineRouteStore.shared.snapshotImage(routeId: route.id)
                try await RouteRepository.shared.setSaved(routeId: route.id, saved: true, downloadedOffline: true)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { savedOffline = true }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                showDownloadToast((error as? OfflineDownloadError)?.errorDescription ?? "Couldn't save offline — try again.")
            }
            isDownloading = false
        }
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
                    } else {
                        Image(systemName: savedOffline ? "checkmark.circle.fill" : "arrow.down.circle")
                            .font(.system(size: 17))
                    }
                    Text(isDownloading ? "Downloading…" : (savedOffline ? "Saved offline" : "Save offline"))
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

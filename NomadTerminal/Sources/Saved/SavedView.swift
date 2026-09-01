import SwiftUI

/// 09 · Saved / offline — reads real saves back from Supabase; this is
/// where the Save button on the Feed and Route Detail actually lands.
struct SavedView: View {
    enum Lib: String { case saved = "Saved", downloaded = "Downloaded" }
    @State private var lib: Lib = .saved
    @State private var saves: [RouteRepository.SavedRoute] = []
    @State private var isLoading = true
    @State private var openRoute: Route?

    private var downloadedSaves: [RouteRepository.SavedRoute] { saves.filter(\.downloadedOffline) }

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Your library")
                        .font(NTFont.heading(30, .extraBold))
                        .foregroundStyle(NTColor.milk)

                    HStack(spacing: 4) {
                        libTab(.saved, count: saves.count)
                        libTab(.downloaded, count: downloadedSaves.count)
                    }
                    .padding(5)
                    .background(Capsule().fill(NTColor.milk(0.08)))
                    .padding(.top, 20)

                    if lib == .saved {
                        if saves.isEmpty && !isLoading {
                            emptyState(
                                title: "Nothing saved yet",
                                body: "Save a route from the feed or a route page — it lands here.",
                                buttonTitle: nil
                            )
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                                ForEach(saves, id: \.route.id) { item in
                                    savedTile(item: item)
                                        .onTapGesture { openRoute = item.route }
                                }
                            }
                            .padding(.top, 22)
                        }
                    } else {
                        if downloadedSaves.isEmpty {
                            emptyState(
                                title: "Nothing downloaded yet",
                                body: "Pull a route down before you leave signal. Tiles, elevation and gear lists come with it.",
                                buttonTitle: "Browse saved routes"
                            )
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                                ForEach(downloadedSaves, id: \.route.id) { item in
                                    savedTile(item: item)
                                        .onTapGesture { openRoute = item.route }
                                }
                            }
                            .padding(.top, 22)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
                .padding(.bottom, 100)
            }
        }
        .foregroundStyle(NTColor.milk)
        .fullScreenCover(item: $openRoute) { route in
            RouteDetailFlow(route: route)
        }
        .task { await load() }
    }

    private func load() async {
        do {
            saves = try await RouteRepository.shared.fetchSavedRoutes()
        } catch {
            // No connectivity (or the request otherwise failed) — fall back
            // to whatever's actually on disk so "Downloaded" still works
            // with zero signal, which is the entire point of the feature.
            let offline = await OfflineRouteStore.shared.allDownloadedRoutes()
            saves = offline.map { .init(route: $0, downloadedOffline: true) }
        }
        withAnimation { isLoading = false }
    }

    private func libTab(_ l: Lib, count: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { lib = l }
        } label: {
            Text("\(l.rawValue) · \(count)")
                .font(NTFont.body(13.5, .semibold))
                .foregroundStyle(lib == l ? NTColor.pine : NTColor.milk(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(lib == l ? NTColor.milk : .clear))
        }
        .buttonStyle(.plain)
    }

    private func savedTile(item: RouteRepository.SavedRoute) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RouteCoverImage(url: item.route.coverImageUrl, tint: NTColor.pineRaised)
                    .frame(height: 132)
                    .clipped()
                Image(systemName: item.downloadedOffline ? "checkmark" : "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                    .background(Circle().fill(NTColor.pineDeep.opacity(0.5)))
                    .foregroundStyle(item.downloadedOffline ? NTColor.sage : NTColor.milk(0.7))
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(item.route.title.replacingOccurrences(of: "\n", with: " "))
                    .font(NTFont.heading(15, .bold))
                    .lineLimit(2)
                Text("\(String(format: "%.1f", item.route.distanceKM)) KM · \(item.route.difficulty.rawValue)")
                    .font(NTFont.mono(10, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
            }
            .padding(14)
        }
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func emptyState(title: String, body: String, buttonTitle: String?) -> some View {
        VStack(spacing: 22) {
            ZStack {
                OrganicBlob((0.56, 0.44, 0.48, 0.52), (0.5, 0.56, 0.44, 0.5))
                    .fill(NTColor.pineRaised)
                    .frame(width: 200, height: 180)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(NTColor.milk(0.7))
            }
            VStack(spacing: 10) {
                Text(title).font(NTFont.heading(21, .bold))
                Text(body)
                    .font(NTFont.body(13.5, .light))
                    .foregroundStyle(NTColor.milk(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 250)
            }
            if let buttonTitle {
                Button { withAnimation { lib = .saved } } label: {
                    Text(buttonTitle)
                        .font(NTFont.body(14.5, .semibold))
                        .foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 26)
                        .frame(height: 54)
                        .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain).ntPressable()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    SavedView()
}

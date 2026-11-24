import SwiftUI

/// Crews tab — the groups I belong to. Reads come from RLS-scoped selects;
/// creating / joining / leaving are server RPCs (see `CrewRepository`).
struct CrewsView: View {
    @State private var items: [CrewListItem] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showCreate = false
    @State private var openCrew: CrewListItem?
    @State private var adHocTrips: [Expedition] = []
    @State private var showNewTrip = false
    @State private var openTrip: Expedition?

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading && items.isEmpty {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 60)
                    } else if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            Button { openCrew = item } label: { crewCard(item) }
                                .buttonStyle(NTCardPressStyle())
                        }
                    }

                    if !adHocTrips.isEmpty {
                        Text("MY TRIPS")
                            .font(NTFont.mono(11, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.55))
                            .padding(.top, 8)
                        ForEach(adHocTrips) { trip in
                            Button { openTrip = trip } label: { tripCard(trip) }
                                .buttonStyle(NTCardPressStyle())
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 70)
                .padding(.bottom, 110)
            }
            .refreshable { await load() }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: $showCreate) {
            CreateCrewView { newId in
                Task {
                    await load()
                    openCrew = items.first { $0.id == newId }
                }
            }
        }
        .sheet(isPresented: $showNewTrip) {
            CreateExpeditionView(crewId: nil) { id in
                Task {
                    await load()
                    openTrip = adHocTrips.first { $0.id == id }
                }
            }
        }
        .ntFullScreenCover(item: $openCrew, onDismiss: { Task { await load() } }) { item in
            CrewDetailView(crewId: item.crew.id, onClose: { openCrew = nil })
        }
        .ntFullScreenCover(item: $openTrip, onDismiss: { Task { await load() } }) { trip in
            ExpeditionDetailView(expeditionId: trip.id, onClose: { openTrip = nil })
        }
    }

    private var header: some View {
        HStack {
            Text("Crews")
                .font(NTFont.heading(30, .extraBold))
            Spacer()
            Menu {
                Button { showCreate = true } label: { Label("New crew", systemImage: "person.3") }
                Button { showNewTrip = true } label: { Label("New trip", systemImage: "map") }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .accessibilityLabel("Create")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 34))
                .foregroundStyle(NTColor.milk(0.3))
            Text(loadFailed ? "Couldn't load your crews" : "Travel better together")
                .font(NTFont.heading(20, .bold))
            Text(loadFailed
                 ? "Check your connection and pull to refresh."
                 : "A crew is a private group of friends you plan trips with. Start one and invite your people.")
                .font(NTFont.body(14, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
            if !loadFailed {
                NTAccentButton(title: "Create a crew", icon: "plus") { showCreate = true }
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    private func crewCard(_ item: CrewListItem) -> some View {
        HStack(spacing: 14) {
            RouteCoverImage(url: item.crew.coverImageUrl, tint: NTColor.pineRaised)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(item.crew.name)
                    .font(NTFont.heading(17, .bold))
                    .lineLimit(1)
                Text("\(item.memberCount) members · \(roleTitle(item.myRole))")
                    .font(NTFont.mono(10.5, .medium)).tracking(0.3)
                    .foregroundStyle(NTColor.milk(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NTColor.milk(0.35))
        }
        .padding(14)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.1), lineWidth: 1))
    }

    private func tripCard(_ trip: Expedition) -> some View {
        HStack(spacing: 14) {
            Image(systemName: trip.tripType.icon)
                .font(.system(size: 18))
                .frame(width: 48, height: 48)
                .background(Circle().fill(NTColor.milk(0.08)))
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(NTFont.heading(16, .bold)).lineLimit(1)
                Text(trip.tripType.title)
                    .font(NTFont.mono(10.5, .medium)).tracking(0.3).foregroundStyle(NTColor.milk(0.55))
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(NTColor.milk(0.35))
        }
        .padding(14)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.1), lineWidth: 1))
    }

    private func load() async {
        do {
            items = try await CrewRepository.shared.fetchMyCrews()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        // Trips that belong to a crew are listed on that crew; only ad-hoc ones here.
        adHocTrips = ((try? await CrewRepository.shared.fetchMyExpeditions()) ?? []).filter { $0.crewId == nil }
        isLoading = false
    }
}

func roleTitle(_ role: CrewRole) -> String {
    switch role {
    case .owner: return String(localized: "Owner")
    case .organizer: return String(localized: "Organizer")
    case .member: return String(localized: "Member")
    }
}

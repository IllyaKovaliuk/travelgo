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
    @State private var showJoinCode = false
    @State private var rosters: [UUID: [CrewMember]] = [:]
    @State private var trips: [UUID: [Expedition]] = [:]

    private var tripsAhead: Int {
        trips.values.flatMap { $0 }.filter { !$0.isPast }.count + adHocTrips.filter { !$0.isPast }.count
    }

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
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
                .padding(.horizontal, 16)
                .padding(.top, 58)
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
        .sheet(isPresented: $showJoinCode) {
            JoinCodeSheet { code in
                PendingImportCoordinator.shared.pendingInviteSource = "code"
                PendingImportCoordinator.shared.pendingInviteCode = code
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
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text(items.isEmpty
                     ? "NO CREWS YET"
                     : "\(items.count) CREWS · \(tripsAhead) TRIPS AHEAD")
                    .font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.55))
                Text("Crews").font(NTFont.heading(36, .extraBold)).tracking(-0.9)
            }
            Spacer()
            Menu {
                Button { showCreate = true } label: { Label("New crew", systemImage: "person.3") }
                Button { showNewTrip = true } label: { Label("New trip", systemImage: "map") }
                Button { showJoinCode = true } label: { Label("Join with a code", systemImage: "link") }
            } label: {
                CircleIconButton(icon: "plus", label: "Create", filled: true) {}.glyph
            }
            .accessibilityLabel("Create")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                ContourLines(seed: 3).stroke(NTColor.milk(0.1), lineWidth: 1)
                CompassMark(size: 54)
            }
            .frame(height: 170)
            .padding(.top, 20)
            Text(loadFailed ? "Couldn't load your crews" : "Nobody climbs\nalone out here.")
                .font(NTFont.heading(28, .extraBold)).tracking(-0.7).multilineTextAlignment(.center)
            Text(loadFailed
                 ? "Check your connection and pull to refresh."
                 : "A crew is a private circle for planning trips with your people. Shared routes, shared plan, offline for everyone.")
                .font(NTFont.body(15, .light))
                .foregroundStyle(NTColor.milk(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 6)
            if !loadFailed {
                NTAccentButton(title: "Create crew", icon: "plus") { showCreate = true }
                    .padding(.top, 8)
                HStack(spacing: 4) {
                    Text("Have an invite code?").foregroundStyle(NTColor.milk(0.8))
                    Button("Join a crew") { showJoinCode = true }.foregroundStyle(NTColor.accent)
                }
                .font(NTFont.body(14, .medium))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func crewCard(_ item: CrewListItem) -> some View {
        let roster = rosters[item.id] ?? []
        let next = (trips[item.id] ?? []).first { !$0.isPast }
        return VStack(spacing: 0) {
            CrewCover(id: item.crew.id, url: item.crew.coverImageUrl)
                .frame(height: 112)
                .overlay(alignment: .topTrailing) {
                    StatusChip(text: String(localized: "Private"), icon: nil, filled: true).padding(12)
                }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(item.crew.name).font(NTFont.heading(21, .bold)).tracking(-0.5).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(NTColor.milk(0.55))
                }
                HStack(spacing: 10) {
                    AvatarStack(people: roster.map(\.person), total: item.memberCount, size: 28)
                    Text("\(item.memberCount) members").font(NTFont.body(13)).foregroundStyle(NTColor.milk(0.6))
                }
                if let next {
                    Rectangle().fill(NTColor.pineLine).frame(height: 1)
                    HStack(spacing: 12) {
                        DateTile(date: next.startDate)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(next.name).font(NTFont.body(14, .medium)).lineLimit(1)
                            Text(nextMeta(next)).font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.55)).lineLimit(1)
                        }
                        Spacer()
                        Circle().fill(tripColor(next.tripType)).frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        }
        .crewCard()
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func nextMeta(_ e: Expedition) -> String {
        var parts: [String] = []
        if let d = e.dayCount { parts.append("\(d) DAYS") }
        if let s = e.startDate {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: s).day ?? 0
            parts.append(days > 0 ? "IN \(days) DAYS" : days == 0 ? "TODAY" : e.tripType.title.uppercased())
        } else { parts.append(e.tripType.title.uppercased()) }
        return parts.joined(separator: " · ")
    }

    private func tripColor(_ t: TripType) -> Color {
        switch t {
        case .hiking: return NTColor.sage
        case .roadTrip: return NTColor.water
        case .camping: return NTColor.gold
        case .city: return NTColor.milk(0.6)
        case .ski: return NTColor.extreme
        }
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
        .crewCard()
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
        await loadPreviews()
    }
}

extension CrewsView {
    /// Avatars and the next trip for each card; cards render without them first.
    fileprivate func loadPreviews() async {
        for item in items {
            async let m = try? CrewRepository.shared.fetchCrewMembers(crewId: item.id)
            async let x = try? CrewRepository.shared.fetchCrewExpeditions(crewId: item.id)
            let (members, expeditions) = await (m, x)
            if let members { rosters[item.id] = members }
            if let expeditions { trips[item.id] = expeditions.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) } }
        }
    }
}

func roleTitle(_ role: CrewRole) -> String {
    switch role {
    case .owner: return String(localized: "Owner")
    case .organizer: return String(localized: "Organizer")
    case .member: return String(localized: "Member")
    }
}

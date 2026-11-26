import SwiftUI

/// Expeditions tab — every trip I'm on, from my crews and ad hoc ones,
/// split into Upcoming / Past. Tapping opens the same trip screen as inside a crew.
struct ExpeditionsView: View {
    enum Segment: Hashable { case upcoming, past }

    @State private var trips: [Expedition] = []
    @State private var crewNames: [UUID: String] = [:]
    @State private var segment: Segment = .upcoming
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var showNewTrip = false
    @State private var openTrip: Expedition?

    private var upcoming: [Expedition] {
        trips.filter { !$0.isPast }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
    private var past: [Expedition] {
        trips.filter(\.isPast).sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(upcoming.count) AHEAD · \(past.count) DONE")
                                .font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.55))
                            Text("Expeditions").font(NTFont.heading(36, .extraBold)).tracking(-0.9)
                                .lineLimit(1).minimumScaleFactor(0.7)
                        }
                        Spacer()
                        Button { showNewTrip = true } label: {
                            CircleIconButton(icon: "plus", label: "New trip", filled: true) {}.glyph
                        }
                        .accessibilityLabel("New trip")
                    }

                    CrewSegments(items: [
                        (Segment.upcoming, String(localized: "Upcoming") + (upcoming.isEmpty ? "" : " · \(upcoming.count)")),
                        (Segment.past, String(localized: "Past")),
                    ], selection: $segment)

                    content
                }
                .padding(.horizontal, 16).padding(.top, 58).padding(.bottom, 110)
            }
            .refreshable { await load() }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: $showNewTrip) {
            CreateExpeditionView(crewId: nil) { id in
                Task {
                    await load()
                    openTrip = trips.first { $0.id == id }
                }
            }
        }
        .ntFullScreenCover(item: $openTrip, onDismiss: { Task { await load() } }) { trip in
            ExpeditionDetailView(expeditionId: trip.id, onClose: { openTrip = nil })
        }
    }

    @ViewBuilder private var content: some View {
        let list = segment == .upcoming ? upcoming : past
        if isLoading && trips.isEmpty {
            ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 50)
        } else if list.isEmpty {
            VStack(spacing: 10) {
                Text(loadFailed ? "Couldn't load your trips"
                     : segment == .upcoming ? "No trips planned yet" : "No past trips")
                    .font(NTFont.heading(20, .bold))
                Text(loadFailed ? "Check your connection and pull to refresh."
                     : segment == .upcoming ? "Start an expedition and your crew can build the plan together."
                     : "Finished expeditions land here.")
                    .font(NTFont.body(14, .light)).foregroundStyle(NTColor.milk(0.6)).multilineTextAlignment(.center)
                if segment == .upcoming && !loadFailed {
                    NTAccentButton(title: "New expedition", icon: "plus") { showNewTrip = true }.padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        } else {
            VStack(spacing: 12) {
                ForEach(list) { trip in
                    Button { openTrip = trip } label: { card(trip) }.buttonStyle(NTCardPressStyle())
                }
            }
        }
    }

    private func card(_ e: Expedition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(e.shortRange + (e.dayCount.map { " · \($0) DAYS" } ?? ""))
                    .font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.55))
                Spacer()
                switch e.status {
                case .planning: StatusChip(text: String(localized: "Planning"), color: NTColor.gold)
                case .active: StatusChip(text: String(localized: "Active"), color: NTColor.sage)
                case .completed: StatusChip(text: String(localized: "Done"), color: NTColor.milk(0.6))
                case .cancelled: StatusChip(text: String(localized: "Cancelled"), color: NTColor.hard)
                }
            }
            Text(e.name).font(NTFont.heading(21, .bold)).tracking(-0.4).multilineTextAlignment(.leading).lineLimit(2)
            HStack(spacing: 6) {
                Image(systemName: e.tripType.icon).font(.system(size: 12))
                Text(e.tripType.title).font(NTFont.body(13.5))
                if let crewId = e.crewId, let name = crewNames[crewId] {
                    Text("·"); Text(name).lineLimit(1)
                }
            }
            .foregroundStyle(NTColor.milk(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .crewCard()
    }

    private func load() async {
        do {
            trips = try await CrewRepository.shared.fetchMyExpeditions()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        if let crews = try? await CrewRepository.shared.fetchMyCrews() {
            crewNames = Dictionary(uniqueKeysWithValues: crews.map { ($0.id, $0.crew.name) })
        }
        isLoading = false
    }
}

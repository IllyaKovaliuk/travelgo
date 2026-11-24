import SwiftUI

/// One trip: Overview / Itinerary / Members. Itinerary is grouped by day;
/// routes come from Nomad's own routes, stops are free-form. All changes are
/// RPCs; Report and Block are on the trip and on each member (Guideline 1.2).
struct ExpeditionDetailView: View {
    let expeditionId: UUID
    var onClose: () -> Void

    enum Tab: String, CaseIterable { case overview = "Overview", itinerary = "Itinerary", members = "Members" }

    @State private var expedition: Expedition?
    @State private var itinerary = ExpeditionItinerary(routes: [], stops: [])
    @State private var members: [ExpeditionMember] = []
    @State private var myId: UUID?
    @State private var crewRole: CrewRole?
    @State private var tab: Tab = .overview
    @State private var isLoading = true

    @State private var showEdit = false
    @State private var showAddRoute = false
    @State private var showAddStop = false
    @State private var showDeleteConfirm = false
    @State private var showLeaveConfirm = false
    @State private var showReport = false
    @State private var reported = false
    @State private var reportUser: CrewPerson?
    @State private var blockUser: CrewPerson?
    @State private var openRoute: Route?
    @State private var errorMessage: String?

    private var isOrganizer: Bool { expedition?.organizerId == myId }
    private var canManage: Bool { isOrganizer || (crewRole?.isManager ?? false) }

    /// Days offered for scheduling: the trip's own length, or what's already used.
    private var dayOptions: [Int] {
        var count = 0
        if let s = expedition?.startDate, let e = expedition?.endDate {
            count = (Calendar(identifier: .gregorian).dateComponents([.day], from: s, to: e).day ?? 0) + 1
        }
        let used = (itinerary.routes.compactMap(\.dayIndex) + itinerary.stops.compactMap(\.dayIndex)).max() ?? 0
        return Array(1...max(1, max(count, used + 1)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if let expedition {
                        hero(expedition)
                        tabs
                        switch tab {
                        case .overview: overview(expedition)
                        case .itinerary: itineraryTab
                        case .members: membersTab
                        }
                    } else if isLoading {
                        ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.top, 120)
                    } else {
                        Text("This trip isn't available.")
                            .font(NTFont.body(14, .medium)).foregroundStyle(NTColor.milk(0.6))
                            .frame(maxWidth: .infinity).padding(.top, 120)
                    }
                }
                .padding(.horizontal, 22).padding(.top, 70).padding(.bottom, 60)
            }
            .refreshable { await load() }

            topBar
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: $showEdit) {
            if let expedition { CreateExpeditionView(crewId: expedition.crewId, editing: expedition) { _ in Task { await load() } } }
        }
        .sheet(isPresented: $showAddRoute) {
            AddRouteToTripSheet(expeditionId: expeditionId, alreadyAdded: Set(itinerary.routes.map(\.routeId))) { Task { await load() } }
        }
        .sheet(isPresented: $showAddStop) {
            AddStopSheet(expeditionId: expeditionId, dayOptions: dayOptions) { Task { await load() } }
        }
        .ntFullScreenCover(item: $openRoute) { route in RouteDetailFlow(route: route) }
        .alert("Delete this trip?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { run({ try await CrewRepository.shared.deleteExpedition(id: expeditionId) }, then: onClose) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("The itinerary and members' access are removed for everyone.") }
        .alert("Leave this trip?", isPresented: $showLeaveConfirm) {
            Button("Leave", role: .destructive) { run({ try await CrewRepository.shared.leaveExpedition(id: expeditionId) }, then: onClose) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Why are you reporting this trip?", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(["Spam", "Harassment", "Inappropriate content", "Other"], id: \.self) { reason in
                Button(reason) {
                    reported = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task { try? await RouteRepository.shared.report(.expedition, id: expeditionId.uuidString, reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Why are you reporting this user?",
                            isPresented: Binding(get: { reportUser != nil }, set: { if !$0 { reportUser = nil } }),
                            titleVisibility: .visible) {
            ForEach(["Spam", "Harassment", "Inappropriate content", "Other"], id: \.self) { reason in
                Button(reason) {
                    if let p = reportUser {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Task { try? await RouteRepository.shared.report(.user, id: p.id.uuidString, reason: reason) }
                    }
                    reportUser = nil
                }
            }
            Button("Cancel", role: .cancel) { reportUser = nil }
        }
        .alert("Block this user?", isPresented: Binding(get: { blockUser != nil }, set: { if !$0 { blockUser = nil } })) {
            Button("Block", role: .destructive) {
                if let p = blockUser { run { try await RouteRepository.shared.blockUser(p.id.uuidString) } }
                blockUser = nil
            }
            Button("Cancel", role: .cancel) { blockUser = nil }
        } message: {
            Text("Their routes, comments and photos will be hidden from you everywhere in Nomad. You can unblock them any time in Settings.")
        }
        .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "") }
    }

    // MARK: Header

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(NTColor.milk(0.08)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            if expedition != nil {
                Menu {
                    if canManage {
                        Button { showEdit = true } label: { Label("Edit trip", systemImage: "pencil") }
                    }
                    Button(role: .destructive) { showReport = true } label: {
                        Label(reported ? "Reported" : "Report trip", systemImage: "flag")
                    }
                    .disabled(reported)
                    if canManage {
                        Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete trip", systemImage: "trash") }
                    } else if !isOrganizer {
                        Button(role: .destructive) { showLeaveConfirm = true } label: { Label("Leave trip", systemImage: "rectangle.portrait.and.arrow.right") }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(NTColor.milk(0.08)))
                        .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 22).padding(.top, 20)
    }

    private func hero(_ e: Expedition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: e.tripType.icon)
                Text(e.tripType.title.uppercased())
            }
            .font(NTFont.mono(10.5, .semibold)).tracking(0.8).foregroundStyle(NTColor.milk(0.6))
            Text(e.name).font(NTFont.heading(28, .extraBold))
            Text(dateRange(e)).font(NTFont.mono(11, .medium)).tracking(0.3).foregroundStyle(NTColor.milk(0.55))
        }
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button { withAnimation(NTMotion.spring) { tab = t } } label: {
                    Text(LocalizedStringKey(t.rawValue))
                        .font(NTFont.body(12.5, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(tab == t ? NTColor.pine : NTColor.milk(0.7))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(tab == t ? NTColor.milk : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Capsule().fill(NTColor.milk(0.08)))
    }

    // MARK: Tabs

    private func overview(_ e: Expedition) -> some View {
        VStack(spacing: 10) {
            infoRow("Status", value: statusTitle(e.status))
            infoRow("Routes", value: "\(itinerary.routes.count)")
            infoRow("Stops", value: "\(itinerary.stops.count)")
            infoRow("People", value: "\(members.count)")
            NTAccentButton(title: "Open itinerary", icon: "list.bullet") { withAnimation(NTMotion.spring) { tab = .itinerary } }
                .padding(.top, 8)
        }
    }

    private func infoRow(_ key: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(key).font(NTFont.body(14, .medium)).foregroundStyle(NTColor.milk(0.6))
            Spacer()
            Text(value).font(NTFont.body(14, .semibold))
        }
        .padding(14)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private var itineraryTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Button { showAddRoute = true } label: { addChip("Add route", icon: "map") }.buttonStyle(.plain)
                Button { showAddStop = true } label: { addChip("Add stop", icon: "mappin.and.ellipse") }.buttonStyle(.plain)
            }
            if itinerary.routes.isEmpty && itinerary.stops.isEmpty {
                Text("Nothing planned yet. Add a route from the map or a stop like a stay or a restaurant.")
                    .font(NTFont.body(13.5, .light)).foregroundStyle(NTColor.milk(0.55))
            }
            ForEach(itinerary.days) { day in
                VStack(alignment: .leading, spacing: 8) {
                    Text(day.day.map { "DAY \($0)" } ?? String(localized: "UNSCHEDULED"))
                        .font(NTFont.mono(11, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.55))
                    ForEach(day.routes) { routeRow($0) }
                    ForEach(day.stops) { stopRow($0) }
                }
            }
        }
    }

    private func addChip(_ title: LocalizedStringKey, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold))
            Text(title).font(NTFont.body(13, .semibold))
        }
        .frame(maxWidth: .infinity).frame(height: 44)
        .background(Capsule().fill(NTColor.milk(0.1)))
        .overlay(Capsule().stroke(NTColor.milk(0.18), lineWidth: 1))
    }

    private func routeRow(_ item: ExpeditionRouteItem) -> some View {
        HStack(spacing: 12) {
            Button { open(item) } label: {
                HStack(spacing: 12) {
                    RouteCoverImage(url: item.coverImageUrl, tint: NTColor.pineRaised)
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                        Text("\(item.place) · \(String(format: "%.0f", item.distanceKm)) km")
                            .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5)).lineLimit(1)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            itemMenu(
                up: { itinerary.moveRoute(item.id, by: -1); persist() },
                down: { itinerary.moveRoute(item.id, by: 1); persist() },
                day: { itinerary.setDay(routeID: item.id, day: $0); persist() },
                remove: { run { try await CrewRepository.shared.removeRoute(itemId: item.id) } })
        }
        .padding(10)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func stopRow(_ stop: ExpeditionStop) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stop.kind.icon).font(.system(size: 16)).frame(width: 52, height: 52)
                .background(Circle().fill(NTColor.milk(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                Text(stop.notes?.isEmpty == false ? stop.notes! : stop.kind.title)
                    .font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.55)).lineLimit(2)
            }
            Spacer()
            itemMenu(
                up: { itinerary.moveStop(stop.id, by: -1); persist() },
                down: { itinerary.moveStop(stop.id, by: 1); persist() },
                day: { itinerary.setDay(stopID: stop.id, day: $0); persist() },
                remove: { run { try await CrewRepository.shared.removeStop(itemId: stop.id) } })
        }
        .padding(10)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func itemMenu(up: @escaping () -> Void, down: @escaping () -> Void,
                          day: @escaping (Int?) -> Void, remove: @escaping () -> Void) -> some View {
        Menu {
            Button(action: up) { Label("Move up", systemImage: "arrow.up") }
            Button(action: down) { Label("Move down", systemImage: "arrow.down") }
            Menu("Move to day") {
                Button("Unscheduled") { day(nil) }
                ForEach(dayOptions, id: \.self) { d in Button("Day \(d)") { day(d) } }
            }
            Button(role: .destructive, action: remove) { Label("Remove", systemImage: "trash") }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NTColor.milk(0.6)).frame(width: 32, height: 32)
        }
    }

    private var membersTab: some View {
        VStack(spacing: 8) {
            ForEach(members) { m in
                HStack(spacing: 12) {
                    PersonAvatar(person: m.person, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(m.person.displayName).font(NTFont.body(14.5, .semibold)).lineLimit(1)
                        Text("@\(m.person.username)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
                    }
                    Spacer()
                    if m.role == .organizer {
                        Text("Organizer")
                            .font(NTFont.mono(9.5, .semibold)).tracking(0.4)
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Capsule().fill(NTColor.accent.opacity(0.25)))
                    }
                    if m.person.id != myId {
                        Menu {
                            Button(role: .destructive) { reportUser = m.person } label: { Label("Report user", systemImage: "flag") }
                            Button(role: .destructive) { blockUser = m.person } label: { Label("Block user", systemImage: "hand.raised") }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NTColor.milk(0.6)).frame(width: 32, height: 32)
                        }
                    }
                }
                .padding(12)
                .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            }
        }
    }

    // MARK: Helpers

    private func statusTitle(_ s: ExpeditionStatus) -> String {
        switch s {
        case .planning: return String(localized: "Planning")
        case .active: return String(localized: "Active")
        case .completed: return String(localized: "Completed")
        case .cancelled: return String(localized: "Cancelled")
        }
    }

    private func dateRange(_ e: Expedition) -> String {
        guard let start = e.startDate else { return String(localized: "No dates yet") }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "UTC")
        if let end = e.endDate, end != start { return "\(f.string(from: start)) – \(f.string(from: end))" }
        return f.string(from: start)
    }

    private func load() async {
        myId = try? await RouteRepository.shared.ensureSession()
        async let e = try? CrewRepository.shared.fetchExpedition(id: expeditionId)
        async let i = try? CrewRepository.shared.fetchItinerary(expeditionId: expeditionId)
        async let m = try? CrewRepository.shared.fetchExpeditionMembers(expeditionId: expeditionId)
        let (exp, itin, mem) = await (e, i, m)
        expedition = exp
        itinerary = itin ?? itinerary
        members = mem ?? members
        if let crewId = exp?.crewId, let me = myId,
           let roster = try? await CrewRepository.shared.fetchCrewMembers(crewId: crewId) {
            crewRole = roster.first { $0.person.id == me }?.role
        }
        isLoading = false
    }

    private func run(_ work: @escaping () async throws -> Void, then: (() -> Void)? = nil) {
        Task {
            do {
                try await work()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if let then { then() } else { await load() }
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }

    /// Saves the local reorder; reloads from the server on failure.
    private func persist() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let snapshot = itinerary
        run({ try await CrewRepository.shared.reorder(expeditionId: expeditionId, itinerary: snapshot) }, then: {})
    }

    private func open(_ item: ExpeditionRouteItem) {
        Task {
            if let dto = try? await RouteRepository.shared.fetchRouteDTO(id: item.routeId.uuidString) {
                openRoute = dto.toRoute()
            } else {
                errorMessage = String(localized: "That route isn't available anymore.")
            }
        }
    }
}

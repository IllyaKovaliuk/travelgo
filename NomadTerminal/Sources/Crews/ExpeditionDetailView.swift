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
    @State private var addRouteDay: DayTarget?
    @State private var addStopDay: DayTarget?
    @State private var showDeleteConfirm = false
    @State private var showLeaveConfirm = false
    @State private var showReport = false
    @State private var reported = false
    @State private var reportUser: CrewPerson?
    @State private var blockUser: CrewPerson?
    @State private var openRoute: Route?
    @State private var errorMessage: String?

    struct DayTarget: Identifiable { let day: Int?; var id: Int { day ?? 0 } }

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
        ZStack(alignment: .bottom) {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    if let expedition {
                        hero(expedition)
                        CrewSegments(items: [
                            (Tab.overview, String(localized: "Overview")),
                            (Tab.itinerary, String(localized: "Itinerary")),
                            (Tab.members, String(localized: "Members") + (tab == .members ? " · \(members.count)" : "")),
                        ], selection: $tab)
                        switch tab {
                        case .overview: overview(expedition)
                        case .itinerary: itineraryTab(expedition)
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
                .padding(.horizontal, 16).padding(.top, 64).padding(.bottom, 130)
            }
            .refreshable { await load() }

            if expedition != nil, tab == .itinerary, itinerary.routes.isEmpty, itinerary.stops.isEmpty {
                VStack { NTAccentButton(title: "Add first route", icon: "plus") { addRouteDay = DayTarget(day: 1) } }
                    .padding(.horizontal, 16).padding(.bottom, 8)
            }
            VStack { topBar; Spacer() }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
        .sheet(isPresented: $showEdit) {
            if let expedition { CreateExpeditionView(crewId: expedition.crewId, editing: expedition) { _ in Task { await load() } } }
        }
        .sheet(item: $addRouteDay) { target in
            AddRouteToTripSheet(expeditionId: expeditionId, day: target.day,
                                alreadyAdded: Set(itinerary.routes.map(\.routeId))) { Task { await load() } }
        }
        .sheet(item: $addStopDay) { target in
            AddStopSheet(expeditionId: expeditionId, dayOptions: dayOptions, initialDay: target.day) { Task { await load() } }
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
            CircleIconButton(icon: "chevron.left", label: "Back", action: onClose)
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
                    CircleIconButton(icon: "ellipsis", label: "More") {}.glyph
                }
                .accessibilityLabel("More")
            }
        }
        .padding(.horizontal, 16).padding(.top, 8)
        .background(NTColor.pine.opacity(0.0))
    }

    private var totalKm: Double { itinerary.routes.reduce(0) { $0 + $1.distanceKm } }
    private var totalAscent: Int { itinerary.routes.reduce(0) { $0 + $1.ascentM } }

    private func hero(_ e: Expedition) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(e.name).font(NTFont.heading(34, .extraBold)).tracking(-0.9)
            HStack(spacing: 10) {
                Text(e.shortRange).foregroundStyle(NTColor.milk)
                if totalKm > 0 { Text(String(format: "%.1f KM", totalKm)).foregroundStyle(NTColor.milk(0.55)) }
                if totalAscent > 0 { Text("↑ \(totalAscent) M").foregroundStyle(NTColor.milk(0.55)) }
                if totalKm == 0 { Text(e.tripType.title.uppercased()).foregroundStyle(NTColor.milk(0.55)) }
                if totalKm == 0 { Text(statusTitle(e.status).uppercased()).foregroundStyle(NTColor.milk(0.55)) }
            }
            .font(NTFont.mono(11, .medium))
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    // MARK: Tabs

    private func overview(_ e: Expedition) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                statTile(value: "\(itinerary.routes.count)", label: "ROUTES")
                statTile(value: "\(itinerary.stops.count)", label: "STOPS")
                statTile(value: "\(members.count)", label: "GOING")
            }
            HStack(spacing: 12) {
                statTile(value: String(format: "%.1f", totalKm), unit: "km", label: "DISTANCE")
                statTile(value: "\(totalAscent)", unit: "m", label: "ASCENT")
            }
            NTAccentButton(title: "Open itinerary", icon: "list.bullet") { withAnimation(NTMotion.spring) { tab = .itinerary } }
                .padding(.top, 8)
        }
    }

    private func statTile(value: String, unit: String? = nil, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(NTFont.heading(26, .extraBold)).tracking(-0.5)
                if let unit { Text(unit).font(NTFont.body(13, .medium)).foregroundStyle(NTColor.milk(0.55)) }
            }
            Text(label).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .crewCard(radius: 16)
    }

    /// Days shown: the trip's own length (pre-created from the dates), anything
    /// already used, and an "unscheduled" bucket only when something is in it.
    private func itineraryTab(_ e: Expedition) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(dayOptions, id: \.self) { d in dayBlock(d, in: e) }
            if hasUnscheduled { dayBlock(nil, in: e) }
        }
    }

    private var hasUnscheduled: Bool {
        itinerary.routes.contains { $0.dayIndex == nil } || itinerary.stops.contains { $0.dayIndex == nil }
    }

    private func dayBlock(_ d: Int?, in e: Expedition) -> some View {
        let routes = itinerary.routes.filter { $0.dayIndex == d }.sorted { $0.position < $1.position }
        let stops = itinerary.stops.filter { $0.dayIndex == d }.sorted { $0.position < $1.position }
        let km = routes.reduce(0) { $0 + $1.distanceKm }
        let up = routes.reduce(0) { $0 + $1.ascentM }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(dayTitle(d, in: e)).font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.accent)
                Spacer()
                if km > 0 {
                    Text(String(format: "%.1f KM · ↑ %d M", km, up)).font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.55))
                }
            }
            .padding(.horizontal, 4)

            if routes.isEmpty && stops.isEmpty {
                Button { addRouteDay = DayTarget(day: d) } label: {
                    Text("NOTHING PLANNED · TAP TO ADD")
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(NTColor.pineLine, style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    let rows: [AnyView] = routes.map { AnyView(routeRow($0)) } + stops.map { AnyView(stopRow($0)) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                        if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                        row
                    }
                }
                .crewCard()
                HStack(spacing: 10) {
                    Button { addRouteDay = DayTarget(day: d) } label: { addChip("Route") }.buttonStyle(.plain)
                    Button { addStopDay = DayTarget(day: d) } label: { addChip("Stop") }.buttonStyle(.plain)
                }
            }
        }
    }

    private func dayTitle(_ d: Int?, in e: Expedition) -> String {
        guard let d else { return String(localized: "UNSCHEDULED") }
        var title = "DAY \(d)"
        if let start = e.startDate, let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: d - 1, to: start) {
            let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "EEE d MMM"
            title += " · " + f.string(from: date).uppercased()
        }
        return title
    }

    private func addChip(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
            Text(title).font(NTFont.body(14, .semibold))
        }
        .frame(maxWidth: .infinity).frame(height: 48)
        .background(Capsule().fill(NTColor.pine))
        .overlay(Capsule().stroke(NTColor.pineLine, lineWidth: 1))
    }

    private func routeRow(_ item: ExpeditionRouteItem) -> some View {
        HStack(spacing: 12) {
            Button { open(item) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(NTColor.sage)
                        .frame(width: 40, height: 40)
                        .background(NTColor.sage.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title.replacingOccurrences(of: "\n", with: " ")).font(NTFont.body(15, .semibold)).lineLimit(1)
                        Text(routeMeta(item)).font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    if let d = item.difficulty { StatusChip(text: d.rawValue, color: d.color) }
                }
            }
            .buttonStyle(.plain)
            itemMenu(
                up: { itinerary.moveRoute(item.id, by: -1); persist() },
                down: { itinerary.moveRoute(item.id, by: 1); persist() },
                day: { itinerary.setDay(routeID: item.id, day: $0); persist() },
                remove: { run { try await CrewRepository.shared.removeRoute(itemId: item.id) } })
        }
        .padding(.leading, 12).padding(.trailing, 2).padding(.vertical, 10)
    }

    private func routeMeta(_ item: ExpeditionRouteItem) -> String {
        var parts = [String(format: "%.1f KM", item.distanceKm)]
        if item.ascentM > 0 { parts.append("↑ \(item.ascentM) M") }
        return parts.joined(separator: " · ")
    }

    private func stopRow(_ stop: ExpeditionStop) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stop.kind.icon).font(.system(size: 15)).foregroundStyle(NTColor.milk(0.85))
                .frame(width: 40, height: 40)
                .background(NTColor.pine, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NTColor.pineLine, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(stop.title).font(NTFont.body(15, .semibold)).lineLimit(1)
                Text((stop.kind.title + (stop.notes?.isEmpty == false ? " · \(stop.notes!)" : "")).uppercased())
                    .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55)).lineLimit(1)
            }
            Spacer()
            itemMenu(
                up: { itinerary.moveStop(stop.id, by: -1); persist() },
                down: { itinerary.moveStop(stop.id, by: 1); persist() },
                day: { itinerary.setDay(stopID: stop.id, day: $0); persist() },
                remove: { run { try await CrewRepository.shared.removeStop(itemId: stop.id) } })
        }
        .padding(.leading, 12).padding(.trailing, 2).padding(.vertical, 10)
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
                .foregroundStyle(NTColor.milk(0.6)).frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
    }

    private var membersTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MonoLabel("Going · \(members.count)")
                Spacer()
                MonoLabel("Role")
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                    HStack(spacing: 12) {
                        PersonAvatar(person: m.person, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.person.displayName).font(NTFont.body(15, .semibold)).lineLimit(1)
                            Text(m.person.id == myId ? String(localized: "You") : "@\(m.person.username)")
                                .font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55)).lineLimit(1)
                        }
                        Spacer()
                        let owner = m.role == .organizer && m.person.id == expedition?.organizerId
                        Text((owner ? String(localized: "Organizer") : m.role == .organizer ? String(localized: "Organizer") : String(localized: "Member")).uppercased())
                            .font(NTFont.mono(9.5, .semibold)).tracking(0.4)
                            .foregroundStyle(m.role == .organizer ? NTColor.accent : NTColor.milk(0.6))
                            .padding(.horizontal, 9).padding(.vertical, 5)
                            .overlay(Capsule().stroke(m.role == .organizer ? NTColor.accent : NTColor.pineLine, lineWidth: 1))
                        if m.person.id != myId {
                            Menu {
                                Button(role: .destructive) { reportUser = m.person } label: { Label("Report user", systemImage: "flag") }
                                Button(role: .destructive) { blockUser = m.person } label: { Label("Block user", systemImage: "hand.raised") }
                            } label: {
                                Image(systemName: "ellipsis").font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(NTColor.milk(0.6)).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("More")
                        }
                    }
                    .padding(.leading, 12).padding(.trailing, 2).padding(.vertical, 8)
                }
            }
            .crewCard()
            Text("Organizers edit the itinerary and invite. Report or block anyone from their row.")
                .font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55)).padding(.horizontal, 4)
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

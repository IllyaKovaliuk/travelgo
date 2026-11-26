import SwiftUI
import CoreLocation

/// Opt-in screen shown before anyone's position leaves the phone: who can see it,
/// until when, and how often it updates.
struct LiveConsentSheet: View {
    let expedition: Expedition
    let people: [CrewPerson]
    /// (until, mode, lowPower)
    var onStart: (Date, String, Bool) async -> Void
    var onNotNow: () -> Void

    @State private var option: Option = .tripEnd
    @State private var lowPower = false
    @State private var isStarting = false

    enum Option { case tripEnd, recording }

    private var tripEnd: Date {
        if let end = expedition.endDate ?? expedition.startDate {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = TimeZone(identifier: "UTC") ?? .current
            let d = c.dateComponents([.year, .month, .day], from: end)
            var local = DateComponents(); local.year = d.year; local.month = d.month; local.day = d.day; local.hour = 20
            if let date = Calendar.current.date(from: local), date > Date() { return date }
        }
        return Date().addingTimeInterval(24 * 3600)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            AvatarStack(people: people, size: 40, maxShown: 5, ring: NTColor.pineElevated)
            Text("See each other on the trip").font(NTFont.heading(28, .extraBold)).tracking(-0.7)
            Text("Only the \(people.count) people going on \(expedition.name) see where you are. Nobody else in the crew, nobody outside it.")
                .font(NTFont.body(15)).foregroundStyle(NTColor.milk(0.75))

            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Share until")
                VStack(spacing: 0) {
                    radio(.tripEnd, title: "Trip ends",
                          sub: tripEnd.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()) + " · " + String(localized: "stops automatically"))
                    Rectangle().fill(NTColor.pineLine).frame(height: 1)
                    radio(.recording, title: "Only while I record", sub: "Pauses when you stop the track")
                }
                .crewCard(radius: 16)
            }

            Toggle(isOn: $lowPower) {
                HStack(spacing: 12) {
                    Image(systemName: "battery.50")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Low-power mode").font(NTFont.body(15, .semibold))
                        Text("Update every 2 min instead of 30 s").font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55))
                    }
                }
            }
            .tint(NTColor.sage).padding(14).crewCard(radius: 16)

            Text("NO SIGNAL? YOUR PHONE KEEPS TRYING AND SENDS YOUR LAST POSITION WHEN IT RECONNECTS. ONLY YOUR LATEST POSITION IS STORED, AND IT'S DELETED WHEN SHARING ENDS.")
                .font(NTFont.mono(9.5, .medium)).foregroundStyle(NTColor.milk(0.55))

            NTAccentButton(title: isStarting ? "Starting…" : "Start sharing") {
                isStarting = true
                Task {
                    await onStart(tripEnd, option == .tripEnd ? "trip_end" : "recording", lowPower)
                    isStarting = false
                }
            }
            .disabled(isStarting)
            NTGhostButton(title: "Not now", action: onNotNow).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 8)
        .background(NTColor.pineElevated.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
    }

    private func radio(_ o: Option, title: LocalizedStringKey, sub: String) -> some View {
        Button { option = o } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(option == o ? NTColor.accent : NTColor.milk(0.3), lineWidth: 2).frame(width: 24, height: 24)
                    if option == o { Circle().fill(NTColor.accent).frame(width: 12, height: 12) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NTFont.body(15.5, .semibold))
                    Text(sub).font(NTFont.body(12.5)).foregroundStyle(NTColor.milk(0.55))
                }
                Spacer()
            }
            .padding(14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Ready check before the trip starts: first leg, my car, who's ready.
struct StartLobbyView: View {
    let expedition: Expedition
    var onStarted: (Expedition) -> Void
    var onClose: () -> Void

    @State private var members: [ExpeditionMember] = []
    @State private var readiness: [UUID: Readiness] = [:]
    @State private var itinerary = ExpeditionItinerary(routes: [], stops: [])
    @State private var myId: UUID?
    @State private var leg: Leg = .convoy
    @State private var isStarting = false
    @State private var errorMessage: String?

    enum Leg: Hashable { case convoy, foot }

    private var me: ExpeditionMember? { members.first { $0.person.id == myId } }
    private var cars: [UUID] { Array(Set(members.compactMap(\.carDriverId))) }
    private var firstDayKm: Double { itinerary.routes.filter { ($0.dayIndex ?? 1) == 1 }.reduce(0) { $0 + $1.distanceKm } }
    private var readyCount: Int { members.filter { readiness[$0.person.id]?.ready == true }.count }
    private var canStart: Bool { expedition.organizerId == myId || true }  // server enforces who may start

    var body: some View {
        ZStack(alignment: .bottom) {
            NTColor.pine.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(todayLine).font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.accent)
                    Text(expedition.name).font(NTFont.heading(34, .extraBold)).tracking(-0.9)

                    MonoLabel("First leg")
                    CrewSegments(items: [
                        (Leg.convoy, String(localized: "Convoy")), (Leg.foot, String(localized: "On foot")),
                    ], selection: $leg)

                    if leg == .convoy { driveSummary; myCar }

                    HStack {
                        MonoLabel("Ready check")
                        Spacer()
                        Text("\(readyCount) OF \(members.count)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                            if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                            readyRow(m)
                        }
                    }
                    .crewCard()

                    Button { Task { await markReady(!(readiness[myId ?? UUID()]?.ready ?? false)) } } label: {
                        Label(readiness[myId ?? UUID()]?.ready == true ? "I'm not ready" : "I'm ready", systemImage: "checkmark.circle")
                            .font(NTFont.body(15, .semibold)).frame(maxWidth: .infinity).frame(height: 52)
                            .background(Capsule().fill(NTColor.pineRaised)).overlay(Capsule().stroke(NTColor.pineLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    if let errorMessage { Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright) }
                }
                .padding(.horizontal, 16).padding(.top, 64).padding(.bottom, 150)
            }
            VStack(spacing: 8) {
                NTAccentButton(title: isStarting ? "Starting…" : "Start expedition", icon: "play.fill") { start() }
                    .disabled(isStarting)
                Text("Everyone going sees it start. You choose separately whether to share your position.")
                    .font(NTFont.body(12)).foregroundStyle(NTColor.milk(0.55)).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
            VStack {
                HStack { CircleIconButton(icon: "chevron.left", label: "Back", action: onClose); Spacer() }
                    .padding(.horizontal, 16).padding(.top, 8)
                Spacer()
            }
        }
        .foregroundStyle(NTColor.milk)
        .task { await load() }
    }

    private var todayLine: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return (String(localized: "TODAY") + " · " + f.string(from: Date()).uppercased() + (expedition.dayCount.map { " · \($0) DAYS" } ?? ""))
    }

    private var driveSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(NTColor.water)
                .frame(width: 40, height: 40).background(NTColor.water.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Day 1 drive").font(NTFont.body(15, .semibold))
                Text("\(max(cars.count, 1)) CARS · \(String(format: "%.0f", firstDayKm)) KM").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
            }
            Spacer()
        }
        .padding(12).crewCard()
    }

    /// Which car I'm in: driving, or riding with someone who drives.
    private var myCar: some View {
        Menu {
            Button("I'm driving") { Task { await setCar(myId) } }
            ForEach(members.filter { $0.person.id != myId }) { m in
                Button("Riding with \(m.person.displayName)") { Task { await setCar(m.person.id) } }
            }
        } label: {
            HStack {
                Image(systemName: "car.fill")
                Text(carLabel).font(NTFont.body(15, .semibold))
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 12)).foregroundStyle(NTColor.milk(0.5))
            }
            .padding(14).crewCard(radius: 16)
        }
    }

    private var carLabel: String {
        guard let d = me?.carDriverId else { return String(localized: "Choose your car") }
        if d == myId { return String(localized: "I'm driving") }
        return String(localized: "Riding with \(members.first { $0.person.id == d }?.person.displayName ?? "—")")
    }

    private func readyRow(_ m: ExpeditionMember) -> some View {
        let r = readiness[m.person.id]
        return HStack(spacing: 12) {
            PersonAvatar(person: m.person, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.person.id == myId ? String(localized: "You") : m.person.displayName).font(NTFont.body(15, .semibold)).lineLimit(1)
                Text(r.map { "MAPS \($0.offlinePct)% · GPS \($0.gpsOn ? "ON" : "OFF")" + ($0.battery.map { " · \($0)%" } ?? "") } ?? "WAITING")
                    .font(NTFont.mono(10, .medium)).foregroundStyle(r?.ready == true ? NTColor.milk(0.55) : NTColor.gold).lineLimit(1)
            }
            Spacer()
            if r?.ready == true {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color(hex: 0x0B2716))
                    .frame(width: 28, height: 28).background(Circle().fill(NTColor.sage))
            } else {
                StatusChip(text: String(localized: "Waiting"), color: NTColor.gold)
            }
        }
        .padding(12)
    }

    // MARK: Actions

    private func load() async {
        myId = try? await RouteRepository.shared.ensureSession()
        members = (try? await CrewRepository.shared.fetchExpeditionMembers(expeditionId: expedition.id)) ?? []
        itinerary = (try? await CrewRepository.shared.fetchItinerary(expeditionId: expedition.id)) ?? itinerary
        leg = expedition.tripType == .roadTrip ? .convoy : .foot
        await reloadReadiness()
        await markReady(readiness[myId ?? UUID()]?.ready ?? false)
    }

    private func reloadReadiness() async {
        let list = (try? await CrewLiveRepository.shared.fetchReadiness(expeditionId: expedition.id)) ?? []
        readiness = Dictionary(list.map { ($0.userId, $0) }, uniquingKeysWith: { $1 })
    }

    /// Writes my own readiness: how much of the trip is saved offline, GPS state, battery.
    private func markReady(_ ready: Bool) async {
        let ids = itinerary.routes.map { $0.routeId.uuidString }
        let offline = ids.isEmpty ? 100 : Int(Double(ids.filter {
            OfflineMapStore.shared.isDownloaded(routeId: $0) && OfflineRouteStore.shared.isDownloaded(routeId: $0)
        }.count) / Double(ids.count) * 100)
        let gps = [.authorizedWhenInUse, .authorizedAlways].contains(CLLocationManager().authorizationStatus)
        UIDevice.current.isBatteryMonitoringEnabled = true
        let b = UIDevice.current.batteryLevel
        try? await CrewLiveRepository.shared.setReadiness(
            expeditionId: expedition.id, offlinePct: offline, gpsOn: gps, battery: b < 0 ? nil : Int(b * 100), ready: ready)
        await reloadReadiness()
    }

    private func setCar(_ driver: UUID?) async {
        try? await CrewLiveRepository.shared.setMyCar(expeditionId: expedition.id, driverId: driver)
        members = (try? await CrewRepository.shared.fetchExpeditionMembers(expeditionId: expedition.id)) ?? members
    }

    private func start() {
        isStarting = true; errorMessage = nil
        Task {
            do {
                try await CrewLiveRepository.shared.startExpedition(id: expedition.id, mode: leg == .convoy ? "convoy" : "foot")
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                RouteRepository.shared.logEvent("expedition_started", metadata: ["expedition_id": expedition.id.uuidString, "mode": leg == .convoy ? "convoy" : "foot"])
                if let started = try? await CrewRepository.shared.fetchExpedition(id: expedition.id) { onStarted(started) }
            } catch { errorMessage = error.localizedDescription }
            isStarting = false
        }
    }
}

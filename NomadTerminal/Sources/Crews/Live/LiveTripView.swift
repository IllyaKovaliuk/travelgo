import SwiftUI
import MapboxMaps
import CoreLocation
import MapKit

/// The live screen of a started trip: crew on the map (Trail / Road convoy), the
/// ascent profile, or a plain list, plus alert banners and the one-tap convoy status.
struct LiveTripView: View {
    let expedition: Expedition
    var onClose: () -> Void

    enum Pane: Hashable { case map, profile, list }

    private let session = LiveSession.shared
    @State private var pane: Pane = .map
    @State private var viewport: Viewport = .styleDefault
    @State private var satellite = false
    @State private var selected: UUID?
    @State private var showSOS = false
    @State private var showConsent = false
    @State private var showAlerts = false
    @State private var statusAlert: LiveAlert?
    @State private var dismissedStops: Set<String> = []
    @State private var flew = false

    private var me: UUID? { session.myId }
    private var isRoad: Bool { session.mode == .road }

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()
            if pane == .map { mapLayer } else { Color.clear }

            VStack(spacing: 10) {
                hud
                if pane == .map, let banner = currentBanner { bannerView(banner) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.top, 6)

            if pane == .map {
                HStack { Spacer(); mapControls }.padding(.trailing, 12).padding(.top, 70)
                    .frame(maxHeight: .infinity, alignment: .top)
            }

            VStack(spacing: 10) {
                Spacer()
                bottomPanel
                paneSwitch
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .foregroundStyle(NTColor.milk)
        .task {
            await session.attach(expedition)
            if !session.isSharing && !consentAsked { showConsent = true; consentAsked = true }
        }
        .onDisappear { session.detachIfIdle() }
        .ntFullScreenCover(isPresented: $showSOS, readable: false) {
            SOSView(onClose: { showSOS = false }, lastKnownCoordinate: session.myLocation?.coordinate)
        }
        .sheet(isPresented: $showConsent) {
            LiveConsentSheet(expedition: expedition, people: session.members.map(\.person)) { until, mode, low in
                do {
                    try await session.startSharing(until: until, mode: mode, lowPower: low)
                    RouteRepository.shared.logEvent("live_share_started", metadata: ["expedition_id": expedition.id.uuidString])
                } catch {}
                showConsent = false
            } onNotNow: { showConsent = false }
            .presentationDetents([.large]).presentationCornerRadius(32)
        }
        .sheet(isPresented: $showAlerts) {
            CrewAlertsView(expedition: expedition) { showAlerts = false }
                .presentationDetents([.large]).presentationCornerRadius(32)
        }
        .sheet(item: $statusAlert) { alert in
            ConvoyStatusSheet(expedition: expedition, alert: alert, session: session) { statusAlert = nil }
                .presentationDetents([.large]).presentationCornerRadius(32)
        }
        .onChange(of: session.alerts) { _, alerts in
            // my own car stopped: ask what happened, once per stop
            if let mine = alerts.first(where: { $0.kind == "convoy_stopped" && $0.subject == me }),
               !dismissedStops.contains(mine.id + "\(mine.since.timeIntervalSince1970)") {
                dismissedStops.insert(mine.id + "\(mine.since.timeIntervalSince1970)")
                statusAlert = mine
            }
        }
    }

    @State private var consentAsked = false

    // MARK: Map

    private var mapLayer: some View {
        Map(viewport: $viewport) {
            Puck2D(bearing: .heading)
            if session.routeLine.count > 1 {
                GeoJSONSource(id: "live-planned").data(.geometry(.lineString(LineString(session.routeLine))))
                LineLayer(id: "live-planned-line", source: "live-planned")
                    .lineColor(UIColor(NTColor.milk).withAlphaComponent(0.55))
                    .lineEmissiveStrength(1).lineWidth(4)
            }
            if session.myTrack.count > 1 {
                GeoJSONSource(id: "live-mine").data(.geometry(.lineString(LineString(session.myTrack))))
                LineLayer(id: "live-mine-line", source: "live-mine")
                    .lineColor(UIColor(NTColor.accent)).lineEmissiveStrength(1).lineWidth(6).lineCap(.round).lineJoin(.round)
            }
            if let r = session.regroup, let lat = r.lat, let lng = r.lng {
                MapViewAnnotation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                    MapPin(icon: "scope", tint: NTColor.gold)
                }
            }
            ForEvery(Array(session.fixes.values)) { fix in
                MapViewAnnotation(coordinate: fix.coordinate) {
                    Button { selected = fix.userId } label: { pin(for: fix) }.buttonStyle(.plain)
                }
            }
        }
        .mapStyle(NomadMap.style(satellite: satellite))
        .ignoresSafeArea()
        .task(id: session.fixes.count) {
            guard !flew, !session.fixes.isEmpty || session.myLocation != nil else { return }
            flew = true
            fitCrew()
        }
    }

    private func pin(for fix: LiveFix) -> some View {
        let person = session.person[fix.userId]
        let fresh = fix.freshness()
        let color: Color = fresh == .live ? NTColor.sage : (fresh == .stale ? NTColor.gold : NTColor.milk(0.4))
        let stopped = session.alerts.contains { $0.subject == fix.userId && ($0.kind == "convoy_stopped" || $0.kind == "help") }
        return VStack(spacing: 3) {
            ZStack {
                if let person { PersonAvatar(person: person, size: 38) } else { Circle().fill(NTColor.pineRaised).frame(width: 38, height: 38) }
                Circle().stroke(stopped ? NTColor.hardBright : color, style: StrokeStyle(lineWidth: 3, dash: fresh == .live && !stopped ? [] : [4, 3]))
                    .frame(width: 46, height: 46)
                if isRoad, let n = carNumber(for: fix.userId) {
                    Text("\(n)").font(NTFont.mono(10, .semibold)).foregroundStyle(Color(hex: 0x231007))
                        .frame(width: 18, height: 18).background(Circle().fill(NTColor.accent)).offset(x: 18, y: -18)
                }
            }
            if fresh != .live { Text(fix.ageLabel()).font(NTFont.mono(9, .semibold)).foregroundStyle(color) }
            else if let p = person, fix.userId == me { Text("YOU").font(NTFont.mono(9, .semibold)).foregroundStyle(NTColor.milk) }
            else if let p = person { Text(p.displayName.split(separator: " ").first.map { String($0).uppercased() } ?? "").font(NTFont.mono(9, .semibold)) }
        }
    }

    private func fitCrew() {
        var coords = session.fixes.values.map(\.coordinate)
        if let l = session.myLocation?.coordinate { coords.append(l) }
        guard !coords.isEmpty else { return }
        withViewportAnimation(.fly(duration: 1.2)) {
            viewport = coords.count == 1
                ? .camera(center: coords[0], zoom: 14)
                : .fitting(coords, padding: EdgeInsets(top: 160, leading: 60, bottom: 380, trailing: 60))
        }
    }

    private var mapControls: some View {
        VStack(spacing: 10) {
            control("square.3.layers.3d", label: "Map style") { satellite.toggle() }
            control("person.2.fill", label: "Fit the crew", on: true) { fitCrew() }
            control("location.fill", label: "My position") {
                if let l = session.myLocation?.coordinate { withViewportAnimation(.fly(duration: 0.8)) { viewport = .camera(center: l, zoom: 15.5) } }
            }
        }
    }

    private func control(_ icon: String, label: LocalizedStringKey, on: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(on ? NTColor.pine : NTColor.milk).frame(width: 44, height: 44)
                .background(Circle().fill(on ? NTColor.milk : NTColor.pine.opacity(0.85)))
                .overlay(Circle().stroke(NTColor.pineLine, lineWidth: 1))
        }
        .buttonStyle(.plain).accessibilityLabel(label)
    }

    // MARK: HUD + banner

    private var hud: some View {
        HStack(spacing: 10) {
            CircleIconButton(icon: "chevron.left", label: "Back", action: onClose)
            Menu {
                ForEach(AwarenessMode.allCases) { m in
                    Button { session.mode = m } label: { Label(m.title, systemImage: session.mode == m ? "checkmark" : "") }
                }
                Button { showAlerts = true } label: { Label("Crew alerts", systemImage: "bell.badge") }
                if session.isSharing {
                    Button(role: .destructive) { Task { await session.stopSharing() } } label: { Label("Stop sharing", systemImage: "location.slash") }
                } else {
                    Button { showConsent = true } label: { Label("Share my position", systemImage: "location") }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(session.isSharing ? NTColor.accent : NTColor.milk(0.4)).frame(width: 8, height: 8)
                    Text(session.mode.title.uppercased()).font(NTFont.mono(11, .semibold))
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(elapsed(ctx.date)).font(NTFont.mono(11, .medium)).foregroundStyle(NTColor.milk(0.75))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(NTColor.milk(0.5))
                }
                .padding(.horizontal, 14).frame(height: 44).frame(maxWidth: .infinity)
                .background(Capsule().fill(NTColor.pine.opacity(0.88))).overlay(Capsule().stroke(NTColor.pineLine, lineWidth: 1))
            }
            Button { showSOS = true } label: {
                Text("SOS").font(NTFont.mono(12, .semibold)).foregroundStyle(NTColor.hardBright)
                    .frame(width: 56, height: 44)
                    .background(Capsule().fill(NTColor.pine.opacity(0.88))).overlay(Capsule().stroke(NTColor.hard, lineWidth: 1.5))
            }
            .buttonStyle(.plain).accessibilityLabel("SOS")
        }
    }

    private func elapsed(_ now: Date) -> String {
        guard let s = expedition.startedAt ?? session.expedition?.startedAt else { return "" }
        let t = max(0, Int(now.timeIntervalSince(s)))
        return String(format: "%02d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
    }

    private var currentBanner: LiveAlert? {
        session.alerts.first { $0.subject != me || $0.kind == "help" }
    }

    private func bannerView(_ alert: LiveAlert) -> some View {
        let name = session.person[alert.subject]?.displayName ?? String(localized: "Someone")
        let minutes = max(1, Int(Date().timeIntervalSince(alert.since) / 60))
        let kind = AlertKind(rawValue: alert.kind)
        let title: String = {
            switch alert.kind {
            case "convoy_stopped": return String(localized: "\(carLabel(for: alert.subject)) stopped · \(minutes) min")
            case "help": return String(localized: "\(name) needs help")
            default: return "\(name) · \(kind?.bannerTitle ?? "")"
            }
        }()
        let coord = alert.lat.flatMap { lat in alert.lng.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) } }
            ?? session.fixes[alert.subject]?.coordinate
        let distance = coord.flatMap { c in session.myLocation.map { Geo.distance($0.coordinate, c) } }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: alert.kind == "help" ? "exclamationmark.triangle.fill" : "car.fill").foregroundStyle(NTColor.hardBright)
                    .frame(width: 40, height: 40).background(Circle().fill(NTColor.hard.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NTFont.heading(18, .bold)).lineLimit(2)
                    Text([name, distance.map { Geo.distanceLabel($0).lowercased() + " " + String(localized: "away") },
                          alert.status?.title].compactMap { $0 }.joined(separator: " · "))
                        .font(NTFont.body(13)).foregroundStyle(NTColor.milk(0.75)).lineLimit(2)
                }
            }
            HStack(spacing: 10) {
                if let coord {
                    Button { openDirections(to: coord, name: name) } label: {
                        Text(alert.etaMin.map { String(localized: "Turn back · \($0) min") } ?? String(localized: "Navigate to them"))
                            .font(NTFont.body(15, .semibold)).foregroundStyle(Color(hex: 0x231007))
                            .frame(maxWidth: .infinity).frame(height: 46).background(Capsule().fill(NTColor.accent))
                    }.buttonStyle(.plain)
                }
                Button { Task { await session.ping(alert.subject) } } label: {
                    Text("Ping").font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 26).frame(height: 46).background(Capsule().fill(NTColor.milk))
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color(hex: 0x2A1210)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NTColor.hard.opacity(0.6), lineWidth: 1))
    }

    private func openDirections(to c: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: isRoad ? MKLaunchOptionsDirectionsModeDriving : MKLaunchOptionsDirectionsModeWalking])
    }

    // MARK: Bottom panel

    private var paneSwitch: some View {
        CrewSegments(items: [(Pane.map, String(localized: "Map")), (Pane.profile, String(localized: "Profile")), (Pane.list, String(localized: "List"))],
                     selection: $pane)
    }

    @ViewBuilder private var bottomPanel: some View {
        switch pane {
        case .map:
            if isRoad { convoySheet } else { crewSheet }
        case .profile:
            AscentProfileView(session: session, onFocus: { selected = $0 })
        case .list:
            ScrollView(showsIndicators: false) { VStack(spacing: 8) { ForEach(sortedPeople, id: \.id) { personRow($0, detailed: true) } } }
                .frame(maxHeight: 460)
        }
        if let id = selected, let fix = session.fixes[id], let p = session.person[id] {
            Color.clear.frame(height: 0)
                .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                    LiveMemberSheet(person: p, fix: fix, session: session) { selected = nil }
                        .presentationDetents([.height(420)]).presentationCornerRadius(32)
                }
        }
    }

    private var sortedPeople: [CrewPerson] {
        session.members.map(\.person).sorted { (session.fixes[$0.id]?.recordedAt ?? .distantPast) > (session.fixes[$1.id]?.recordedAt ?? .distantPast) }
    }

    private var crewSheet: some View {
        let live = session.fixes.values.filter { $0.freshness() == .live }.count
        let lost = session.fixes.count - live
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Crew on map").font(NTFont.heading(20, .bold))
                Spacer()
                Text("\(live) LIVE" + (lost > 0 ? " · \(lost) LOST SIGNAL" : "")).font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
            }
            if session.fixes.isEmpty {
                Text("Nobody is sharing a position yet.").font(NTFont.body(13.5)).foregroundStyle(NTColor.milk(0.6))
            }
            VStack(spacing: 0) {
                ForEach(Array(sortedPeople.filter { session.fixes[$0.id] != nil }.enumerated()), id: \.element.id) { i, p in
                    if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                    personRow(p, detailed: false)
                }
            }
            HStack(spacing: 12) {
                Button { Task { await setRegroup() } } label: {
                    Label("Set regroup point", systemImage: "mappin.and.ellipse").font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.pine)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(NTColor.milk))
                }.buttonStyle(.plain)
                Button { if session.isSharing { Task { await session.stopSharing() } } else { showConsent = true } } label: {
                    Image(systemName: session.isSharing ? "location.slash" : "location").font(.system(size: 17, weight: .semibold))
                        .frame(width: 52, height: 52).background(Circle().fill(NTColor.pineRaised)).overlay(Circle().stroke(NTColor.pineLine, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel(session.isSharing ? "Stop sharing" : "Share my position")
            }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(NTColor.pineElevated))
    }

    private func setRegroup() async {
        if let l = session.myLocation?.coordinate ?? session.fixes[me ?? UUID()]?.coordinate { await session.setRegroup(at: l) }
    }

    private func personRow(_ p: CrewPerson, detailed: Bool) -> some View {
        let fix = session.fixes[p.id]
        return Button { if fix != nil { selected = p.id } } label: {
            HStack(spacing: 10) {
                Circle().fill(color(fix)).frame(width: 8, height: 8)
                Text(p.id == me ? String(localized: "You") : (p.displayName.split(separator: " ").first.map(String.init) ?? p.displayName))
                    .font(NTFont.body(16, .semibold))
                Spacer()
                if let fix {
                    Text(relative(fix)).font(NTFont.mono(11, .medium))
                    Text(fix.freshness() == .live ? "LIVE" : fix.ageLabel()).font(NTFont.mono(10.5, .medium))
                        .foregroundStyle(fix.freshness() == .live ? NTColor.milk(0.55) : NTColor.gold)
                } else {
                    Text("NOT SHARING").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.45))
                }
            }
            .padding(.vertical, detailed ? 12 : 11).padding(.horizontal, detailed ? 14 : 0)
            .background(detailed ? AnyShapeStyle(NTColor.pineRaised) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func color(_ fix: LiveFix?) -> Color {
        guard let fix else { return NTColor.milk(0.3) }
        switch fix.freshness() { case .live: return NTColor.sage; case .stale: return NTColor.gold; case .offline: return NTColor.milk(0.4) }
    }

    /// "420 M ↗ AHEAD": distance and which way, along the route when there is one.
    private func relative(_ fix: LiveFix) -> String {
        guard let mine = session.myLocation?.coordinate ?? me.flatMap({ session.fixes[$0]?.coordinate }), fix.userId != me else { return "—" }
        let d = Geo.distance(mine, fix.coordinate)
        if let a = Geo.project(fix.coordinate, onto: session.routeLine), let b = Geo.project(mine, onto: session.routeLine), abs(a.along - b.along) > 30 {
            return "\(Geo.distanceLabel(d)) \(a.along > b.along ? "↗ " + String(localized: "AHEAD") : "↙ " + String(localized: "BEHIND"))"
        }
        return "\(Geo.distanceLabel(d)) \(Geo.compass(Geo.bearing(from: mine, to: fix.coordinate)))"
    }

    // MARK: Convoy

    /// Cars, ordered by progress along the route (lead first).
    private var cars: [(driver: UUID, riders: [UUID])] {
        var groups: [UUID: [UUID]] = [:]
        for m in session.members {
            let d = m.carDriverId ?? m.person.id
            groups[d, default: []].append(m.person.id)
        }
        return groups.map { ($0.key, $0.value) }.sorted { a, b in
            progress(a.driver) > progress(b.driver)
        }
    }

    private func progress(_ id: UUID) -> Double {
        guard let f = session.fixes[id] else { return -1 }
        return Geo.project(f.coordinate, onto: session.routeLine)?.along ?? 0
    }

    private func carNumber(for user: UUID) -> Int? {
        let driver = session.members.first { $0.person.id == user }?.carDriverId ?? user
        return cars.firstIndex { $0.driver == driver }.map { $0 + 1 }
    }

    private func carLabel(for user: UUID) -> String { String(localized: "Car \(carNumber(for: user) ?? 1)") }

    private var convoySheet: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Convoy").font(NTFont.heading(20, .bold))
                Spacer()
                Text("\(cars.count) CARS").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
            }
            VStack(spacing: 0) {
                ForEach(Array(cars.enumerated()), id: \.element.driver) { i, car in
                    if i > 0 { Rectangle().fill(NTColor.pineLine).frame(height: 1) }
                    let stopped = session.alerts.first { $0.subject == car.driver && $0.kind == "convoy_stopped" }
                    HStack(spacing: 12) {
                        Text("\(i + 1)").font(NTFont.mono(12, .semibold)).foregroundStyle(stopped == nil ? NTColor.pine : .white)
                            .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 8).fill(stopped == nil ? NTColor.milk : NTColor.hard))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(car.riders.compactMap { session.person[$0]?.displayName.split(separator: " ").first.map(String.init) }
                                .map { $0 }.joined(separator: " & ").replacingOccurrences(of: "\(session.person[me ?? UUID()]?.displayName.split(separator: " ").first.map(String.init) ?? "—")", with: String(localized: "You")))
                                .font(NTFont.body(15, .semibold)).lineLimit(1)
                            Text(convoyMeta(car.driver, index: i)).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55))
                        }
                        Spacer()
                        Text(stopped != nil ? "STOPPED \(max(1, Int(Date().timeIntervalSince(stopped!.since) / 60))) MIN"
                             : (session.fixes[car.driver] == nil ? "—" : "MOVING"))
                            .font(NTFont.mono(10.5, .semibold)).foregroundStyle(stopped != nil ? NTColor.hardBright : NTColor.sage)
                    }
                    .padding(.vertical, 11)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(NTColor.pineElevated))
    }

    private func convoyMeta(_ driver: UUID, index: Int) -> String {
        guard let f = session.fixes[driver] else { return String(localized: "NO POSITION") }
        var parts: [String] = []
        if index == 0 { parts.append("LEAD") }
        if let s = f.speed, s >= 0 { parts.append("\(Int(s * 3.6)) KM/H") }
        if index > 0, let lead = cars.first?.driver, let a = Geo.project(session.fixes[lead]?.coordinate ?? f.coordinate, onto: session.routeLine),
           let b = Geo.project(f.coordinate, onto: session.routeLine) { parts.append(Geo.distanceLabel(max(0, a.along - b.along)) + " " + String(localized: "BEHIND")) }
        return parts.joined(separator: " · ")
    }
}

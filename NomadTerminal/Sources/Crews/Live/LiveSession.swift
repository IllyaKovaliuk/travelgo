import Foundation
import CoreLocation
import UIKit
import UserNotifications
import Observation

/// An alert currently worth showing: who it's about, what, since when.
struct LiveAlert: Identifiable, Hashable {
    let id: String
    let kind: String          // AlertKind raw value or "convoy_stopped"
    let subject: UUID
    let since: Date
    let value: Double?
    let lat: Double?
    let lng: Double?
    var status: ConvoyReason?
    var etaMin: Int?
    var askOthers: String?
}

/// One live trip on this device: shares my position (only when I opted in),
/// polls everyone else's latest fix, and evaluates the crew's alert rules.
///
/// Rules are evaluated on device from the fixes received (so they keep
/// working when some members are out of signal); the server only stores the
/// resulting events. Polling, not websockets: every 10–30 s is plenty for
/// "where is everyone" and keeps this simple and cheap.
@MainActor
@Observable
final class LiveSession: NSObject {
    static let shared = LiveSession()

    // What the UI reads
    private(set) var expedition: Expedition?
    private(set) var members: [ExpeditionMember] = []
    private(set) var fixes: [UUID: LiveFix] = [:]
    private(set) var shares: [UUID: LiveShare] = [:]
    private(set) var rules: [String: AlertRule] = [:]
    private(set) var alerts: [LiveAlert] = []
    private(set) var regroup: AwarenessEvent?
    private(set) var routeLine: [CLLocationCoordinate2D] = []
    private(set) var myTrack: [CLLocationCoordinate2D] = []
    /// Elevation profile of the first planned route (normalized 0…1) with its high point and ascent, for the Ascent view.
    private(set) var profile: [Double] = []
    private(set) var profileHighM: Double = 0
    private(set) var profileAscentM: Double = 0
    private(set) var routeTitle = ""
    private(set) var myId: UUID?
    private(set) var isSharing = false
    private(set) var myLocation: CLLocation?
    var mode: AwarenessMode = .trail

    // Internals
    private let manager = CLLocationManager()
    private var pollTask: Task<Void, Never>?
    private var lastUpload = Date.distantPast
    private var pendingUpload = false
    private var stoppedSince: Date?
    private var raised: Set<String> = []
    private var share: LiveShare?
    private let defaultsKey = "io.nomadterminal.liveShare"

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .otherNavigation
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    var person: [UUID: CrewPerson] { Dictionary(uniqueKeysWithValues: members.map { ($0.person.id, $0.person) }) }
    var lead: UUID? { members.first { $0.awarenessRole == .lead }?.person.id }
    var sweep: UUID? { members.first { $0.awarenessRole == .sweep }?.person.id }

    func rule(_ kind: AlertKind) -> AlertRule {
        rules["\(kind.rawValue)|\(mode.rawValue)"]
            ?? AlertRule(kind: kind, mode: mode, threshold: AlertDefaults.threshold(kind, mode), enabled: kind != .turnaround)
    }

    // MARK: Lifecycle

    /// Attach to a trip: loads context and starts polling. Safe to call repeatedly.
    func attach(_ expedition: Expedition) async {
        if self.expedition?.id != expedition.id {
            resetState()
            self.expedition = expedition
            mode = expedition.startMode == "convoy" ? .road : .trail
        }
        myId = try? await RouteRepository.shared.ensureSession()
        await loadStatic()
        startPolling()
        resumeShareIfNeeded()
    }

    func detachIfIdle() {
        guard !isSharing else { return }
        pollTask?.cancel(); pollTask = nil
    }

    private func resetState() {
        pollTask?.cancel(); pollTask = nil
        fixes = [:]; shares = [:]; alerts = []; regroup = nil; routeLine = []; myTrack = []
        raised = []; stoppedSince = nil
    }

    private func loadStatic() async {
        guard let e = expedition else { return }
        members = (try? await CrewRepository.shared.fetchExpeditionMembers(expeditionId: e.id)) ?? members
        let r = (try? await CrewLiveRepository.shared.fetchRules(expeditionId: e.id)) ?? []
        rules = Dictionary(r.map { ("\($0.kind.rawValue)|\($0.mode.rawValue)", $0) }, uniquingKeysWith: { $1 })
        if routeLine.isEmpty { await loadRouteLine() }
    }

    /// The planned route (today's, else all) as a polyline, for off-route and the ascent profile.
    private func loadRouteLine() async {
        guard let e = expedition,
              let itinerary = try? await CrewRepository.shared.fetchItinerary(expeditionId: e.id) else { return }
        let sorted = itinerary.routes.sorted { (($0.dayIndex ?? 99), $0.position) < (($1.dayIndex ?? 99), $1.position) }
        var line: [CLLocationCoordinate2D] = []
        for (n, item) in sorted.prefix(4).enumerated() {
            if let dto = try? await RouteRepository.shared.fetchRouteDTO(id: item.routeId.uuidString) {
                let detail = dto.toRoute().detail
                line += detail.trackPoints.map(\.coordinate)
                if n == 0 {
                    profile = detail.elevationProfile
                    profileHighM = Double(detail.highPointM)
                    profileAscentM = Double(detail.ascentM)
                    routeTitle = item.title.replacingOccurrences(of: "\n", with: " ")
                }
            }
        }
        routeLine = line
    }

    // MARK: Sharing

    /// Starts (or updates) my location sharing. The caller has already shown the consent screen.
    func startSharing(until: Date, mode shareMode: String, lowPower: Bool) async throws {
        guard let e = expedition else { return }
        try await CrewLiveRepository.shared.startShare(expeditionId: e.id, mode: shareMode, until: until, lowPower: lowPower)
        let s = LiveShare(userId: myId ?? UUID(), mode: shareMode, until: until, lowPower: lowPower)
        share = s
        persist(s, expeditionId: e.id)
        beginLocationUpdates()
        requestNotificationPermission()
        await refresh()
    }

    func stopSharing() async {
        guard let e = expedition else { return }
        manager.stopUpdatingLocation()
        isSharing = false
        share = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        try? await CrewLiveRepository.shared.stopShare(expeditionId: e.id)
        await refresh()
    }

    private func beginLocationUpdates() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: return
        default: break
        }
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isSharing = true
    }

    private func persist(_ s: LiveShare, expeditionId: UUID) {
        UserDefaults.standard.set(["e": expeditionId.uuidString, "until": s.until.timeIntervalSince1970,
                                   "low": s.lowPower, "mode": s.mode] as [String: Any], forKey: defaultsKey)
    }

    /// After a relaunch the share is still on the server; pick the location updates back up.
    private func resumeShareIfNeeded() {
        guard !isSharing, let d = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let e = d["e"] as? String, e == expedition?.id.uuidString,
              let until = d["until"] as? Double, Date(timeIntervalSince1970: until) > Date() else { return }
        share = LiveShare(userId: myId ?? UUID(), mode: d["mode"] as? String ?? "trip_end",
                          until: Date(timeIntervalSince1970: until), lowPower: d["low"] as? Bool ?? false)
        beginLocationUpdates()
    }

    /// Re-attaches to a share saved before the app was killed, without opening the map first.
    func resumeSavedShare(loadExpedition: Bool = true) async {
        guard !isSharing, let d = UserDefaults.standard.dictionary(forKey: defaultsKey),
              let e = d["e"] as? String, let id = UUID(uuidString: e),
              let until = d["until"] as? Double, Date(timeIntervalSince1970: until) > Date() else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }
        if let exp = try? await CrewRepository.shared.fetchExpedition(id: id), exp.status == .active {
            await attach(exp)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    // MARK: Polling + rule evaluation

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    func refresh() async {
        guard let e = expedition else { return }
        async let f = try? CrewLiveRepository.shared.fetchFixes(expeditionId: e.id)
        async let s = try? CrewLiveRepository.shared.fetchShares(expeditionId: e.id)
        async let c = try? CrewLiveRepository.shared.fetchConvoyEvents(expeditionId: e.id, since: Date().addingTimeInterval(-3 * 3600))
        async let a = try? CrewLiveRepository.shared.fetchAwareness(expeditionId: e.id, since: Date().addingTimeInterval(-3 * 3600))
        let (fx, sh, cv, aw) = await (f, s, c, a)
        if let fx { fixes = Dictionary(fx.map { ($0.userId, $0) }, uniquingKeysWith: { $1 }) }
        if let sh { shares = Dictionary(sh.map { ($0.userId, $0) }, uniquingKeysWith: { $1 }) }
        rebuildAlerts(convoy: cv ?? [], awareness: aw ?? [])
        if share != nil, let until = share?.until, until < Date() { await stopSharing() }
        await evaluateRules()
        await flushPendingFix()
    }

    private func rebuildAlerts(convoy: [ConvoyEvent], awareness: [AwarenessEvent]) {
        var out: [LiveAlert] = []
        // convoy: a car is "stopped" until it reports resumed after the stop
        let byCar = Dictionary(grouping: convoy, by: \.driverId)
        for (driver, events) in byCar {
            let sorted = events.sorted { $0.createdAt > $1.createdAt }
            guard let stop = sorted.first(where: { $0.kind == "stopped" || $0.kind == "help" }),
                  !sorted.contains(where: { $0.kind == "resumed" && $0.createdAt > stop.createdAt }) else { continue }
            let status = sorted.first { $0.kind == "status" && $0.createdAt >= stop.createdAt }
            out.append(LiveAlert(id: "convoy-\(driver)", kind: stop.kind == "help" ? "help" : "convoy_stopped", subject: driver,
                                 since: stop.createdAt, value: nil, lat: stop.lat, lng: stop.lng,
                                 status: status?.status, etaMin: status?.etaMin, askOthers: status?.askOthers))
        }
        // awareness alerts from the last 15 minutes, newest per kind+subject
        var seen = Set<String>()
        for ev in awareness where Date().timeIntervalSince(ev.createdAt) < 900 {
            if ev.kind == "regroup" { if regroup == nil || ev.createdAt > regroup!.createdAt { regroup = ev }; continue }
            guard AlertKind(rawValue: ev.kind) != nil else { continue }
            let subject = ev.targetUserId ?? ev.userId
            let key = "\(ev.kind)|\(subject)"
            guard seen.insert(key).inserted else { continue }
            out.append(LiveAlert(id: ev.id.uuidString, kind: ev.kind, subject: subject, since: ev.createdAt, value: ev.value,
                                 lat: ev.lat, lng: ev.lng))
        }
        let new = Set(out.map(\.id)).subtracting(alerts.map(\.id))
        alerts = out.sorted { $0.since > $1.since }
        for a in alerts where new.contains(a.id) && a.subject != myId { notify(a) }
    }

    /// Each device checks the rules for *itself* (battery, stops, route, gap to the lead) and for others'
    /// silence, then posts one event per subject; the server dedupes, so two devices don't double up.
    private func evaluateRules() async {
        guard let e = expedition, let me = myId, e.status == .active else { return }
        let myFix = fixes[me]

        // battery
        let low = rule(.lowBattery)
        if low.enabled, let b = myFix?.battery ?? currentBattery(), Double(b) < low.threshold {
            await post(.lowBattery, value: Double(b), at: myFix?.coordinate)
        }

        guard let myFix else { return }
        let myCoord = myFix.coordinate

        // off route
        let off = rule(.offRoute)
        if off.enabled, let proj = Geo.project(myCoord, onto: routeLine), proj.off > off.threshold, proj.off < 20_000 {
            await post(.offRoute, value: proj.off, at: myCoord)
        }

        // behind the lead
        let behind = rule(.fallingBehind)
        if behind.enabled, let leadId = lead, leadId != me, let leadFix = fixes[leadId], leadFix.freshness() == .live {
            let gap: Double
            if mode == .ascent { gap = abs((leadFix.altitude ?? 0) - (myFix.altitude ?? 0)) }
            else if let a = Geo.project(leadFix.coordinate, onto: routeLine), let b = Geo.project(myCoord, onto: routeLine) {
                gap = max(0, a.along - b.along)
            } else { gap = Geo.distance(leadFix.coordinate, myCoord) }
            if gap > behind.threshold { await post(.fallingBehind, value: gap, at: myCoord) }
        }

        // spread (reported by whoever sees it first)
        let spread = rule(.groupSpread)
        let live = fixes.values.filter { $0.freshness() == .live }
        if spread.enabled, live.count > 1 {
            var widest = 0.0
            for a in live { for b in live where a.userId < b.userId { widest = max(widest, Geo.distance(a.coordinate, b.coordinate)) } }
            if widest > spread.threshold { await post(.groupSpread, value: widest, at: myCoord) }
        }

        // other people's silence: only the sweep (or, with no sweep, the lead) reports it
        let silence = rule(.noSignal)
        if silence.enabled, me == (sweep ?? lead) {
            for (uid, fix) in fixes where uid != me && Date().timeIntervalSince(fix.recordedAt) > silence.threshold * 60 {
                await post(.noSignal, value: Date().timeIntervalSince(fix.recordedAt) / 60, at: fix.coordinate, subject: uid)
            }
        }

        // turnaround reminder (minutes since midnight)
        let t = rule(.turnaround)
        if t.enabled, t.threshold > 0 {
            let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let now = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if now >= t.threshold && now < t.threshold + 30 { await post(.turnaround, value: t.threshold, at: myCoord) }
        }
    }

    private func post(_ kind: AlertKind, value: Double, at: CLLocationCoordinate2D?, subject: UUID? = nil) async {
        guard let e = expedition else { return }
        let key = "\(kind.rawValue)|\(subject?.uuidString ?? "me")|\(Int(Date().timeIntervalSince1970 / 300))"
        guard raised.insert(key).inserted else { return }
        _ = try? await CrewLiveRepository.shared.postAwareness(
            expeditionId: e.id, kind: kind.rawValue, value: value, lat: at?.latitude, lng: at?.longitude, target: subject)
    }

    // MARK: Location uploads

    private func currentBattery() -> Int? {
        let l = UIDevice.current.batteryLevel
        return l < 0 ? nil : Int((l * 100).rounded())
    }

    private func upload(_ loc: CLLocation) async {
        guard let e = expedition, let share, share.until > Date() else { return }
        do {
            try await CrewLiveRepository.shared.upsertFix(
                expeditionId: e.id, lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
                altitude: loc.verticalAccuracy >= 0 ? loc.altitude : nil, accuracy: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil,
                speed: loc.speed >= 0 ? loc.speed : nil, heading: loc.course >= 0 ? loc.course : nil,
                battery: currentBattery(), recordedAt: loc.timestamp)
            pendingUpload = false
        } catch {
            // offline: keep only the newest position and retry on the next tick
            pendingUpload = true
        }
    }

    private func flushPendingFix() async {
        if pendingUpload, let loc = myLocation { await upload(loc) }
    }

    fileprivate func handle(_ loc: CLLocation) {
        myLocation = loc
        if myTrack.last.map({ Geo.distance($0, loc.coordinate) > 15 }) ?? true { myTrack.append(loc.coordinate) }
        if myTrack.count > 2_000 { myTrack.removeFirst(500) }
        detectStop(loc)
        let interval: TimeInterval = (share?.lowPower ?? false) ? 120 : 30
        guard Date().timeIntervalSince(lastUpload) >= interval else { return }
        lastUpload = Date()
        Task { await upload(loc) }
    }

    /// Road mode: below 5 km/h for the rule's minutes, away from any planned stop → a convoy "stopped" event.
    private func detectStop(_ loc: CLLocation) {
        guard expedition?.startMode == "convoy", let e = expedition else { return }
        let slow = loc.speed >= 0 && loc.speed < 1.4
        if !slow {
            if stoppedSince != nil {
                stoppedSince = nil
                Task { _ = try? await CrewLiveRepository.shared.postConvoyEvent(expeditionId: e.id, kind: "resumed") }
            }
            return
        }
        if stoppedSince == nil { stoppedSince = Date(); return }
        let r = rule(.stoppedOffPlan)
        guard r.enabled, Date().timeIntervalSince(stoppedSince!) >= r.threshold * 60 else { return }
        let key = "stopped|\(Int(stoppedSince!.timeIntervalSince1970))"
        guard raised.insert(key).inserted else { return }
        Task {
            _ = try? await CrewLiveRepository.shared.postConvoyEvent(
                expeditionId: e.id, kind: "stopped", lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
            _ = try? await CrewLiveRepository.shared.postAwareness(
                expeditionId: e.id, kind: AlertKind.stoppedOffPlan.rawValue, value: r.threshold,
                lat: loc.coordinate.latitude, lng: loc.coordinate.longitude)
        }
    }

    // MARK: Actions the UI triggers

    func setRegroup(at coordinate: CLLocationCoordinate2D) async {
        guard let e = expedition else { return }
        _ = try? await CrewLiveRepository.shared.postAwareness(
            expeditionId: e.id, kind: "regroup", lat: coordinate.latitude, lng: coordinate.longitude)
        await refresh()
    }

    func ping(_ userId: UUID) async {
        guard let e = expedition else { return }
        _ = try? await CrewLiveRepository.shared.postAwareness(expeditionId: e.id, kind: "ping", target: userId)
    }

    func reportResumed() async {
        guard let e = expedition else { return }
        _ = try? await CrewLiveRepository.shared.postConvoyEvent(expeditionId: e.id, kind: "resumed")
        await refresh()
    }

    // MARK: Local notifications (app in the background)

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ alert: LiveAlert) {
        guard UIApplication.shared.applicationState != .active else { return }
        let name = person[alert.subject]?.displayName ?? String(localized: "Someone")
        let content = UNMutableNotificationContent()
        content.title = expedition?.name ?? "Nomad"
        if let kind = AlertKind(rawValue: alert.kind) { content.body = "\(name) · \(kind.bannerTitle)" }
        else { content.body = "\(name) · " + String(localized: "stopped") }
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: alert.id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
}

extension LiveSession: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in LiveSession.shared.handle(loc) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let s = LiveSession.shared
            if s.share != nil, [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { s.beginLocationUpdates() }
        }
    }
}

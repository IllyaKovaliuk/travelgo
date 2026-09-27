import CoreLocation

/// Part 3 — passive arrival/stay detection via `CLLocationManager
/// .startMonitoringVisits()`. Deliberately separate from `RouteTracker`:
/// visits are cell/Wi-Fi based and effectively free on battery, reported on
/// Apple's own heuristic and timing (can take a while to arrive, sometimes
/// hours) — this is what feeds the Journal, not a substitute for an active
/// LogRoute recording, and never feeds km/streak/leaderboard (see
/// `ProfileView.countriesVisited` for the one, explicitly-confirmed-only
/// exception).
///
/// A singleton rather than something scoped to a view's lifetime — unlike
/// `RouteTracker` (owned by `RecordTrackView`, only ever alive while that
/// screen is on screen), this has to keep working with *no* view on screen
/// at all: iOS can relaunch the app headless purely to deliver a pending
/// `CLVisit`, and `NomadTerminalApp`'s `AppDelegate` calls
/// `applicationDidLaunch()` immediately on every launch (including that
/// headless one) specifically so the delegate is already wired up before
/// the event arrives.
@MainActor
final class VisitsMonitor: NSObject {
    static let shared = VisitsMonitor()

    private let manager = CLLocationManager()

    /// CLVisit's own detection already filters most sub-few-minute noise
    /// (a stoplight, a drive-through pass), but a real errand — a quick
    /// grocery run, a gas stop — can still land in the 10-15 minute range
    /// and would otherwise spam the Journal with stops nobody wants
    /// logged. 20 minutes is a deliberately loose floor above that: long
    /// enough to skip routine errands, short enough to still catch a real
    /// coffee/lunch stop, sightseeing pause, or obviously anything
    /// overnight. Tune here if it turns out too chatty or too quiet.
    private static let minimumStaySeconds: TimeInterval = 20 * 60

    private override init() {
        super.init()
        manager.delegate = self
    }

    /// Call once, as early as possible — `NomadTerminalApp`'s
    /// `AppDelegate.application(_:didFinishLaunchingWithOptions:)`, not a
    /// SwiftUI `.onAppear` (which wouldn't exist yet for a headless
    /// visit-delivery relaunch). Re-registers monitoring on every cold
    /// launch: CoreLocation's underlying visit-detection state persists
    /// across launches on its own, but the *delegate* registration this
    /// process needs to actually receive the callback does not, so this
    /// has to run again every time regardless.
    func applicationDidLaunch() {
        guard AppPreferences.visitsMonitoringEnabled, manager.authorizationStatus == .authorizedAlways else { return }
        manager.startMonitoringVisits()
    }

    /// Called from Settings the moment the toggle flips on.
    func start() {
        guard AppPreferences.visitsMonitoringEnabled else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            // Same contextual-upgrade-on-fresh-grant fix as
            // `RouteTracker.start()` — see its own doc comment for why
            // this has to happen both here *and* in
            // `locationManagerDidChangeAuthorization` below to actually
            // close the loop within one session.
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            manager.startMonitoringVisits()
        default:
            break
        }
    }

    func stop() {
        manager.stopMonitoringVisits()
    }

    private func handle(_ visit: CLVisit) async {
        let lat = visit.coordinate.latitude
        let lng = visit.coordinate.longitude

        if visit.departureDate == .distantFuture {
            // "Still here" — an arrival signal with no departure known yet.
            // Guard against a duplicate open row if CoreLocation re-delivers
            // the same still-ongoing visit.
            if let existing = try? await RouteRepository.shared.findOpenVisit(nearLat: lat, lng: lng), existing.departureAt == nil {
                return
            }
            let arrival = visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate
            let placeName = await Self.reverseGeocode(lat: lat, lng: lng)
            _ = try? await RouteRepository.shared.insertPendingVisit(lat: lat, lng: lng, placeName: placeName, arrivalAt: arrival, departureAt: nil)
            return
        }

        // A real departure. `arrivalDate` is `.distantPast` when
        // CoreLocation never actually observed the arrival (e.g. Visits
        // monitoring only just started while already at this location) —
        // there's no honest real arrival time in that case, so this backs
        // it out from the minimum-stay floor rather than inventing one.
        let arrival = visit.arrivalDate == .distantPast
            ? visit.departureDate.addingTimeInterval(-Self.minimumStaySeconds)
            : visit.arrivalDate
        let duration = visit.departureDate.timeIntervalSince(arrival)
        let existing = try? await RouteRepository.shared.findOpenVisit(nearLat: lat, lng: lng)

        guard duration >= Self.minimumStaySeconds else {
            // Too short to be worth journaling — if an open row already
            // exists from the earlier arrival signal, remove it rather
            // than leaving an orphaned pending entry with no departure.
            if let existing { try? await RouteRepository.shared.deleteVisit(id: existing.id.uuidString) }
            return
        }

        if let existing {
            try? await RouteRepository.shared.updateVisitDeparture(id: existing.id.uuidString, departureAt: visit.departureDate)
        } else {
            let placeName = await Self.reverseGeocode(lat: lat, lng: lng)
            _ = try? await RouteRepository.shared.insertPendingVisit(lat: lat, lng: lng, placeName: placeName, arrivalAt: arrival, departureAt: visit.departureDate)
        }
    }

    /// "Locality, Country" — the exact same shape `routes.place` already
    /// uses, so `ProfileView.countryTag(from:)` (splits on the last comma)
    /// works unchanged for a kept visit too, no second country-parsing path.
    private static func reverseGeocode(lat: Double, lng: Double) async -> String? {
        let location = CLLocation(latitude: lat, longitude: lng)
        guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let locality = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.administrativeArea
        switch (locality, placemark.country) {
        case let (loc?, country?): return "\(loc), \(country)"
        case let (loc?, nil): return loc
        case let (nil, country?): return country
        default: return nil
        }
    }
}

extension VisitsMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse:
                manager.requestAlwaysAuthorization()
            case .authorizedAlways:
                if AppPreferences.visitsMonitoringEnabled {
                    manager.startMonitoringVisits()
                }
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            await self.handle(visit)
        }
    }
}

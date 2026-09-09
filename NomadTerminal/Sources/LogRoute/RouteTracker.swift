import Foundation
import CoreLocation
import Observation

/// A recorded GPS point — the wire shape for `routes.track_points` (jsonb
/// array of `{"lat", "lng"}` objects).
struct TrackPoint: Codable, Hashable {
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

/// Real GPS recording for the log-a-route flow — replaces the old simulated
/// pace timer. Reads CoreLocation directly: distance is the sum of
/// consecutive `CLLocation.distance(from:)`, ascent is the sum of positive
/// altitude deltas (filtered against GPS altitude noise), points are kept
/// in order for the route's stored polyline.
@MainActor
@Observable
final class RouteTracker: NSObject {
    private(set) var points: [TrackPoint] = []
    private(set) var distanceKM: Double = 0
    private(set) var ascentM: Double = 0
    /// Highest altitude actually observed during the recording (meters
    /// above sea level) — feeds the route's "high point" stat.
    private(set) var highPointM: Double = 0
    private(set) var isAuthorized = true
    var authorizationDenied = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    /// Ignore altitude jitter smaller than this per-sample before counting it as real ascent.
    private let altitudeNoiseFloorM: Double = 1.5

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    func start() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        case .authorizedWhenInUse:
            // Upgrade contextually, right when a recording actually starts
            // (Apple's recommended pattern) rather than asking for Always
            // upfront during onboarding — this is also what keeps the
            // Dynamic Island / lock-screen Live Activity fed with fresh
            // stats if the phone gets pocketed mid-recording.
            manager.requestAlwaysAuthorization()
            manager.startUpdatingLocation()
        default:
            manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
            manager.startUpdatingLocation()
        }
    }

    func pause() {
        manager.stopUpdatingLocation()
    }

    func resume() {
        lastLocation = nil // avoid one big jump being counted as distance after a pause
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Downsampled to a sane number of points for storage/rendering — a
    /// multi-hour recording at 1 sample/sec would otherwise be thousands of
    /// points for very little visual gain on a phone-sized map.
    var storedPoints: [TrackPoint] {
        let maxPoints = 300
        guard points.count > maxPoints else { return points }
        let stride = Double(points.count) / Double(maxPoints)
        return (0..<maxPoints).map { points[Int(Double($0) * stride)] }
    }
}

extension RouteTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways:
                self.authorizationDenied = false
                manager.allowsBackgroundLocationUpdates = true
                manager.startUpdatingLocation()
            case .authorizedWhenInUse:
                self.authorizationDenied = false
                manager.allowsBackgroundLocationUpdates = false
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.authorizationDenied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else { continue }

                if location.verticalAccuracy >= 0, location.altitude > self.highPointM {
                    self.highPointM = location.altitude
                }

                if let last = self.lastLocation {
                    let delta = location.distance(from: last)
                    // Drop GPS jitter while stationary — a phone sitting still
                    // can "drift" several meters between fixes.
                    if delta > 2 {
                        self.distanceKM += delta / 1000
                        let altDelta = location.altitude - last.altitude
                        if altDelta > self.altitudeNoiseFloorM {
                            self.ascentM += altDelta
                        }
                        self.points.append(TrackPoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude))
                    }
                } else {
                    self.points.append(TrackPoint(lat: location.coordinate.latitude, lng: location.coordinate.longitude))
                }
                self.lastLocation = location
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are normal (tunnels, cold starts) — nothing
        // to surface to the user, CoreLocation keeps retrying on its own.
    }
}

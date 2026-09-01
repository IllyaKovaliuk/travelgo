import Foundation
import CoreLocation
import Observation

/// Real device heading + location for Compass mode — replaces the old
/// sine-wave simulation. When given a target coordinate, computes real
/// bearing/distance to it from the live location; with no target, the
/// needle just points to true north like an ordinary compass.
@MainActor
@Observable
final class CompassTracker: NSObject {
    private(set) var headingDegrees: Double = 0
    private(set) var currentLocation: CLLocation?
    private(set) var speedKMH: Double = 0
    private(set) var altitudeM: Double = 0
    private(set) var horizontalAccuracyM: Double = -1
    var authorizationDenied = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            beginUpdates()
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func beginUpdates() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    /// True-north bearing (0..<360) from the live location to `target`, via
    /// the standard great-circle initial-bearing formula.
    func bearing(to target: CLLocationCoordinate2D) -> Double? {
        guard let current = currentLocation?.coordinate else { return nil }
        let lat1 = current.latitude * .pi / 180, lon1 = current.longitude * .pi / 180
        let lat2 = target.latitude * .pi / 180, lon2 = target.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    func distanceKM(to target: CLLocationCoordinate2D) -> Double? {
        guard let current = currentLocation else { return nil }
        return current.distance(from: CLLocation(latitude: target.latitude, longitude: target.longitude)) / 1000
    }
}

extension CompassTracker: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.authorizationDenied = false
                self.beginUpdates()
            case .denied, .restricted:
                self.authorizationDenied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let loc = locations.last else { return }
            self.currentLocation = loc
            self.speedKMH = max(0, loc.speed) * 3.6
            self.horizontalAccuracyM = loc.horizontalAccuracy
            if loc.verticalAccuracy >= 0 { self.altitudeM = loc.altitude }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.headingDegrees = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient GPS errors are normal — CoreLocation keeps retrying on its own.
    }
}

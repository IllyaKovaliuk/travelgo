import Foundation
import CoreLocation
import Observation

/// Real guidance derived from the route's own recorded geometry — never a
/// routing-engine's turn-by-turn instruction, because there isn't one:
/// this app records and replays a GPS trail, it doesn't route against a
/// road network. `direction` compares where the trail heads ~`lookaheadM`
/// ahead against where the person is actually facing right now (live
/// course/heading), which is a real, honest signal — just not the same
/// thing as "turn left onto Main St."
struct TrackGuidance {
    enum Direction {
        case straight, bearLeft, bearRight, sharpLeft, sharpRight

        var icon: String {
            switch self {
            case .straight: return "arrow.up"
            case .bearLeft: return "arrow.up.left"
            case .bearRight: return "arrow.up.right"
            case .sharpLeft: return "arrow.turn.up.left"
            case .sharpRight: return "arrow.turn.up.right"
            }
        }
    }

    let direction: Direction
    let distanceToTurnM: Double
    /// The real segment name the upcoming stretch belongs to — nil for a
    /// single-segment (or segment-less) route rather than a fabricated one.
    let label: String?
}

/// Real-time progress against one route's recorded track — powers
/// `NavigationModeView`'s HUD, maneuver banner, and off-track warning.
///
/// Runs its own `CLLocationManager`, separate from the map's internal
/// location provider (which drives the puck + `Viewport.followPuck`
/// camera via `Puck2D` in `NavigationModeView`) — the same "each screen
/// owns its own location manager" pattern `RouteTracker` and
/// `CompassTracker` already use independently elsewhere in this app, not a
/// new architecture decision.
@MainActor
@Observable
final class NavigationSession: NSObject {
    private(set) var currentLocation: CLLocation?
    private(set) var speedKMH: Double = 0
    private(set) var altitudeM: Double = 0
    private(set) var headingDegrees: Double = 0
    private(set) var horizontalAccuracyM: Double = -1
    var authorizationDenied = false

    private(set) var isOffTrack = false
    private(set) var distanceFromTrackM: Double = 0
    private(set) var traveledDistanceKM: Double = 0
    private(set) var remainingDistanceKM: Double
    /// nil while stopped/too slow to project meaningfully — an ETA
    /// computed against ~0 km/h is a lie dressed as a number, not a real
    /// estimate.
    private(set) var etaDate: Date?
    private(set) var guidance: TrackGuidance?

    let totalDistanceKM: Double
    private let stretches: [MapSegmentStretch]
    /// Every stretch's coordinates flattened into one ordered path, each
    /// point carrying its cumulative distance (meters) from the route
    /// start — the working representation off-track/progress/guidance
    /// math actually walks.
    private let path: [(coordinate: CLLocationCoordinate2D, cumulativeM: Double)]

    private let offTrackThresholdM: Double = 35
    private let lookaheadM: Double = 80

    private let manager = CLLocationManager()

    init(stretches: [MapSegmentStretch], totalDistanceKM: Double) {
        self.stretches = stretches
        self.totalDistanceKM = totalDistanceKM
        self.remainingDistanceKM = totalDistanceKM
        self.path = Self.buildPath(stretches)
        super.init()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.activityType = .otherNavigation
        manager.headingFilter = 2
        manager.delegate = self
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
        manager.allowsBackgroundLocationUpdates = manager.authorizationStatus == .authorizedAlways
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    private static func buildPath(_ stretches: [MapSegmentStretch]) -> [(coordinate: CLLocationCoordinate2D, cumulativeM: Double)] {
        var result: [(coordinate: CLLocationCoordinate2D, cumulativeM: Double)] = []
        var cumulative: Double = 0
        var last: CLLocationCoordinate2D?
        for stretch in stretches {
            for coordinate in stretch.coordinates {
                if let last { cumulative += GeoMath.distanceMeters(last, coordinate) }
                result.append((coordinate, cumulative))
                last = coordinate
            }
        }
        return result
    }

    private func handle(_ location: CLLocation) {
        currentLocation = location
        speedKMH = max(0, location.speed) * 3.6
        horizontalAccuracyM = location.horizontalAccuracy
        if location.verticalAccuracy >= 0 { altitudeM = location.altitude }
        refreshProgress(at: location)
    }

    private func refreshProgress(at location: CLLocation) {
        guard path.count > 1 else { return }

        var bestDistanceM = Double.greatestFiniteMagnitude
        var bestCumulativeM: Double = 0
        var bestIndex = 0
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let (distanceM, fraction) = GeoMath.distance(from: location.coordinate, toSegment: a.coordinate, b.coordinate)
            if distanceM < bestDistanceM {
                bestDistanceM = distanceM
                bestCumulativeM = a.cumulativeM + (b.cumulativeM - a.cumulativeM) * fraction
                bestIndex = i
            }
        }

        distanceFromTrackM = bestDistanceM
        isOffTrack = bestDistanceM > offTrackThresholdM
        traveledDistanceKM = bestCumulativeM / 1000
        remainingDistanceKM = max(0, totalDistanceKM - traveledDistanceKM)

        etaDate = speedKMH > 1 ? Date().addingTimeInterval(remainingDistanceKM / speedKMH * 3600) : nil

        guidance = computeGuidance(currentCumulativeM: bestCumulativeM, currentIndex: bestIndex, referenceBearing: referenceBearing(for: location))
    }

    /// Live course (direction of actual travel) when it's real and the
    /// person is actually moving — a `CLLocation.course` below 0 or a near-
    /// standstill speed makes GPS course noise, not signal, so this falls
    /// back to the compass heading instead.
    private func referenceBearing(for location: CLLocation) -> Double {
        (location.course >= 0 && location.speed > 0.5) ? location.course : headingDegrees
    }

    private func computeGuidance(currentCumulativeM: Double, currentIndex: Int, referenceBearing: Double) -> TrackGuidance? {
        var targetIndex = currentIndex
        while targetIndex < path.count - 1, path[targetIndex].cumulativeM < currentCumulativeM + lookaheadM {
            targetIndex += 1
        }
        guard targetIndex < path.count, let location = currentLocation else { return nil }

        let pathBearing = GeoMath.bearing(from: location.coordinate, to: path[targetIndex].coordinate)
        let delta = GeoMath.signedDelta(from: referenceBearing, to: pathBearing)

        let direction: TrackGuidance.Direction
        switch delta {
        case -12...12: direction = .straight
        case 12..<45: direction = .bearRight
        case -45 ..< -12: direction = .bearLeft
        case 45...180: direction = .sharpRight
        default: direction = .sharpLeft
        }

        return TrackGuidance(
            direction: direction,
            distanceToTurnM: max(0, path[targetIndex].cumulativeM - currentCumulativeM),
            label: stretchLabel(atCumulativeM: path[targetIndex].cumulativeM)
        )
    }

    private func stretchLabel(atCumulativeM cumulativeM: Double) -> String? {
        var running: Double = 0
        for stretch in stretches {
            running += stretch.distanceKM * 1000
            if cumulativeM <= running { return stretch.label }
        }
        return stretches.last?.label
    }
}

extension NavigationSession: CLLocationManagerDelegate {
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
            guard let location = locations.last else { return }
            self.handle(location)
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

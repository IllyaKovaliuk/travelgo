import CoreLocation

/// Pure geometry helpers for `NavigationSession` — off-track distance and
/// upcoming-bearing detection against a recorded track. Deliberately not
/// shared with `CompassTracker.bearing(to:)` (same great-circle formula,
/// small enough that duplicating it here beats coupling two independent,
/// already-shipped trackers together for it) — same tradeoff this project
/// already makes between `RouteTracker` and `CompassTracker`.
enum GeoMath {
    static func distanceMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// True-north initial bearing (0..<360) from `a` to `b`, standard
    /// great-circle formula.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lon1 = a.longitude * .pi / 180
        let lat2 = b.latitude * .pi / 180, lon2 = b.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return deg < 0 ? deg + 360 : deg
    }

    /// The closest point on segment `a`→`b` to `point`, as
    /// (distance in meters, fraction 0...1 along the segment).
    ///
    /// Projection itself is done in a flat-earth (equirectangular) frame
    /// local to the segment — accurate at the scale a single polyline
    /// segment actually spans (tens of meters between consecutive
    /// already-smoothed track points, never a segment long enough for
    /// Earth's curvature to matter) — but the *reported* distance is real
    /// `CLLocation` great-circle distance to that projected point, not the
    /// flat approximation itself.
    static func distance(
        from point: CLLocationCoordinate2D,
        toSegment a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> (meters: Double, fraction: Double) {
        let latRad = a.latitude * .pi / 180
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latRad)

        let bx = (b.longitude - a.longitude) * metersPerDegreeLon
        let by = (b.latitude - a.latitude) * metersPerDegreeLat
        let px = (point.longitude - a.longitude) * metersPerDegreeLon
        let py = (point.latitude - a.latitude) * metersPerDegreeLat

        let lengthSquared = bx * bx + by * by
        let fraction: Double = lengthSquared < 1e-9 ? 0 : max(0, min(1, (px * bx + py * by) / lengthSquared))

        let projected = CLLocationCoordinate2D(
            latitude: a.latitude + fraction * (b.latitude - a.latitude),
            longitude: a.longitude + fraction * (b.longitude - a.longitude)
        )
        return (distanceMeters(point, projected), fraction)
    }

    /// Signed angle (-180...180) you'd have to turn from `reference` to
    /// face `target` — positive is clockwise/right, negative is
    /// counter-clockwise/left.
    static func signedDelta(from reference: Double, to target: Double) -> Double {
        var delta = (target - reference).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
}

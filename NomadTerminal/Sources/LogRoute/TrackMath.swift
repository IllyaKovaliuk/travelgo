import CoreLocation

/// Batch versions of the same distance/ascent math `RouteTracker` already
/// does live, per-GPS-fix, while recording. Not shared code with
/// `RouteTracker` itself — that class accumulates incrementally against a
/// running `lastLocation` as fixes arrive in real time, which doesn't fit
/// a full array known upfront (an imported file, or a hand-drawn path).
/// Deliberately not refactoring `RouteTracker` to sit on top of this — it's
/// a proven, already-shipped live-recording path, not worth the regression
/// risk of restructuring it just for code reuse.
enum TrackMath {
    /// Sum of consecutive `CLLocation.distance(from:)` — the same
    /// great-circle ground distance `RouteTracker` sums, just over a whole
    /// array at once instead of one fix at a time.
    static func distanceKM(_ coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var meters: Double = 0
        var last = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        for coordinate in coordinates.dropFirst() {
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            meters += current.distance(from: last)
            last = current
        }
        return meters / 1000
    }

    /// Sum of positive elevation deltas above `noiseFloorM` — mirrors
    /// `RouteTracker`'s own `altitudeNoiseFloorM` filtering so a GPX/KML
    /// file's own elevation jitter doesn't inflate ascent any more than a
    /// live recording's GPS altitude noise would.
    static func ascentM(_ elevations: [Double], noiseFloorM: Double = 1.5) -> Double {
        guard elevations.count > 1 else { return 0 }
        var ascent: Double = 0
        for i in 1..<elevations.count {
            let delta = elevations[i] - elevations[i - 1]
            if delta > noiseFloorM { ascent += delta }
        }
        return ascent
    }

    static func highPointM(_ elevations: [Double]) -> Double {
        elevations.max() ?? 0
    }

    /// Same downsampling `RouteTracker.storedPoints` applies to a live
    /// recording — an imported file can easily be a few thousand points
    /// (a multi-hour GPX at 1 sample/sec), for no more visual gain on a
    /// phone-sized map than a live recording gets from the same cap.
    static func downsample(_ points: [TrackPoint], maxPoints: Int = 300) -> [TrackPoint] {
        guard points.count > maxPoints else { return points }
        let stride = Double(points.count) / Double(maxPoints)
        return (0..<maxPoints).map { points[Int(Double($0) * stride)] }
    }
}

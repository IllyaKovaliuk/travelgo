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

    /// Douglas-Peucker simplification (iterative, no recursion depth risk)
    /// that keeps every point where the path actually bends. The old
    /// uniform every-Nth-point downsample to 300 points turned a 44 km
    /// drive into ~150 m straight chords that cut straight through
    /// buildings — corners are what matter, not evenly spaced samples.
    /// Tolerance is widened only if the result still exceeds `maxPoints`.
    static func downsample(_ points: [TrackPoint], maxPoints: Int = 3000) -> [TrackPoint] {
        guard points.count > 2 else { return points }
        var tolerance = 2.0 // meters
        var result = simplify(points, toleranceM: tolerance)
        while result.count > maxPoints && tolerance < 200 {
            tolerance *= 1.6
            result = simplify(points, toleranceM: tolerance)
        }
        return result
    }

    static func simplify(_ points: [TrackPoint], toleranceM: Double) -> [TrackPoint] {
        let n = points.count
        guard n > 2 else { return points }
        // Local equirectangular projection to meters — plenty accurate at
        // route scale and much cheaper than great-circle per comparison.
        let lat0 = points[0].lat * .pi / 180
        let mx = 111_320.0 * cos(lat0), my = 110_540.0
        let xy = points.map { (x: $0.lng * mx, y: $0.lat * my) }
        var keep = [Bool](repeating: false, count: n)
        keep[0] = true; keep[n - 1] = true
        var stack = [(0, n - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let (ax, ay) = xy[a], (bx, by) = xy[b]
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            var maxD = 0.0, idx = a
            for i in (a + 1)..<b {
                let px = xy[i].x - ax, py = xy[i].y - ay
                let d: Double
                if len2 == 0 {
                    d = (px * px + py * py).squareRoot()
                } else {
                    let t = max(0, min(1, (px * dx + py * dy) / len2))
                    let ex = px - t * dx, ey = py - t * dy
                    d = (ex * ex + ey * ey).squareRoot()
                }
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > toleranceM {
                keep[idx] = true
                stack.append((a, idx)); stack.append((idx, b))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }
}

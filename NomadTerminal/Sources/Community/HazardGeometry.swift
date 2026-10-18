import Foundation
import CoreLocation

/// Small planar-distance helpers for "is this hazard on/near my route".
/// Local equirectangular projection to meters — accurate to well under a
/// meter at route scale, and far cheaper than great-circle per comparison.
enum HazardGeometry {
    /// Shortest distance in meters from `p` to the polyline `line`.
    static func distance(from p: CLLocationCoordinate2D, toPolyline line: [CLLocationCoordinate2D]) -> Double {
        guard let first = line.first else { return .infinity }
        let mx = 111_320.0 * cos(p.latitude * .pi / 180), my = 110_540.0
        func xy(_ c: CLLocationCoordinate2D) -> (Double, Double) { ((c.longitude - p.longitude) * mx, (c.latitude - p.latitude) * my) }
        if line.count == 1 { let (x, y) = xy(first); return (x * x + y * y).squareRoot() }
        var best = Double.infinity
        for i in 0..<(line.count - 1) {
            let (ax, ay) = xy(line[i]), (bx, by) = xy(line[i + 1])
            let dx = bx - ax, dy = by - ay
            let len2 = dx * dx + dy * dy
            let t = len2 == 0 ? 0 : max(0, min(1, (-ax * dx - ay * dy) / len2))
            let ex = ax + t * dx, ey = ay + t * dy
            best = min(best, (ex * ex + ey * ey).squareRoot())
        }
        return best
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Center + radius (km) of a box covering the whole track.
    static func searchArea(for points: [TrackPoint]) -> (center: CLLocationCoordinate2D, radiusKM: Double)? {
        guard let first = points.first else { return nil }
        var minLat = first.lat, maxLat = first.lat, minLng = first.lng, maxLng = first.lng
        for p in points {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLng = min(minLng, p.lng); maxLng = max(maxLng, p.lng)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let corner = CLLocationCoordinate2D(latitude: maxLat, longitude: maxLng)
        return (center, meters(center, corner) / 1000 + 1)
    }
}

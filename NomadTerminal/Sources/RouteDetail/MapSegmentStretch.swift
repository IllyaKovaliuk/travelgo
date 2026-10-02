import SwiftUI
import MapboxMaps
import Turf
import CoreLocation

/// One colored, labeled stretch of a route's polyline — the real recorded
/// track split proportionally by each segment's logged distance (there's no
/// exact GPS boundary between segments, only their order and length, so
/// this is the honest approximation of "which piece of the path used which
/// transport"). Shared by the Route Detail header preview and the
/// full-screen interactive map so both agree on the same split.
///
/// Coordinates go through two real passes before storage here, once, at
/// compute time — the underlying `TrackPoint` data on disk/in Postgres is
/// never touched, only what gets drawn:
///   1. Douglas-Peucker simplification, dropping points that sit within
///      `simplificationToleranceM` of the straight line between their
///      neighbors — this is what actually removes GPS jitter (a live
///      recording can be a couple hundred points over a short stretch,
///      with real device drift between them), while keeping any point that
///      represents a genuine turn or switchback.
///   2. Catmull-Rom spline interpolation through what's left — every
///      surviving point stays exactly on the curve (unlike Bézier
///      smoothing, which can pull the line away from real GPS fixes), with
///      interpolated points filled in between so the result reads as a
///      real curved track instead of straight point-to-point segments.
/// In that order deliberately — simplify first, then curve the survivors;
/// curving before simplifying would just produce a smooth-looking curve
/// that still wiggles through every last bit of raw jitter.
struct MapSegmentStretch: Identifiable {
    /// Deterministic (segment index in the route, not a fresh random UUID
    /// per computation) — `compute` runs independently in a few different
    /// views for the same route (the header preview, the full map, Route
    /// Detail itself), and anything that captures a `MapSegmentStretch.ID`
    /// from one of those (`RouteFullMapView.focusStretchID`) needs it to
    /// still match a stretch computed by a *different* call site, not just
    /// a different call to the same one.
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let tint: Color
    let icon: String
    let label: String
    let midpoint: CLLocationCoordinate2D
    let transport: Transport?
    let distanceKM: Double

    static func compute(trackPoints: [TrackPoint], segments: [RouteDetailInfo.Segment]) -> [MapSegmentStretch] {
        guard trackPoints.count > 1, !segments.isEmpty else { return [] }
        let coords = trackPoints.map(\.coordinate)
        let totalKM = segments.reduce(0) { $0 + $1.distanceKM }

        // Real fix for a real bug: a segment added with a name/transport
        // but no distance (easy to skip — the whole "SEGMENTS" section is
        // labeled "(OPTIONAL)", which reads as "the distance field inside
        // it is optional too") used to zero out `totalKM` for every
        // segment at once, and this function bailed to an empty array the
        // instant that happened. With no stretches, every call site falls
        // back to one single generic-colored line for the *entire* route —
        // not just the blank segment, all of them, with no transport
        // distinction visible anywhere. When nobody filled in a real
        // distance for *any* segment, split the actual trackpoints evenly
        // by count instead of refusing to render segment colors at all —
        // an honest "split evenly since nobody said otherwise" fallback,
        // not a silent failure.
        let useEqualSplit = totalKM <= 0

        let lastIndex = coords.count - 1
        var stretches: [MapSegmentStretch] = []
        var startIdx = 0
        var cumulative: Double = 0

        for (i, seg) in segments.enumerated() {
            cumulative += seg.distanceKM
            let isLast = i == segments.count - 1
            let endIdx: Int
            if isLast {
                endIdx = lastIndex
            } else if useEqualSplit {
                let fraction = Double(i + 1) / Double(segments.count)
                endIdx = max(startIdx + 1, Int((Double(lastIndex) * fraction).rounded()))
            } else {
                endIdx = max(startIdx + 1, Int((Double(lastIndex) * (cumulative / totalKM)).rounded()))
            }
            let clampedEnd = min(endIdx, lastIndex)
            guard clampedEnd > startIdx else { continue }
            let rawSlice = Array(coords[startIdx...clampedEnd])
            let simplified = MapSegmentStretch.simplified(rawSlice)
            let smoothed = MapSegmentStretch.smoothed(simplified)
            stretches.append(MapSegmentStretch(
                id: "\(i)", coordinates: smoothed, tint: seg.tint, icon: seg.icon, label: seg.name,
                midpoint: smoothed[smoothed.count / 2], transport: seg.transport, distanceKM: seg.distanceKM
            ))
            startIdx = clampedEnd
        }
        return stretches
    }

    /// Up to `maxCount` real coordinates along the track, always including
    /// the actual start and end — for handing off to Apple/Google Maps'
    /// own "directions with stops" deep links (`RouteFullMapView`'s "Open
    /// in Maps"). Neither platform's public URL/API can render an
    /// arbitrary custom polyline, only route through a sequence of real
    /// points, so this is the honest maximum approximation of "show the
    /// actual route" those integrations can achieve — real recorded
    /// coordinates, not a routing engine's guess, just fewer of them than
    /// the full track (both platforms cap how many stops a deep link
    /// accepts).
    static func representativeWaypoints(trackPoints: [TrackPoint], maxCount: Int = 8) -> [CLLocationCoordinate2D] {
        let coords = trackPoints.map(\.coordinate)
        guard coords.count > maxCount else { return coords }
        // A looser tolerance than the display pipeline's 3m — this only
        // needs to capture the real shape of the route in a handful of
        // stops, not remove GPS jitter for a smooth curve.
        let candidates = simplified(coords, toleranceMeters: 15)
        guard candidates.count > maxCount else { return candidates }
        let stride = Double(candidates.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { candidates[Int((Double($0) * stride).rounded())] }
    }

    /// Douglas-Peucker line simplification. 3m default tolerance is well
    /// inside typical consumer-GPS jitter (5-10m horizontal accuracy is
    /// normal) but small enough to leave a real trail switchback alone —
    /// a genuine direction change moves the point further than that from
    /// the straight line its neighbors would draw.
    static func simplified(_ points: [CLLocationCoordinate2D], toleranceMeters: Double = 3) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        douglasPeucker(points, 0, points.count - 1, toleranceMeters, &keep)
        return points.indices.compactMap { keep[$0] ? points[$0] : nil }
    }

    private static func douglasPeucker(
        _ points: [CLLocationCoordinate2D], _ start: Int, _ end: Int, _ toleranceMeters: Double, _ keep: inout [Bool]
    ) {
        guard end > start + 1 else { return }
        var maxDistance: Double = 0
        var maxIndex = start
        for i in (start + 1)..<end {
            let d = perpendicularDistanceMeters(points[i], points[start], points[end])
            if d > maxDistance {
                maxDistance = d
                maxIndex = i
            }
        }
        if maxDistance > toleranceMeters {
            keep[maxIndex] = true
            douglasPeucker(points, start, maxIndex, toleranceMeters, &keep)
            douglasPeucker(points, maxIndex, end, toleranceMeters, &keep)
        }
    }

    /// Perpendicular distance in meters from `point` to the infinite line
    /// through `a`→`b` — a flat-earth (equirectangular) projection local to
    /// the two points, accurate at the scale a couple of recorded GPS fixes
    /// actually span.
    private static func perpendicularDistanceMeters(
        _ point: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> Double {
        let latRad = a.latitude * .pi / 180
        let metersPerDegreeLat = 111_320.0
        let metersPerDegreeLon = 111_320.0 * cos(latRad)

        let bx = (b.longitude - a.longitude) * metersPerDegreeLon
        let by = (b.latitude - a.latitude) * metersPerDegreeLat
        let px = (point.longitude - a.longitude) * metersPerDegreeLon
        let py = (point.latitude - a.latitude) * metersPerDegreeLat

        let lineLength = (bx * bx + by * by).squareRoot()
        guard lineLength > 1e-6 else { return (px * px + py * py).squareRoot() }
        return abs(by * px - bx * py) / lineLength
    }

    /// Catmull-Rom spline through the (already-simplified) points — every
    /// surviving point stays exactly on the curve, with interpolated points
    /// filled in between so a sparse recording reads as a real curved track
    /// instead of straight point-to-point segments.
    static func smoothed(_ points: [CLLocationCoordinate2D], samplesPerSegment: Int = 8) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }
        var result: [CLLocationCoordinate2D] = [points[0]]
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            for step in 1...samplesPerSegment {
                let t = Double(step) / Double(samplesPerSegment)
                result.append(catmullRom(p0, p1, p2, p3, t))
            }
        }
        return result
    }

    private static func catmullRom(
        _ p0: CLLocationCoordinate2D, _ p1: CLLocationCoordinate2D, _ p2: CLLocationCoordinate2D, _ p3: CLLocationCoordinate2D, _ t: Double
    ) -> CLLocationCoordinate2D {
        let t2 = t * t, t3 = t2 * t
        func axis(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
            0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        return CLLocationCoordinate2D(
            latitude: axis(p0.latitude, p1.latitude, p2.latitude, p3.latitude),
            longitude: axis(p0.longitude, p1.longitude, p2.longitude, p3.longitude)
        )
    }
}

/// The per-transport dash pattern + whether it gets the subtle "flow"
/// overlay — one real, functional distinction per transport type, not one
/// uniform line for the whole route regardless of what covered it.
/// Dasharray values are in line-width units (Mapbox scales them by the
/// layer's own `lineWidth`), not points.
enum SegmentLineStyle {
    /// `nil` dash = solid.
    static func dashArray(for transport: Transport?) -> [Double]? {
        switch transport {
        case .overland, .bike, nil: return nil
        case .foot: return [2.4, 1.6]
        case .water: return nil // solid base; the animated flow is a separate overlay layer
        case .climb, .paraglide: return [0.2, 1.8] // dotted
        }
    }

    static func hasFlowOverlay(_ transport: Transport?) -> Bool { transport == .water }
}

/// Real, cheap "flow" animation for water segments — cycles a short dash
/// pattern's phase every half-second via a discrete step count (not a
/// per-frame timer), so it reads as moving water without costing real
/// frame budget. Mapbox's `line-dasharray` has no separate phase/offset
/// property, so the phase is faked by shifting how much of the first dash
/// is "already drawn" across four fixed patterns that sum to the same
/// period.
enum FlowPhase {
    static let period: TimeInterval = 0.5
    static let patternCount = 4

    /// `[dash, gap, dash, gap, …]`, Mapbox/SVG convention — always starts
    /// with a drawn segment. A near-invisible leading dash (`0.05`, not
    /// literally 0) followed by a `gap` of `offset` pushes where the real
    /// visible dash starts; cycling `offset` through the four steps is what
    /// reads as the highlight sliding along the line each half-second.
    static func dashArray(step: Int) -> [Double] {
        let dash = 0.8, gap = 3.2, period = dash + gap
        let offset = period * Double(step % patternCount) / Double(patternCount)
        return [0.05, offset, dash, gap]
    }
}

/// The "what transport, here" label along a segment's stretch of the real
/// map — icon + a short piece of its name, styled to read clearly against
/// a light street map (à la Apple/Google Maps' inline route chips).
struct SegmentLabelChip: View {
    let icon: String
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(label)
                .font(NTFont.mono(9.5, .semibold))
                .tracking(0.2)
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(Capsule().fill(tint))
        .overlay(Capsule().stroke(.white, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
        .fixedSize()
    }
}

/// Marks a real changeover — the point where the route switches from one
/// transport type to another (foot → overland, overland → water, …). A
/// distinct elevated marker, not the generic waypoint pin, so a transition
/// reads as its own checkpoint rather than just another dot on the line.
struct TransitionMarker: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().fill(tint).padding(4)
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
    }
}

/// A user-dropped point-of-interest pin on the real map — round, colored by
/// category, tappable to reveal its title/note.
struct POIMapMarker: View {
    let category: POICategory

    var body: some View {
        ZStack {
            Circle().fill(category.tint)
            Image(systemName: category.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

/// A real cluster of geotagged photos (`RouteRepository.RoutePhoto.lat/lng`
/// — only ever real when taken mid-recording, see that struct's own doc
/// comment) that happened to be taken near the same spot — one pin per
/// cluster rather than one per photo, since several shots at the same
/// viewpoint are the common case and a pile of overlapping pins at one
/// spot would be worse than one. Distinct on purpose from `POIMapMarker`
/// (the author's own placed pins): this is "people actually stood here and
/// took a real photo," not an annotation — so the pin IS the photo, not an
/// icon describing one.
struct PhotoSpot: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let photos: [RouteRepository.RoutePhoto]

    /// Groups photos with real coordinates within `radiusM` of each other
    /// — simple greedy clustering (first photo seeds a cluster, anything
    /// close enough joins it), good enough for the handful of geotagged
    /// photos a single route realistically has. Photos with no real
    /// lat/lng (the after-the-fact library-upload path) are excluded
    /// entirely rather than placed at a fake/default coordinate.
    static func cluster(_ photos: [RouteRepository.RoutePhoto], radiusM: CLLocationDistance = 40) -> [PhotoSpot] {
        var remaining = photos.compactMap { photo -> (photo: RouteRepository.RoutePhoto, coordinate: CLLocationCoordinate2D)? in
            guard let lat = photo.lat, let lng = photo.lng else { return nil }
            return (photo, CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        var spots: [PhotoSpot] = []
        while let seed = remaining.first {
            let seedLocation = CLLocation(latitude: seed.coordinate.latitude, longitude: seed.coordinate.longitude)
            var clustered: [RouteRepository.RoutePhoto] = []
            remaining.removeAll { entry in
                let distance = seedLocation.distance(from: CLLocation(latitude: entry.coordinate.latitude, longitude: entry.coordinate.longitude))
                guard distance <= radiusM else { return false }
                clustered.append(entry.photo)
                return true
            }
            spots.append(PhotoSpot(coordinate: seed.coordinate, photos: clustered))
        }
        return spots
    }
}

/// The pin itself — a real circular thumbnail of the cluster's first photo
/// (not a generic camera glyph), a small camera badge so it still reads as
/// "photo" at a glance, and a count badge when more than one photo was
/// taken here.
struct PhotoSpotMapMarker: View {
    let spot: PhotoSpot

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AsyncImage(url: URL(string: spot.photos.first?.imageUrl ?? "")) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(NTColor.milk(0.15))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)

            ZStack {
                Circle().fill(NTColor.accent)
                Image(systemName: "camera.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(Color(hex: 0x231007))
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.white, lineWidth: 1.5))

            if spot.photos.count > 1 {
                Text("\(spot.photos.count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 17, height: 17)
                    .background(Circle().fill(Color(hex: 0x1A0A07)))
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                    .offset(x: 4, y: -28)
            }
        }
    }
}

/// Shared per-segment map rendering — casing, transport-styled colored
/// line, the animated water-flow overlay, label chips, and transition
/// markers at every real changeover. One implementation, reused by both
/// the Route Detail header preview and the full interactive map, so a
/// route's segments always render identically in both places.
///
/// Runs on the raw `LineLayer`/`GeoJSONSource` style API rather than the
/// simpler `PolylineAnnotation` convenience wrapper — that wrapper has no
/// dasharray support at all, and `LineLayer` gets real casing for free via
/// `lineBorderColor`/`lineBorderWidth` on a single layer instead of a
/// second white polyline stacked underneath.
struct RouteSegmentMapContent: MapContent {
    let stretches: [MapSegmentStretch]
    /// Discrete tick count driving `FlowPhase` — bump roughly twice a
    /// second from a `TimelineView` for the water "flow" to read as moving.
    var flowStep: Int = 0
    var showLabels: Bool = true

    var body: some MapContent {
        ForEvery(stretches) { stretch in
            let sourceId = "route-seg-\(stretch.id)"
            GeoJSONSource(id: sourceId)
                .data(.geometry(.lineString(LineString(stretch.coordinates))))

            LineLayer(id: "\(sourceId)-line", source: sourceId)
                .lineColor(UIColor(stretch.tint))
                .lineOpacity(1)
                .lineWidth(9)
                .lineCap(.round)
                .lineJoin(.round)
                .lineBorderColor(UIColor.black.withAlphaComponent(0.35))
                .lineBorderWidth(2)
                .applyingDashArray(SegmentLineStyle.dashArray(for: stretch.transport))

            if SegmentLineStyle.hasFlowOverlay(stretch.transport) {
                LineLayer(id: "\(sourceId)-flow", source: sourceId)
                    .lineColor(.white)
                    .lineOpacity(0.65)
                    .lineWidth(3.2)
                    .lineCap(.round)
                    .lineDashArray(FlowPhase.dashArray(step: flowStep))
            }
        }

        if showLabels {
            ForEvery(stretches) { stretch in
                MapViewAnnotation(coordinate: stretch.midpoint) {
                    SegmentLabelChip(icon: stretch.icon, label: stretch.label, tint: stretch.tint)
                }
            }
        }

        // A marker at every real changeover — the start of any stretch
        // whose transport differs from the one before it (or the very
        // first stretch, since the route itself starts with *some*
        // transport). Skips stretches with an unrecognized icon (`nil`
        // transport) rather than guessing.
        ForEvery(Array(stretches.enumerated()), id: \.offset) { i, stretch in
            if let transport = stretch.transport, let first = stretch.coordinates.first,
               i == 0 || stretches[i - 1].transport != transport {
                MapViewAnnotation(coordinate: first) {
                    TransitionMarker(icon: transport.icon, tint: stretch.tint)
                }
            }
        }
    }
}

private extension LineLayer {
    func applyingDashArray(_ pattern: [Double]?) -> LineLayer {
        guard let pattern else { return self }
        return lineDashArray(pattern)
    }
}

extension Viewport {
    /// Fits the given coordinates with padding — a single point gets a
    /// fixed close-in camera (an "overview" of one point is meaningless),
    /// several points auto-fit via Mapbox's own bounding-box math. Shared
    /// by the map header's first-appearance fly-in, the full map's initial
    /// framing, and the itinerary panel's "focus this leg" tap.
    static func fitting(_ coordinates: [CLLocationCoordinate2D], padding: SwiftUI.EdgeInsets) -> Viewport {
        guard let first = coordinates.first else { return .styleDefault }
        guard coordinates.count > 1 else { return .camera(center: first, zoom: 13) }
        return .overview(geometry: Geometry.lineString(LineString(coordinates)), geometryPadding: padding)
    }
}

import SwiftUI
import CoreLocation

/// One colored, labeled stretch of a route's polyline — the real recorded
/// track split proportionally by each segment's logged distance (there's no
/// exact GPS boundary between segments, only their order and length, so
/// this is the honest approximation of "which piece of the path used which
/// transport"). Shared by the Route Detail header preview and the
/// full-screen interactive map so both agree on the same split.
struct MapSegmentStretch: Identifiable {
    let id = UUID()
    let coordinates: [CLLocationCoordinate2D]
    let tint: Color
    let icon: String
    let label: String
    let midpoint: CLLocationCoordinate2D

    static func compute(trackPoints: [TrackPoint], segments: [RouteDetailInfo.Segment]) -> [MapSegmentStretch] {
        guard trackPoints.count > 1, !segments.isEmpty else { return [] }
        let coords = trackPoints.map(\.coordinate)
        let totalKM = segments.reduce(0) { $0 + $1.distanceKM }
        guard totalKM > 0 else { return [] }

        let lastIndex = coords.count - 1
        var stretches: [MapSegmentStretch] = []
        var startIdx = 0
        var cumulative: Double = 0

        for (i, seg) in segments.enumerated() {
            cumulative += seg.distanceKM
            let isLast = i == segments.count - 1
            let endIdx = isLast
                ? lastIndex
                : max(startIdx + 1, Int((Double(lastIndex) * (cumulative / totalKM)).rounded()))
            let clampedEnd = min(endIdx, lastIndex)
            guard clampedEnd > startIdx else { continue }
            let slice = Array(coords[startIdx...clampedEnd])
            stretches.append(MapSegmentStretch(
                coordinates: slice, tint: seg.tint, icon: seg.icon, label: seg.name, midpoint: slice[slice.count / 2]
            ))
            startIdx = clampedEnd
        }
        return stretches
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

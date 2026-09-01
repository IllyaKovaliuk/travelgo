import SwiftUI
import MapKit
import CoreLocation

/// The "map" at the top of Route Detail. Any route with at least one real
/// coordinate (`trackPoints`) gets an actual MapKit map — a full polyline
/// for a real recording, or just a centered pin for routes that only have
/// a single reference point. Only routes with zero coordinates at all
/// (shouldn't normally happen once publish always records a track, but
/// guards against edge cases) fall back to the hand-drawn stand-in.
struct RouteMapHeader: View {
    let segments: [RouteDetailInfo.Segment]
    var trackPoints: [TrackPoint] = []
    var pois: [RouteDetailInfo.POI] = []
    /// A pre-rendered snapshot from `OfflineRouteStore` — shown instead of a
    /// live `Map` when present, since a live map still needs network for
    /// tiles even with the real coordinates already on hand.
    var cachedSnapshot: UIImage? = nil
    var onBack: () -> Void
    /// Tapping the map (anywhere but the back button) opens the real
    /// full-screen, pannable/zoomable map — this header is a preview, not
    /// the actual navigable map.
    var onOpenFullMap: (() -> Void)? = nil

    var body: some View {
        ZStack {
            if let cachedSnapshot {
                Image(uiImage: cachedSnapshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
            } else if !trackPoints.isEmpty {
                realMap
            } else {
                terrain
                routeLine
                pins
            }

            LinearGradient(colors: [NTColor.pineDeep.opacity(0.85), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 130)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)

            VStack {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(NTColor.milk)
                            .frame(width: 42, height: 42)
                            .background(Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                            .background(Circle().fill(NTColor.milk(0.1)))
                            .overlay(Circle().stroke(NTColor.milk(0.26), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text(cachedSnapshot != nil ? "SAVED OFFLINE" : (trackPoints.count > 1 ? "LIVE GPS TRACK" : (trackPoints.isEmpty ? "MAP RENDERED WITH REAL GEODATA" : "APPROXIMATE LOCATION")))
                        .font(NTFont.mono(9.5, .medium))
                        .tracking(0.6)
                        .foregroundStyle(NTColor.milk)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                        .background(Capsule().fill(NTColor.milk(0.1)))
                        .overlay(Capsule().stroke(NTColor.milk(0.26), lineWidth: 1))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            if onOpenFullMap != nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                            Text("OPEN MAP")
                        }
                        .font(NTFont.mono(9.5, .semibold)).tracking(0.5)
                        .foregroundStyle(NTColor.milk)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(.ultraThinMaterial).environment(\.colorScheme, .dark))
                        .background(Capsule().fill(NTColor.milk(0.1)))
                        .overlay(Capsule().stroke(NTColor.milk(0.26), lineWidth: 1))
                    }
                }
                .padding(16)
            }
        }
        .frame(height: 330)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { onOpenFullMap?() }
    }

    private var segmentStretches: [MapSegmentStretch] {
        MapSegmentStretch.compute(trackPoints: trackPoints, segments: segments)
    }

    private var realMap: some View {
        Map(initialPosition: .region(trackRegion)) {
            if !segmentStretches.isEmpty {
                // White casing under every stretch first, so the colored
                // line reads clearly against any terrain color underneath
                // (green segment over green forest was invisible without it).
                ForEach(segmentStretches) { stretch in
                    MapPolyline(coordinates: stretch.coordinates)
                        .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                }
                // One colored stretch per segment, so it's clear at a glance
                // which transport covers which piece of the route — not
                // just a single flat line.
                ForEach(segmentStretches) { stretch in
                    MapPolyline(coordinates: stretch.coordinates)
                        .stroke(stretch.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                ForEach(segmentStretches) { stretch in
                    Annotation("", coordinate: stretch.midpoint) {
                        SegmentLabelChip(icon: stretch.icon, label: stretch.label, tint: stretch.tint)
                    }
                }
            } else if trackPoints.count > 1 {
                MapPolyline(coordinates: trackPoints.map(\.coordinate))
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: trackPoints.map(\.coordinate))
                    .stroke(NTColor.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if trackPoints.count > 1 {
                if let start = trackPoints.first {
                    Annotation("", coordinate: start.coordinate) {
                        MapPin(icon: "flag.fill", tint: NTColor.sage)
                    }
                }
                if let end = trackPoints.last {
                    Annotation("", coordinate: end.coordinate) {
                        MapPin(icon: "flag.checkered", tint: NTColor.pine, iconColor: NTColor.milk)
                    }
                }
            } else if let only = trackPoints.first {
                Annotation("", coordinate: only.coordinate) {
                    MapPin(icon: "flag.fill", tint: NTColor.pine, iconColor: NTColor.milk)
                }
            }

            ForEach(pois) { poi in
                Annotation("", coordinate: poi.coordinate) {
                    POIMapMarker(category: poi.category)
                }
            }
        }
        // Satellite (not vector "standard") — remote trails/backcountry
        // routes mostly have no road data in Apple's vector map, which
        // rendered as a flat color wash with no visible terrain at all.
        // Real satellite imagery shows the actual land regardless.
        .mapStyle(.hybrid(elevation: .realistic))
        .allowsHitTesting(false) // header preview only — not for interactive panning inside a ScrollView
    }

    /// A region that frames the whole recorded track with a little breathing room.
    private var trackRegion: MKCoordinateRegion {
        let lats = trackPoints.map(\.lat)
        let lngs = trackPoints.map(\.lng)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.5, 0.01),
            longitudeDelta: max((maxLng - minLng) * 1.5, 0.01)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var terrain: some View {
        ZStack {
            NTColor.pineShadow
            OrganicBlob((0.15, 0.55, 0.3, 0.1), (0.1, 0.2, 0.7, 0.5))
                .fill(NTColor.pineLine)
                .frame(width: 460, height: 340)
                .position(x: 120, y: 60)
            OrganicBlob((0.4, 0.2, 0.35, 0.5), (0.4, 0.1, 0.55, 0.35))
                .fill(NTColor.pineRaised.opacity(0.75))
                .frame(width: 420, height: 300)
                .position(x: 300, y: 190)
        }
    }

    private var routeLine: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Path { p in
                p.move(to: CGPoint(x: w * 0.12, y: 285))
                p.addCurve(
                    to: CGPoint(x: w * 0.55, y: 150),
                    control1: CGPoint(x: w * 0.28, y: 230),
                    control2: CGPoint(x: w * 0.4, y: 190)
                )
                p.addCurve(
                    to: CGPoint(x: w * 0.86, y: 100),
                    control1: CGPoint(x: w * 0.68, y: 118),
                    control2: CGPoint(x: w * 0.76, y: 108)
                )
            }
            .stroke(NTColor.milk(0.85), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            .shadow(color: .black.opacity(0.3), radius: 3)
        }
    }

    private var pins: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let spots: [CGPoint] = [
                CGPoint(x: w * 0.12, y: 268),
                CGPoint(x: w * 0.55, y: 133),
                CGPoint(x: w * 0.72, y: 108)
            ]
            ZStack {
                ForEach(Array(segments.prefix(3).enumerated()), id: \.offset) { i, seg in
                    MapPin(icon: seg.icon, tint: seg.tint)
                        .position(spots[i])
                }
                if segments.count > 1 {
                    POIPin(icon: "house.fill")
                        .position(x: w * 0.3, y: 235)
                }
                MapPin(icon: "flag.fill", tint: NTColor.milk, iconColor: NTColor.pine)
                    .position(x: w * 0.86, y: 83)
            }
        }
    }
}

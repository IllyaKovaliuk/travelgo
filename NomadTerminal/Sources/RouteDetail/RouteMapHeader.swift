import SwiftUI
import MapboxMaps
import Turf
import CoreLocation

/// The "map" at the top of Route Detail. Any route with at least one real
/// coordinate (`trackPoints`) gets an actual Mapbox map — a full polyline
/// for a real recording, or just a centered pin for routes that only have
/// a single reference point. Only routes with zero coordinates at all
/// (shouldn't normally happen once publish always records a track, but
/// guards against edge cases) fall back to the hand-drawn stand-in.
///
/// Runs on Mapbox (Standard Satellite — real 3D terrain + satellite
/// imagery) instead of MapKit: unlike MapKit's `.hybrid(elevation:
/// .realistic)`, Mapbox's view annotations are documented to always render
/// above the terrain mesh, so there's no need for the `.flat`-elevation
/// workaround the old MapKit version needed to keep pins visible.
///
/// `viewport` is a live binding, not a one-shot initial camera — on first
/// appearance this flies the camera in from a wide establishing shot to
/// the real route bounds (a "flyover," not a hard cut), and afterwards the
/// itinerary panel below can drive the same binding to reframe on just one
/// leg when a row is tapped, so the map and the list stay one connected
/// experience instead of two disconnected pieces.
struct RouteMapHeader: View {
    let segments: [RouteDetailInfo.Segment]
    var trackPoints: [TrackPoint] = []
    var pois: [RouteDetailInfo.POI] = []
    /// A pre-rendered snapshot from `OfflineRouteStore` — shown instead of a
    /// live `Map` when present, since a live map still needs network for
    /// tiles even with the real coordinates already on hand.
    var cachedSnapshot: UIImage? = nil
    @Binding var viewport: Viewport
    var onBack: () -> Void
    /// Tapping the map (anywhere but the back button) opens the real
    /// full-screen, pannable/zoomable map — this header is a preview, not
    /// the actual navigable map.
    var onOpenFullMap: (() -> Void)? = nil

    @State private var hasFlownIn = false
    @State private var flowStep = 0

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

    /// Deliberately a computed property, not something cached in `@State`
    /// at init — `segments`/`trackPoints` are plain `var`/`let` props fed
    /// from `RouteDetailView`'s own `route`, which really does mutate after
    /// a real edit (`EditRouteExtrasView`'s `route = updated`); this view's
    /// identity persists across that (SwiftUI updates the props in place,
    /// it doesn't reconstruct the view), so anything cached only at init
    /// would silently go stale the moment segments actually change. The
    /// Douglas-Peucker + Catmull-Rom pass itself is cheap at this app's
    /// real point counts — correctness here matters more than the redundant
    /// recompute across the couple of places this gets read per render.
    private var segmentStretches: [MapSegmentStretch] {
        MapSegmentStretch.compute(trackPoints: trackPoints, segments: segments)
    }

    private var fullRouteTarget: Viewport {
        .fitting(trackPoints.map(\.coordinate), padding: EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40))
    }

    private var realMap: some View {
        Map(viewport: $viewport) {
            if !segmentStretches.isEmpty {
                RouteSegmentMapContent(stretches: segmentStretches, flowStep: flowStep)
            } else if trackPoints.count > 1 {
                let sourceId = "route-plain"
                GeoJSONSource(id: sourceId).data(.geometry(.lineString(LineString(trackPoints.map(\.coordinate)))))
                LineLayer(id: "\(sourceId)-line", source: sourceId)
                    .lineColor(UIColor(NTColor.accent))
                    .lineWidth(9)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineBorderColor(UIColor.black.withAlphaComponent(0.4))
                    .lineBorderWidth(2)
            }

            if trackPoints.count > 1 {
                if let start = trackPoints.first {
                    MapViewAnnotation(coordinate: start.coordinate) {
                        MapPin(icon: "flag.fill", tint: NTColor.sage)
                    }
                }
                if let end = trackPoints.last {
                    MapViewAnnotation(coordinate: end.coordinate) {
                        MapPin(icon: "flag.checkered", tint: NTColor.pine, iconColor: NTColor.milk)
                    }
                }
            } else if let only = trackPoints.first {
                MapViewAnnotation(coordinate: only.coordinate) {
                    MapPin(icon: "flag.fill", tint: NTColor.pine, iconColor: NTColor.milk)
                }
            }

            ForEvery(pois) { poi in
                MapViewAnnotation(coordinate: poi.coordinate) {
                    POIMapMarker(category: poi.category)
                }
            }
        }
        .mapStyle(NomadMap.style(satellite: false))
        .allowsHitTesting(false) // header preview only — not for interactive panning inside a ScrollView
        .task {
            // Flyover on first appearance, not a hard cut — starts from
            // whatever `viewport` the parent initialized (a wide,
            // establishing-shot default) and eases the camera in to the
            // route's real bounds.
            guard !hasFlownIn else { return }
            hasFlownIn = true
            let target = fullRouteTarget
            try? await Task.sleep(nanoseconds: 150_000_000) // lets the style finish its own initial load first
            withViewportAnimation(.fly(duration: 1.6)) { viewport = target }
        }
        .task {
            guard segmentStretches.contains(where: { $0.transport == .water }) else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(FlowPhase.period * 1_000_000_000))
                flowStep += 1
            }
        }
    }

    private var terrain: some View {
        ZStack {
            NTColor.pineShadow
            // Flat ground + a faint straight-line contour pattern instead of
            // the old soft organic blobs — still reads as "terrain," just
            // without the decorative shapes that don't belong in this
            // aesthetic anymore.
            TopoLines(lineCount: 6, spacing: 26)
                .stroke(NTColor.pineLine, lineWidth: 1)
                .opacity(0.5)
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

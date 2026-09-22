import SwiftUI
import MapboxMaps
import Turf
import MapKit
import CoreLocation

/// The real map — pannable, zoomable, tappable pins. What the small header
/// in Route Detail is a preview *of*. Segment-colored polyline, every
/// point-of-interest pin the author dropped, and a real "Open in Maps"
/// hand-off to Apple Maps for turn-by-turn to the trailhead (Apple Maps
/// can't render a third-party app's custom multi-point route, so that's
/// the honest limit of what deep-linking out can do — the rest of this
/// screen is where the real route lives). Rendering itself is Mapbox
/// (Standard Satellite — real 3D terrain + satellite, real photo pins);
/// `MapKit` is still imported here purely for the "Open in Maps" deep link
/// (`MKMapItem`), not for drawing anything.
struct RouteFullMapView: View {
    let route: Route
    var onClose: () -> Void
    /// Focuses this one segment on open, when arriving from an itinerary
    /// row tap rather than the map header — the full map still shows every
    /// segment, just framed to the one the user tapped into.
    var focusStretchID: MapSegmentStretch.ID? = nil

    @State private var selectedPOI: RouteDetailInfo.POI?
    @State private var showSatellite = true
    @State private var viewport: Viewport
    @State private var hasFlownIn = false
    @State private var flowStep = 0

    init(route: Route, onClose: @escaping () -> Void, focusStretchID: MapSegmentStretch.ID? = nil) {
        self.route = route
        self.onClose = onClose
        self.focusStretchID = focusStretchID
        _viewport = State(initialValue: .styleDefault)
    }

    // `MapKit` and `MapboxMaps` both declare a `MapStyle` type — imported
    // together here since MapKit is still needed for the Open in Maps deep
    // link — so this must be qualified.
    private var mapStyle: MapboxMaps.MapStyle {
        showSatellite ? .standardSatellite : .standard
    }

    private var trackPoints: [TrackPoint] { route.detail.trackPoints }
    private var pois: [RouteDetailInfo.POI] { route.detail.pois }
    private var segmentStretches: [MapSegmentStretch] {
        MapSegmentStretch.compute(trackPoints: trackPoints, segments: route.detail.segments)
    }

    private var fullRouteTarget: Viewport {
        .fitting(trackPoints.map(\.coordinate) + pois.map(\.coordinate), padding: EdgeInsets(top: 60, leading: 40, bottom: 60, trailing: 40))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(viewport: $viewport) {
                if !segmentStretches.isEmpty {
                    RouteSegmentMapContent(stretches: segmentStretches, flowStep: flowStep)
                } else if trackPoints.count > 1 {
                    let sourceId = "route-plain-full"
                    GeoJSONSource(id: sourceId).data(.geometry(.lineString(LineString(trackPoints.map(\.coordinate)))))
                    LineLayer(id: "\(sourceId)-line", source: sourceId)
                        .lineColor(UIColor(NTColor.accent))
                        .lineWidth(7.5)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .lineBorderColor(UIColor.black.withAlphaComponent(0.4))
                        .lineBorderWidth(1.6)
                }

                if trackPoints.count > 1 {
                    if let start = trackPoints.first {
                        MapViewAnnotation(coordinate: start.coordinate) { MapPin(icon: "flag.fill", tint: NTColor.sage) }
                    }
                    if let end = trackPoints.last {
                        MapViewAnnotation(coordinate: end.coordinate) { MapPin(icon: "flag.checkered", tint: NTColor.pine, iconColor: NTColor.milk) }
                    }
                } else if let only = trackPoints.first {
                    MapViewAnnotation(coordinate: only.coordinate) { MapPin(icon: "flag.fill", tint: NTColor.pine, iconColor: NTColor.milk) }
                }

                ForEvery(pois) { poi in
                    MapViewAnnotation(coordinate: poi.coordinate) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(NTMotion.spring) { selectedPOI = poi }
                        } label: {
                            POIMapMarker(category: poi.category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(mapStyle)
            .ignoresSafeArea()
            .task {
                guard !hasFlownIn else { return }
                hasFlownIn = true
                let target = focusTarget ?? fullRouteTarget
                try? await Task.sleep(nanoseconds: 150_000_000)
                withViewportAnimation(.fly(duration: 1.6)) { viewport = target }
            }
            .task {
                guard segmentStretches.contains(where: { $0.transport == .water }) else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: UInt64(FlowPhase.period * 1_000_000_000))
                    flowStep += 1
                }
            }

            VStack {
                topBar
                Spacer()
                if let selectedPOI {
                    poiCard(selectedPOI)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .foregroundStyle(NTColor.milk)
    }

    private var focusTarget: Viewport? {
        guard let focusStretchID, let stretch = segmentStretches.first(where: { $0.id == focusStretchID }) else { return nil }
        return .fitting(stretch.coordinates, padding: EdgeInsets(top: 100, leading: 60, bottom: 200, trailing: 60))
    }

    private var topBar: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NTColor.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSatellite.toggle()
            } label: {
                Image(systemName: showSatellite ? "map.fill" : "globe.americas.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NTColor.ink)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.leading, 10)

            Spacer()

            if let start = trackPoints.first {
                Button {
                    openInAppleMaps(coordinate: start.coordinate, name: route.title.replacingOccurrences(of: "\n", with: " "))
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        Text("Open in Maps")
                    }
                    .font(NTFont.body(13.5, .semibold))
                    .foregroundStyle(NTColor.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 42)
                    .background(Capsule().fill(.white))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func poiCard(_ poi: RouteDetailInfo.POI) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(poi.category.tint)
                Image(systemName: poi.category.icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(poi.title).font(NTFont.body(15, .semibold)).foregroundStyle(NTColor.milk)
                Text(poi.category.label).font(NTFont.mono(10, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.55))
                if let note = poi.note, !note.isEmpty {
                    Text(note)
                        .font(NTFont.body(12.5, .light))
                        .foregroundStyle(NTColor.milk(0.75))
                        .padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(NTMotion.spring) { selectedPOI = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NTColor.milk(0.6))
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(NTColor.milk(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(NTColor.pineDeep, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

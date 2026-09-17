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

    @State private var selectedPOI: RouteDetailInfo.POI?
    @State private var showSatellite = true
    @State private var viewport: Viewport

    init(route: Route, onClose: @escaping () -> Void) {
        self.route = route
        self.onClose = onClose
        let coords = route.detail.trackPoints.map(\.coordinate) + route.detail.pois.map(\.coordinate)
        if coords.count > 1 {
            _viewport = State(initialValue: .overview(
                geometry: Geometry.lineString(LineString(coords)),
                geometryPadding: EdgeInsets(top: 60, leading: 40, bottom: 60, trailing: 40)
            ))
        } else {
            _viewport = State(initialValue: .camera(center: coords.first, zoom: 13))
        }
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

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(viewport: $viewport) {
                if !segmentStretches.isEmpty {
                    // White casing first so the colored line reads against any
                    // terrain color underneath (satellite forest is often green,
                    // same as the "foot" segment tint, otherwise invisible).
                    ForEvery(segmentStretches) { stretch in
                        PolylineAnnotation(lineCoordinates: stretch.coordinates)
                            .lineColor(.white)
                            .lineWidth(8.5)
                            .lineJoin(.round)
                    }
                    ForEvery(segmentStretches) { stretch in
                        PolylineAnnotation(lineCoordinates: stretch.coordinates)
                            .lineColor(UIColor(stretch.tint))
                            .lineWidth(5.5)
                            .lineJoin(.round)
                    }
                    ForEvery(segmentStretches) { stretch in
                        MapViewAnnotation(coordinate: stretch.midpoint) {
                            SegmentLabelChip(icon: stretch.icon, label: stretch.label, tint: stretch.tint)
                        }
                    }
                } else if trackPoints.count > 1 {
                    PolylineAnnotation(lineCoordinates: trackPoints.map(\.coordinate))
                        .lineColor(.white)
                        .lineWidth(8.5)
                        .lineJoin(.round)
                    PolylineAnnotation(lineCoordinates: trackPoints.map(\.coordinate))
                        .lineColor(UIColor(NTColor.accent))
                        .lineWidth(5.5)
                        .lineJoin(.round)
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedPOI = poi }
                        } label: {
                            POIMapMarker(category: poi.category)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(mapStyle)
            .ignoresSafeArea()

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
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { selectedPOI = nil }
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
        .background(NTColor.pineDeep, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    private func openInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

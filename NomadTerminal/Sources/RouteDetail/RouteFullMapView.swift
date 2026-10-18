import SwiftUI
import MapboxMaps
import Turf
import MapKit
import CoreLocation

/// The real map — pannable, zoomable, tappable pins. What the small header
/// in Route Detail is a preview *of*. Segment-colored polyline, every
/// point-of-interest pin the author dropped, and a real "Open in Maps"
/// hand-off to Apple Maps *or* Google Maps showing the route's own real
/// start through its own real end (via a handful of real waypoints along
/// the way — `MapSegmentStretch.representativeWaypoints`), not directions
/// from wherever the user currently is to just the trailhead. Neither
/// platform's public deep link can render an arbitrary custom polyline —
/// they still calculate their own road routing *between* each stop — so
/// this is the honest limit of what deep-linking out can do; the rest of
/// this screen is where the exact real route lives. Rendering itself is
/// Mapbox (Standard Satellite — real 3D terrain + satellite, real photo
/// pins); `MapKit` is still imported here purely for the Apple Maps hand-
/// off (`MKMapItem`), not for drawing anything.
struct RouteFullMapView: View {
    let route: Route
    var onClose: () -> Void
    /// Focuses this one segment on open, when arriving from an itinerary
    /// row tap rather than the map header — the full map still shows every
    /// segment, just framed to the one the user tapped into.
    var focusStretchID: MapSegmentStretch.ID? = nil

    @State private var selectedPOI: RouteDetailInfo.POI?
    @State private var hazardStore = HazardStore()
    /// Pro: Meteo-Terminal (route weather timeline, storm zones, radar).
    @State private var meteo: MeteoViewModel?
    @State private var showPaywall = false
    @State private var showSatellite = false
    @State private var viewport: Viewport
    @State private var hasFlownIn = false
    @State private var flowStep = 0
    /// Real geotagged photos on this route (`RouteRepository.fetchPhotos`,
    /// the same data `RoutePhotosSection` shows as a horizontal strip) —
    /// fetched independently here since this map and that section are
    /// sibling views with no shared state. Clustered into `photoSpots` and
    /// drawn as their own pin type, distinct from the author's placed POIs.
    @State private var photos: [RouteRepository.RoutePhoto] = []
    @State private var currentUserId: String?
    @State private var photoViewerSpot: PhotoSpot?
    /// Computed once (init), not a plain computed property — this file
    /// reads `segmentStretches` from three different spots in one body
    /// pass (the map content, the water-flow `.task` guard, `focusTarget`),
    /// and a computed property would silently redo the full Douglas-Peucker
    /// + Catmull-Rom pipeline every single one of those, on every render.
    @State private var segmentStretches: [MapSegmentStretch]

    init(route: Route, onClose: @escaping () -> Void, focusStretchID: MapSegmentStretch.ID? = nil) {
        self.route = route
        self.onClose = onClose
        self.focusStretchID = focusStretchID
        _viewport = State(initialValue: .styleDefault)
        _segmentStretches = State(initialValue: MapSegmentStretch.compute(trackPoints: route.detail.trackPoints, segments: route.detail.segments))
    }

    // `MapKit` and `MapboxMaps` both declare a `MapStyle` type — imported
    // together here since MapKit is still needed for the Open in Maps deep
    // link — so this must be qualified.
    private var mapStyle: MapboxMaps.MapStyle {
        NomadMap.style(satellite: showSatellite)
    }

    private var trackPoints: [TrackPoint] { route.detail.trackPoints }
    private var pois: [RouteDetailInfo.POI] { route.detail.pois }
    /// Real recorded coordinates along the actual track (start through
    /// end), not "from wherever I'm standing to the trailhead" — Apple/
    /// Google Maps' own directions-with-stops still calculate their own
    /// road routing *between* each of these, so this can't render the
    /// exact off-road polyline shape (neither platform's public deep link
    /// can, at all), but it's the real route's own real shape, not a
    /// detour through the user's current location.
    private var routeWaypoints: [CLLocationCoordinate2D] {
        MapSegmentStretch.representativeWaypoints(trackPoints: trackPoints)
    }

    private var fullRouteTarget: Viewport {
        .fitting(trackPoints.map(\.coordinate) + pois.map(\.coordinate), padding: EdgeInsets(top: 60, leading: 40, bottom: 60, trailing: 40))
    }

    private var photoSpots: [PhotoSpot] { PhotoSpot.cluster(photos) }

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
                        .lineWidth(9)
                        .lineCap(.round)
                        .lineJoin(.round)
                        .lineBorderColor(UIColor.white.withAlphaComponent(0.95))
                        .lineBorderWidth(2)
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

                CommunityMapContent(
                    hazards: hazardStore.hazards, partners: [],
                    onHazard: { h in withAnimation(NTMotion.spring) { selectedPOI = nil; hazardStore.selectedHazard = h } },
                    onPartner: { _ in }
                )

                if let meteo {
                    MeteoMapContent(
                        riskySegments: meteo.segments.filter { $0.risk != .clear },
                        radarFrames: meteo.radarFrames,
                        radarIndex: meteo.radarIndex,
                        radarEnabled: meteo.radarEnabled,
                        scrubCoordinate: meteo.scrubCoordinate,
                        scrubRisk: meteo.currentWeather?.risk ?? .clear
                    )
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

                // Real photo pins — "people actually stood here," distinct
                // from the author's own placed POIs above. Drawn after
                // them so a photo pin never sits visually under a POI pin
                // at a near-identical spot.
                ForEvery(photoSpots) { spot in
                    MapViewAnnotation(coordinate: spot.coordinate) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            photoViewerSpot = spot
                        } label: {
                            PhotoSpotMapMarker(spot: spot)
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
            .task { await hazardStore.loadAlongRoute(trackPoints) }
            .task(id: meteo != nil) {
                // Radar loop: step frames while Meteo-Terminal is open.
                while meteo != nil && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    meteo?.advanceRadar()
                }
            }
            .task {
                photos = (try? await RouteRepository.shared.fetchPhotos(routeId: route.id)) ?? []
                currentUserId = (try? await supabase.auth.session)?.user.id.uuidString
            }

            VStack {
                topBar
                if let meteo {
                    HStack {
                        MeteoHUDWidget(
                            weather: meteo.currentWeather,
                            radarEnabled: meteo.radarEnabled,
                            radarFailed: meteo.radarFailed,
                            radarSyncedAt: meteo.radarSyncedAt,
                            radarFrameTime: meteo.radarFrames.indices.contains(meteo.radarIndex) ? meteo.radarFrames[meteo.radarIndex].time : nil,
                            isLoading: meteo.isLoading
                        )
                        Spacer()
                    }
                    .padding(.horizontal, 16).padding(.top, 6)
                    .transition(.opacity)
                }
                Spacer()
                if let hazard = hazardStore.selectedHazard {
                    HazardDetailCard(
                        hazard: hazard, showsVoting: false, isVoting: false,
                        onConfirm: {}, onDismiss: {},
                        onClose: { withAnimation(NTMotion.spring) { hazardStore.selectedHazard = nil } }
                    )
                    .padding(.horizontal, 16).padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let selectedPOI {
                    poiCard(selectedPOI)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if let meteo {
                    MeteoTimelinePanel(model: meteo, onClose: { withAnimation(NTMotion.spring) { self.meteo = nil } })
                        .padding(.horizontal, 12).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .foregroundStyle(NTColor.milk)
        .fullScreenCover(isPresented: $showPaywall) { PaywallView(onClose: { showPaywall = false }) }
        .fullScreenCover(item: $photoViewerSpot) { spot in
            // Reuses the exact same viewer `RoutePhotosSection` presents —
            // one real swipeable photo screen, not a second one built for
            // the map specifically. Starts at the tapped spot's first
            // photo but still pages through every photo on the route so
            // swiping isn't a dead end at the edge of a small cluster.
            PhotoViewerView(
                photos: photos,
                startIndex: photos.firstIndex(where: { $0.id == spot.photos.first?.id }) ?? 0,
                currentUserId: currentUserId,
                onDelete: { photo in
                    photos.removeAll { $0.id == photo.id }
                    Task { try? await RouteRepository.shared.deletePhoto(id: photo.id) }
                },
                onReport: { photo in
                    Task { try? await RouteRepository.shared.report(.photo, id: photo.id, reason: "Reported from map") }
                },
                onClose: { photoViewerSpot = nil }
            )
        }
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

            if trackPoints.count > 1 {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if meteo != nil {
                        withAnimation(NTMotion.spring) { meteo = nil }
                    } else if SubscriptionManager.shared.isPro {
                        let model = MeteoViewModel(trackPoints: trackPoints, transport: route.transport)
                        withAnimation(NTMotion.spring) { meteo = model }
                        Task { await model.load() }
                    } else {
                        showPaywall = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "cloud.bolt.rain.fill")
                        Text("METEO").font(NTFont.mono(11, .semibold)).tracking(0.6)
                        if !SubscriptionManager.shared.isPro { Text("PRO").font(NTFont.mono(8, .semibold)).padding(.horizontal, 4).background(Capsule().fill(NTColor.gold)) }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(meteo != nil ? NTColor.pine : NTColor.ink)
                    .padding(.horizontal, 12).frame(height: 42)
                    .background(Capsule().fill(meteo != nil ? Color.cyan : .white))
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
            }

            Spacer()

            if !trackPoints.isEmpty {
                Menu {
                    Button {
                        openInAppleMaps(waypoints: routeWaypoints, name: route.title.replacingOccurrences(of: "\n", with: " "))
                    } label: {
                        Label("Apple Maps", systemImage: "map")
                    }
                    Button {
                        openInGoogleMaps(waypoints: routeWaypoints)
                    } label: {
                        Label("Google Maps", systemImage: "map")
                    }
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

    /// `MKMapItem.openMaps(with:)` with more than one item opens Apple Maps
    /// showing directions through all of them in order — the first item
    /// becomes the route's origin instead of defaulting to the user's
    /// current location the way the single-item `openInMaps(launchOptions:)`
    /// does, which is the actual fix: this shows the real route (its own
    /// start through its own end), not "how do I get to the trailhead
    /// from here."
    private func openInAppleMaps(waypoints: [CLLocationCoordinate2D], name: String) {
        guard !waypoints.isEmpty else { return }
        let items = waypoints.enumerated().map { i, coordinate -> MKMapItem in
            let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
            item.name = i == 0 ? name : (i == waypoints.count - 1 ? "\(name) — end" : nil)
            return item
        }
        MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// Google's own documented "Maps URLs" scheme
    /// (developers.google.com/maps/documentation/urls/get-started) — a
    /// plain `https://` universal link, so this opens the real Google Maps
    /// app directly if it's installed (no custom `comgooglemaps://` scheme
    /// or `LSApplicationQueriesSchemes` entry needed) and falls back to
    /// Google Maps in Safari if it isn't. `waypoints` takes a `|`-separated
    /// list of real coordinates between `origin` and `destination` — the
    /// same real-route-shape approach as the Apple Maps hand-off above.
    private func openInGoogleMaps(waypoints: [CLLocationCoordinate2D]) {
        guard let first = waypoints.first, let last = waypoints.last else { return }
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "origin", value: "\(first.latitude),\(first.longitude)"),
            URLQueryItem(name: "destination", value: "\(last.latitude),\(last.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        let middle = waypoints.dropFirst().dropLast()
        if !middle.isEmpty {
            items.append(URLQueryItem(name: "waypoints", value: middle.map { "\($0.latitude),\($0.longitude)" }.joined(separator: "|")))
        }
        var components = URLComponents(string: "https://www.google.com/maps/dir/")!
        components.queryItems = items
        guard let url = components.url else { return }
        UIApplication.shared.open(url)
    }
}

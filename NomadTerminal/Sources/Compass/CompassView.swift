import SwiftUI
import CoreLocation
import MapboxMaps
import Turf

/// 06 · Compass mode — real device heading via CoreLocation. Given a
/// route's real segments/POIs, builds a real ordered waypoint list (each
/// segment's end point along the actual recorded track, plus every dropped
/// POI) instead of faking a single "WAYPOINT 3 OF 5" label; without route
/// data at all, it's an honest plain compass instead of faking a waypoint
/// that doesn't exist.
///
/// Defaults to a real Mapbox map (same satellite/polyline rendering as
/// `RouteFullMapView`, plus a live-following location puck) rather than
/// the bearing-only dial — actually seeing the real route's shape under
/// your real moving position is the point of "launching" a route, not
/// just an arrow and a distance number. The dial is still one tap away
/// (`showMapMode` toggle in the header) for a GPS-only fallback / battery
/// saver, or when there's no track to draw at all.
struct CompassView: View {
    var routeId: String? = nil
    /// The route's own real title — threaded through to
    /// `LiveActivityManager.startNavigating` so the Dynamic Island shows
    /// the actual route name, not a generic label. Nil only for the
    /// plain, target-less compass (no route involved at all).
    var routeName: String? = nil
    var segments: [RouteDetailInfo.Segment] = []
    var trackPoints: [TrackPoint] = []
    var pois: [RouteDetailInfo.POI] = []
    var onClose: () -> Void

    @State private var tracker = CompassTracker()
    @State private var showSOS = false
    @State private var showWaypoints = false
    @State private var showLogNote = false
    @State private var waypoints: [CompassWaypoint] = []
    @State private var waypointIndex = 0
    /// Compass used to have its own bottom-tab entry for a "no route"
    /// plain compass; that tab is gone now, so this lets the same screen
    /// (opened from a route's Navigate button) drop its waypoint target
    /// and act as a plain compass without leaving the screen.
    @State private var showingPlain = false
    /// The needle's actual on-screen rotation — unwrapped (not clamped to
    /// 0..<360) so it always animates the short way around. Animating the
    /// raw 0..<360 `needleRotation` directly makes the needle spin almost
    /// all the way around every time it crosses the 0°/360° seam, which on
    /// a real device (where heading updates constantly) looked jerky.
    @State private var displayRotation: Double = 0

    /// True by default — the map is the "launch a route" experience now;
    /// the dial is the fallback. Computed once in `.onAppear` from the
    /// same `MapSegmentStretch` pipeline `RouteFullMapView` uses, so the
    /// polyline this screen draws can't disagree with the one on Route
    /// Detail's own full map.
    @State private var showMapMode = true
    @State private var segmentStretches: [MapSegmentStretch] = []
    @State private var viewport: Viewport = .styleDefault
    /// True = satellite imagery, tilted "navigator" camera (pitch 40°).
    /// False = the actual flat classic navigator look — Standard's plain
    /// vector style (clean roads/paths/labels, no satellite photo) at a
    /// top-down pitch 0 — not just the satellite photo tilted flat, which
    /// still reads as "a photo" rather than "a map." Both follow the puck
    /// and rotate with real device heading regardless; this only changes
    /// the look, same as Waze/Google Maps' own 2D/3D toggle.
    @State private var is3DMap = true
    /// Bright vector map by default; satellite is an opt-in toggle.
    @State private var showSatellite = false

    private var followViewport: Viewport {
        .followPuck(zoom: 17, bearing: .heading, pitch: is3DMap ? 40 : 0)
    }
    private var mapStyle: MapboxMaps.MapStyle {
        NomadMap.style(satellite: showSatellite)
    }

    /// The real recorded track as one `Turf.LineString` — built once in
    /// `.onAppear`, reused every ~2.5s tick (`updateNavigationState`) to
    /// answer two real questions plain "distance to waypoint" can't: how
    /// far off the actual path is the user right now (`closestOnTrail` +
    /// `offTrailMeters`), and how far along the whole route have they
    /// actually gotten (`progressMeters`/`progressFraction`) — real
    /// on-trail detection and route progress, the two things a recorded-
    /// track "follow" screen can offer that a plain compass dial can't,
    /// with no routing engine or paid Nav SDK involved.
    @State private var fullLine: LineString?
    /// The user's own real path during this navigation session, sampled
    /// every tick when they've moved >`breadcrumbMinMoveM` — drawn as a
    /// distinct line on the map so it's visible whether they're tracking
    /// the planned route or wandering off it, not just told a number.
    @State private var breadcrumb: [CLLocationCoordinate2D] = []
    @State private var offTrailMetersBanner: Int?
    @State private var transientMessage: TransientMessage?
    @State private var hasArrived = false
    /// Real geotagged photos on this route and the author's own placed
    /// POIs — same two pin types `RouteFullMapView` already shows, tap-to-
    /// reveal and all. This screen (live navigation) previously had
    /// neither: POI pins were decorative glyphs with no tap action, and
    /// there were no photo pins at all, even though this is the screen
    /// someone's actually looking at mid-hike.
    @State private var photos: [RouteRepository.RoutePhoto] = []
    @State private var currentUserId: String?
    @State private var selectedPOI: RouteDetailInfo.POI?
    @State private var photoViewerSpot: PhotoSpot?
    // Community layer: hazard reports + verified partners, FAB, store.
    @State private var hazardStore = HazardStore()
    @State private var showHazardSheet = false
    @State private var showNomadStore = false
    private var photoSpots: [PhotoSpot] { PhotoSpot.cluster(photos) }

    private let offTrailThresholdM: Double = 50
    private let waypointArrivalThresholdM: Double = 40
    private let breadcrumbMinMoveM: Double = 8

    enum TransientMessage: Equatable {
        case reachedWaypoint
        case routeComplete
    }

    private var hasRealTrack: Bool { trackPoints.count > 1 }

    private var closestOnTrail: LineString.IndexedCoordinate? {
        guard let fullLine, let current = tracker.currentLocation?.coordinate else { return nil }
        return fullLine.closestCoordinate(to: current)
    }
    private var offTrailMeters: Double? {
        guard let closestOnTrail, let current = tracker.currentLocation else { return nil }
        return current.distance(from: CLLocation(latitude: closestOnTrail.coordinate.latitude, longitude: closestOnTrail.coordinate.longitude))
    }
    private var routeTotalMeters: Double { fullLine?.distance() ?? 0 }
    private var progressMeters: Double { closestOnTrail?.distance ?? 0 }
    private var remainingMeters: Double { max(0, routeTotalMeters - progressMeters) }
    private var progressFraction: Double {
        routeTotalMeters > 1 ? min(1, max(0, progressMeters / routeTotalMeters)) : 0
    }
    /// The Standard Satellite style supports real time-of-day lighting for
    /// free (built into the style, no extra data or API call) — a small
    /// thing none of AllTrails/Komoot/Gaia GPS bother with on their own
    /// "follow route" screens, and it makes the map look alive rather than
    /// a flat, always-noon satellite tile.
    private var lightPreset: StandardLightPreset {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<8: return .dawn
        case 8..<18: return .day
        case 18..<20: return .dusk
        default: return .night
        }
    }

    private var currentWaypoint: CompassWaypoint? {
        waypoints.indices.contains(waypointIndex) ? waypoints[waypointIndex] : nil
    }
    /// nil while showing the plain compass, even if a real target exists.
    private var activeTarget: CLLocationCoordinate2D? { showingPlain ? nil : currentWaypoint?.coordinate }
    private var hasTarget: Bool { activeTarget != nil && distanceKM != nil }
    private var distanceKM: Double? { activeTarget.flatMap { tracker.distanceKM(to: $0) } }
    private var bearingToTarget: Double? { activeTarget.flatMap { tracker.bearing(to: $0) } }
    /// Needle rotation relative to the top of the screen: points at the
    /// target bearing (adjusted for which way the phone itself is facing)
    /// when there's a target, otherwise just points at true north.
    private var needleRotation: Double {
        let target = bearingToTarget ?? 0
        let r = target - tracker.headingDegrees
        return r < 0 ? r + 360 : r
    }
    private var etaMinutes: Int? {
        guard let distanceKM, tracker.speedKMH > 0.5 else { return nil }
        return Int((distanceKM / tracker.speedKMH * 60).rounded())
    }

    private var isMapActive: Bool { showMapMode && hasRealTrack }

    var body: some View {
        ZStack {
            if isMapActive {
                mapLayer
            } else {
                NTColor.pineDeep.ignoresSafeArea()
            }

            VStack(spacing: 0) {
                header
                if hasRealTrack { banners }
                if let alert = hazardStore.proximityAlert {
                    HazardProximityBanner(
                        alert: alert,
                        onTap: { hazardStore.selectedHazard = alert.hazard },
                        onDismiss: { hazardStore.dismissProximityAlert() }
                    )
                    .padding(.horizontal, 16).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer(minLength: 0)
                if isMapActive {
                    HStack {
                        Spacer()
                        HazardFAB { showHazardSheet = true }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 4)
                    recenterButton
                    if let hazard = hazardStore.selectedHazard {
                        HazardDetailCard(
                            hazard: hazard,
                            isVoting: hazardStore.isVoting,
                            onConfirm: { Task { await hazardStore.vote(confirm: true, from: tracker.currentLocation?.coordinate) } },
                            onDismiss: { Task { await hazardStore.vote(confirm: false, from: tracker.currentLocation?.coordinate) } },
                            onClose: { withAnimation(NTMotion.spring) { hazardStore.selectedHazard = nil } }
                        )
                        .padding(.horizontal, 16).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let partner = hazardStore.selectedPartner {
                        PartnerDetailCard(
                            partner: partner,
                            onOpenStore: { showNomadStore = true },
                            onClose: { withAnimation(NTMotion.spring) { hazardStore.selectedPartner = nil } }
                        )
                        .padding(.horizontal, 16).padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if let selectedPOI {
                        poiCard(selectedPOI)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    hudStrip
                } else {
                    dial
                    Spacer(minLength: 0)
                }
                footer
            }
        }
        .foregroundStyle(NTColor.milk)
        .overlay {
            if let points = hazardStore.rewardBurst {
                PointsBurstOverlay(points: points)
                    .transition(.scale.combined(with: .opacity))
                    .task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        withAnimation { hazardStore.rewardBurst = nil }
                    }
            }
        }
        .sheet(isPresented: $showHazardSheet) {
            HazardReportSheet(coordinate: tracker.currentLocation?.coordinate, store: hazardStore) {
                showHazardSheet = false
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showNomadStore) { NomadStoreView() }
        .onChange(of: tracker.currentLocation?.timestamp) { _, _ in
            if let here = tracker.currentLocation?.coordinate {
                withAnimation(NTMotion.spring) { hazardStore.updateProximity(at: here) }
            }
        }
        .task(id: tracker.currentLocation != nil) {
            // Load once a fix exists, then keep the layer fresh while open.
            while !Task.isCancelled {
                if let here = tracker.currentLocation?.coordinate { await hazardStore.refresh(near: here) }
                else { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
        .fullScreenCover(isPresented: $showSOS) {
            SOSView(
                onClose: { showSOS = false },
                lastKnownCoordinate: tracker.currentLocation?.coordinate,
                onTriggered: { LiveActivityManager.shared.triggerSOS() },
                onCancelled: { LiveActivityManager.shared.cancelSOS() }
            )
        }
        .onAppear {
            tracker.start()
            waypoints = CompassWaypoint.build(segments: segments, trackPoints: trackPoints, pois: pois)
            segmentStretches = MapSegmentStretch.compute(trackPoints: trackPoints, segments: segments)
            displayRotation = needleRotation
            if hasRealTrack {
                fullLine = LineString(trackPoints.map(\.coordinate))
                viewport = followViewport
                // Real Dynamic Island / Lock Screen presence for
                // navigation, same as recording already gets — lock the
                // phone or switch apps mid-hike and the real distance/ETA
                // is still right there, not just silently tracked in the
                // background with nothing to show for it.
                LiveActivityManager.shared.startNavigating(routeName: routeName, plannedLengthKM: routeTotalMeters / 1000)
            }
        }
        .onDisappear {
            tracker.stop()
            LiveActivityManager.shared.endNavigating()
        }
        .task {
            // Polling, not `.onChange(of: tracker.currentLocation)` — a
            // fresh `CLLocation` arrives many times a second on a real
            // device and none of on-trail/progress/arrival needs that
            // granularity; a steady ~2.5s tick is plenty responsive for a
            // walking/driving pace and a lot cheaper.
            while !Task.isCancelled {
                updateNavigationState()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        .task {
            guard let routeId else { return }
            photos = (try? await RouteRepository.shared.fetchPhotos(routeId: routeId)) ?? []
            currentUserId = (try? await supabase.auth.session)?.user.id.uuidString
        }
        .fullScreenCover(item: $photoViewerSpot) { spot in
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
        .sheet(isPresented: $showWaypoints) {
            WaypointsSheet(waypoints: waypoints, current: waypointIndex) { index in
                UISelectionFeedbackGenerator().selectionChanged()
                waypointIndex = index
                showWaypoints = false
            }
        }
        .sheet(isPresented: $showLogNote) {
            if let routeId {
                LogNoteSheet(routeId: routeId, waypointName: currentWaypoint?.name)
            }
        }
        .onChange(of: needleRotation) { _, newValue in
            var delta = (newValue - displayRotation.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            withAnimation(.easeInOut(duration: 0.25)) {
                displayRotation += delta
            }
        }
    }

    private var header: some View {
        HStack {
            // Real fix for a real bug: every header button here was a
            // stroke-only outline with no solid fill — unlike every other
            // close/back button in the app (RecordTrackView, DrawRouteView,
            // ImportRouteView, RouteUploadDetailsView's new back button all
            // have a real `.background(Circle().fill(...))`). Over a plain
            // color background that's harmless; layered on top of
            // Mapbox's own live, actively-gesture-handling `Map` (this
            // screen's default mode now), a hit area with no opaque
            // backing and no explicit `.contentShape` can lose the touch
            // to the map's pan recognizer underneath — which matched
            // exactly what got reported (X not responding specifically in
            // map mode, while the filled 3D/recenter buttons did). Added a
            // real fill + explicit `.contentShape(Circle())` to every
            // button in this header, not just X, since they're all the
            // same shape.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NTColor.milk(0.12)))
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 5) {
                Text(activeTarget != nil ? "WAYPOINT \(waypointIndex + 1) OF \(waypoints.count)" : "NO ACTIVE ROUTE")
                    .font(NTFont.mono(10, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.5))
                Text(activeTarget != nil ? (currentWaypoint?.name ?? "") : "Plain compass")
                    .font(NTFont.body(14, .semibold))
            }

            Spacer()

            if hasRealTrack {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(NTMotion.spring) { showMapMode.toggle() }
                    if showMapMode {
                        withViewportAnimation(.easeOut(duration: 0.6)) {
                            viewport = followViewport
                        }
                    }
                } label: {
                    Image(systemName: showMapMode ? "location.north.circle.fill" : "map.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(NTColor.milk(0.8))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(NTColor.milk(0.12)))
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            if !waypoints.isEmpty && !isMapActive {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation { showingPlain.toggle() }
                } label: {
                    Image(systemName: showingPlain ? "location.north.line.fill" : "location.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showingPlain ? NTColor.accent : NTColor.milk(0.8))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(NTColor.milk(0.12)))
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

            Button { showSOS = true } label: {
                Image(systemName: "sos")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xE58272))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NTColor.milk(0.12)))
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    /// The real map — same satellite/polyline rendering `RouteFullMapView`
    /// uses (segment-colored polyline, POI pins), plus a real live-updating
    /// location puck (`Puck2D`) that the `.followPuck` viewport keeps
    /// centered and rotated to the device's real heading. Panning away
    /// switches Mapbox's own viewport binding to `.idle` automatically —
    /// `recenterButton` below snaps it back.
    private var mapLayer: some View {
        Map(viewport: $viewport) {
            Puck2D(bearing: .heading)
                .pulsing(.default)

            if !segmentStretches.isEmpty {
                RouteSegmentMapContent(stretches: segmentStretches, flowStep: 0)
            } else {
                let sourceId = "compass-route-plain"
                GeoJSONSource(id: sourceId).data(.geometry(.lineString(LineString(trackPoints.map(\.coordinate)))))
                LineLayer(id: "\(sourceId)-line", source: sourceId)
                    .lineColor(UIColor(NTColor.accent))
                    .lineWidth(7)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineBorderColor(UIColor.black.withAlphaComponent(0.4))
                    .lineBorderWidth(2)
            }

            // The user's own real path this session, distinct from the
            // planned route line above it — makes it visible at a glance
            // whether they're tracking the trail or drifting, not just a
            // number in the HUD.
            if breadcrumb.count > 1 {
                let bcId = "compass-breadcrumb"
                GeoJSONSource(id: bcId).data(.geometry(.lineString(LineString(breadcrumb))))
                LineLayer(id: "\(bcId)-line", source: bcId)
                    .lineColor(UIColor(NTColor.milk))
                    .lineWidth(4)
                    .lineCap(.round)
                    .lineJoin(.round)
                    .lineOpacity(0.9)
            }

            // A cheap, honest stand-in for "reroute" — there's no routing
            // engine here, so this doesn't calculate a real path back, it
            // just draws the straight real-geometry line from the user's
            // real position to the nearest real point on the trail, so
            // "which way is back" is visually obvious.
            if let offTrailMetersBanner, offTrailMetersBanner > 0, let current = tracker.currentLocation?.coordinate, let target = closestOnTrail?.coordinate {
                let rejoinId = "compass-rejoin"
                GeoJSONSource(id: rejoinId).data(.geometry(.lineString(LineString([current, target]))))
                LineLayer(id: "\(rejoinId)-line", source: rejoinId)
                    .lineColor(UIColor(Color(hex: 0xE58272)))
                    .lineWidth(3)
                    .lineDashArray([0, 2])
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

            // Real photo pins — clustered the same way `RouteFullMapView`
            // does, drawn after the POI pins so one never sits visually
            // under a near-identical POI pin.
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

            CommunityMapContent(
                hazards: hazardStore.hazards,
                partners: hazardStore.partners,
                onHazard: { hazard in
                    withAnimation(NTMotion.spring) { hazardStore.selectedPartner = nil; selectedPOI = nil; hazardStore.selectedHazard = hazard }
                },
                onPartner: { partner in
                    withAnimation(NTMotion.spring) { hazardStore.selectedHazard = nil; selectedPOI = nil; hazardStore.selectedPartner = partner }
                }
            )

            if let currentWaypoint {
                MapViewAnnotation(coordinate: currentWaypoint.coordinate) {
                    ZStack {
                        Circle().fill(currentWaypoint.tint)
                        Image(systemName: currentWaypoint.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(.white, lineWidth: 2.4))
                    .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
                }
            }
        }
        .mapStyle(mapStyle)
        // Mapbox's own compass ornament defaults to `.topTrailing` and
        // auto-shows (`.adaptive`) the instant the camera bearing stops
        // being exactly north — which is permanently true here, since
        // `.followPuck(bearing: .heading)` keeps the map rotated to the
        // real device heading. Its default position sits exactly on top
        // of the SOS button, and the scale bar's own default
        // `.topLeading` sits on top of the close (X) button — both are
        // real native UIKit controls (the compass is tappable, resets
        // bearing to north) that intercept the touch before it reaches
        // the SwiftUI buttons underneath, not just a visual overlap. This
        // screen already has its own GPS/heading HUD, so neither ornament
        // is needed — hiding both is the fix, not working around their
        // position.
        .ornamentOptions(OrnamentOptions(
            scaleBar: ScaleBarViewOptions(visibility: .hidden),
            compass: CompassViewOptions(visibility: .hidden)
        ))
        .ignoresSafeArea()
    }

    /// Off-trail warning (persists as long as the condition holds) and the
    /// transient "waypoint reached" / "route complete" toasts, stacked —
    /// both are plain-literal `Text` per branch (never an interpolated-
    /// then-formatted `String`), so both stay real `LocalizedStringKey`s.
    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 8) {
            if let offTrailMetersBanner {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(String(offTrailMetersBanner)).fontWeight(.semibold)
                    Text("M OFF TRAIL — HEAD BACK")
                }
                .font(NTFont.mono(11, .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xB33A2B), in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let transientMessage {
                HStack(spacing: 8) {
                    switch transientMessage {
                    case .reachedWaypoint:
                        Image(systemName: "checkmark.circle.fill")
                        Text("Waypoint reached")
                    case .routeComplete:
                        Image(systemName: "flag.checkered.circle.fill")
                        Text("Route complete — nice work")
                    }
                }
                .font(NTFont.body(13, .semibold))
                .foregroundStyle(NTColor.pine)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(NTColor.sage, in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(NTMotion.spring, value: offTrailMetersBanner)
        .animation(NTMotion.spring, value: transientMessage)
    }

    /// Same card `RouteFullMapView.poiCard` shows — icon, title, category,
    /// the author's own note — just styled for this screen's dark HUD
    /// chrome instead of that one's.
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

    private var recenterButton: some View {
        HStack(spacing: 10) {
            Spacer()

            // Same toggle Waze/Google Maps offer — a real flat 2D map
            // (Standard's plain vector style, no satellite photo, pitch 0)
            // versus the tilted 3D satellite "navigator" view, not just the
            // same satellite photo laid flat. Both still follow the puck
            // and rotate with real heading either way.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSatellite.toggle()
            } label: {
                Image(systemName: showSatellite ? "map.fill" : "globe.europe.africa.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NTColor.pine)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(NTColor.milk))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSatellite ? "Switch to map view" : "Switch to satellite view")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                is3DMap.toggle()
                withViewportAnimation(.easeOut(duration: 0.5)) {
                    viewport = followViewport
                }
            } label: {
                Text(is3DMap ? "3D" : "2D")
                    .font(NTFont.mono(13, .semibold))
                    .foregroundStyle(NTColor.pine)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(NTColor.milk))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withViewportAnimation(.easeOut(duration: 0.6)) {
                    viewport = followViewport
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NTColor.pine)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(NTColor.milk))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
    }

    /// Compact readout docked near the bottom of the map — the same real
    /// distance/ETA/bearing numbers `readoutCard` shows in dial mode, just
    /// small enough not to block the actual view of the route underneath.
    private var hudStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Two separately-localized pieces, not one interpolated-then-
            // uppercased String — a ternary with a dynamic branch forces
            // Text(String) instead of Text(LocalizedStringKey), which
            // silently never translates (the same trap the header/dial
            // readoutCard's plain "TO WAYPOINT"/"HEADING" ternary avoids by
            // having both branches be string literals). The waypoint's own
            // name is already shown in the screen header above, so it isn't
            // repeated here.
            Text(hasTarget ? "TO WAYPOINT" : "HEADING")
                .font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.6))
                .lineLimit(1)

            HStack(alignment: .lastTextBaseline, spacing: 18) {
                if hasTarget, let distanceKM {
                    HStack(alignment: .lastTextBaseline, spacing: 5) {
                        Text(String(format: "%.2f", distanceKM)).font(NTFont.mono(30, .semibold))
                        Text("KM").font(NTFont.mono(12, .medium)).foregroundStyle(NTColor.milk(0.55))
                    }
                } else {
                    Text(String(format: "%03d°", Int(tracker.headingDegrees.rounded()))).font(NTFont.mono(28, .semibold))
                }
                Rectangle().fill(NTColor.milk(0.16)).frame(width: 1, height: 26)
                readoutStat(String(format: "%.1f", tracker.speedKMH), "KM/H")
                readoutStat(etaMinutes.map { "\($0)m" } ?? "—", "ETA")
                Spacer(minLength: 0)
            }

            // Real progress along the actual recorded track (via
            // `Turf.LineString.closestCoordinate`'s cumulative distance),
            // not a straight-line guess — this is what "how far through
            // the route am I" actually means when the route isn't a
            // straight line.
            if hasRealTrack && routeTotalMeters > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(NTColor.milk(0.16)).frame(height: 4)
                            Capsule().fill(NTColor.accent).frame(width: max(4, geo.size.width * progressFraction), height: 4)
                        }
                    }
                    .frame(height: 4)
                    HStack(spacing: 4) {
                        Text(String(format: "%.1f", remainingMeters / 1000)).font(NTFont.mono(11, .semibold))
                        Text("KM REMAINING").font(NTFont.mono(9, .medium)).tracking(0.4).foregroundStyle(NTColor.milk(0.5))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .environment(\.colorScheme, .dark)
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.18), lineWidth: 1))
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var dial: some View {
        ZStack {
            dialFace

            ZStack {
                needleGlyph
                Circle()
                    .fill(RadialGradient(colors: [NTColor.accent.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 30))
                    .frame(width: 60, height: 60)
                    .offset(y: -142)
            }
            .rotationEffect(.degrees(displayRotation))

            readoutCard
        }
        .frame(width: 342, height: 342)
    }

    private var dialFace: some View {
        ZStack {
            Circle().stroke(NTColor.milk(0.1), lineWidth: 1)
            Circle().stroke(NTColor.milk(0.14), lineWidth: 1).padding(24)
            Circle().stroke(NTColor.milk(0.08), lineWidth: 1).padding(58)

            ForEach(0..<16, id: \.self) { i in
                Rectangle()
                    .fill(NTColor.milk(i % 4 == 0 ? 0.5 : 0.22))
                    .frame(width: i % 4 == 0 ? 1.6 : 1, height: i % 4 == 0 ? 12 : 7)
                    .offset(y: -163)
                    .rotationEffect(.degrees(Double(i) * 22.5))
            }

            Group {
                Text("N").offset(y: -152)
                Text("E").offset(x: 152).foregroundStyle(NTColor.milk(0.4))
                Text("S").offset(y: 152).foregroundStyle(NTColor.milk(0.4))
                Text("W").offset(x: -152).foregroundStyle(NTColor.milk(0.4))
            }
            .font(NTFont.mono(13, .semibold))
        }
    }

    private var needleGlyph: some View {
        VStack(spacing: 0) {
            CompassNeedleTip()
                .fill(NTColor.accent)
                .frame(width: 36, height: 46)
            Spacer()
        }
        .frame(height: 342)
    }

    private var readoutCard: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [NTColor.pineLine, NTColor.pineDeep], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 130))
                .overlay(Circle().stroke(NTColor.milk(0.12), lineWidth: 1))

            VStack(spacing: 12) {
                Text(hasTarget ? "TO WAYPOINT" : "HEADING")
                    .font(NTFont.mono(10, .medium)).tracking(1.6).foregroundStyle(NTColor.milk(0.5))

                if hasTarget, let distanceKM {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(String(format: "%.2f", distanceKM))
                            .font(NTFont.mono(58, .semibold))
                            .contentTransition(.numericText())
                        Text("KM").font(NTFont.mono(16, .medium)).foregroundStyle(NTColor.milk(0.55))
                    }
                } else {
                    Text(String(format: "%03d°", Int(tracker.headingDegrees.rounded())))
                        .font(NTFont.mono(52, .semibold))
                        .contentTransition(.numericText())
                }

                Text(hasTarget ? "BEARING \(Int((bearingToTarget ?? 0).rounded()))° \(compassPoint(bearingToTarget ?? 0))" : compassPoint(tracker.headingDegrees) + " · TRUE NORTH")
                    .font(NTFont.mono(11, .semibold)).tracking(0.6)
                    .foregroundStyle(Color(hex: 0xF1A47C))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(NTColor.accent.opacity(0.16)))
                    .overlay(Capsule().stroke(NTColor.accent.opacity(0.4), lineWidth: 1))

                HStack(spacing: 16) {
                    readoutStat(tracker.altitudeM > 0 ? "\(Int(tracker.altitudeM))" : "—", "ALT M")
                    Rectangle().fill(NTColor.milk(0.14)).frame(width: 1, height: 26)
                    readoutStat(String(format: "%.1f", tracker.speedKMH), "KM/H")
                    Rectangle().fill(NTColor.milk(0.14)).frame(width: 1, height: 26)
                    readoutStat(etaMinutes.map { "\($0)m" } ?? "—", "ETA")
                }
                .padding(.top, 4)
            }
        }
        .frame(width: 228, height: 228)
    }

    private var gpsStatusText: LocalizedStringKey {
        if tracker.authorizationDenied { return "LOCATION ACCESS DENIED — ENABLE IN SETTINGS" }
        if tracker.horizontalAccuracyM < 0 { return "ACQUIRING GPS FIX…" }
        return "GPS FIX \(Int(tracker.horizontalAccuracyM.rounded())) M"
    }

    private var gpsStatusColor: Color {
        if tracker.authorizationDenied { return Color(hex: 0xE58272) }
        if tracker.horizontalAccuracyM < 0 { return NTColor.gold }
        return NTColor.sage
    }

    /// One tick of the real navigation logic: samples the breadcrumb,
    /// flags on/off-trail, auto-advances to the next waypoint on real
    /// proximity, and flags arrival at the route's end — all from real
    /// GPS + the real recorded track, no routing engine involved.
    private func updateNavigationState() {
        guard hasRealTrack, let current = tracker.currentLocation?.coordinate else { return }

        if let last = breadcrumb.last {
            let moved = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude))
            if moved > breadcrumbMinMoveM { breadcrumb.append(current) }
        } else {
            breadcrumb.append(current)
        }

        if let offTrailMeters {
            if offTrailMeters > offTrailThresholdM {
                if offTrailMetersBanner == nil {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                }
                offTrailMetersBanner = Int(offTrailMeters.rounded())
            } else {
                offTrailMetersBanner = nil
            }
        }

        LiveActivityManager.shared.updateNavigating(.init(
            waypointName: showingPlain ? "" : (currentWaypoint?.name ?? ""),
            distanceToWaypointKM: distanceKM,
            remainingKM: remainingMeters / 1000,
            progressFraction: progressFraction,
            etaMinutes: etaMinutes,
            isOffTrail: offTrailMetersBanner != nil
        ))

        guard !showingPlain, !hasArrived, let distanceKM, distanceKM * 1000 < waypointArrivalThresholdM else { return }
        if waypointIndex < waypoints.count - 1 {
            waypointIndex += 1
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showTransient(.reachedWaypoint)
        } else {
            hasArrived = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            showTransient(.routeComplete)
            RouteRepository.shared.logEvent("route_navigation_completed")
        }
    }

    private func showTransient(_ message: TransientMessage) {
        transientMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if transientMessage == message { transientMessage = nil }
        }
    }

    private func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return points[max(0, min(7, index))]
    }

    private func readoutStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 5) {
            Text(value).font(NTFont.mono(14, .semibold))
            Text(label).font(NTFont.mono(8.5, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.45))
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(gpsStatusColor).frame(width: 7, height: 7)
                Text(gpsStatusText)
                    .font(NTFont.mono(11, .medium)).tracking(0.4)
                    .foregroundStyle(NTColor.milk(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showWaypoints = true
                } label: {
                    Text("Waypoints")
                        .font(NTFont.body(14, .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .overlay(Capsule().stroke(NTColor.milk(0.4), lineWidth: 1.4))
                }
                .buttonStyle(.plain).ntPressable()
                .disabled(waypoints.isEmpty)
                .opacity(waypoints.isEmpty ? 0.4 : 1)

                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showLogNote = true
                } label: {
                    Text("Log a note")
                        .font(NTFont.body(14, .semibold))
                        .foregroundStyle(NTColor.pine)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain).ntPressable()
                .disabled(routeId == nil)
                .opacity(routeId == nil ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

/// One stop on a real route — either a segment's end point (derived from
/// the actual recorded track, same proportional split `MapSegmentStretch`
/// already draws on the map, so the list and the map polyline can't
/// disagree) or a user-dropped POI. Ordered document order: segments first
/// (the route's natural narrative), then POIs.
struct CompassWaypoint: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let icon: String
    let tint: Color

    static func build(segments: [RouteDetailInfo.Segment], trackPoints: [TrackPoint], pois: [RouteDetailInfo.POI]) -> [CompassWaypoint] {
        var result: [CompassWaypoint] = []
        let stretches = MapSegmentStretch.compute(trackPoints: trackPoints, segments: segments)
        for stretch in stretches {
            guard let end = stretch.coordinates.last else { continue }
            result.append(CompassWaypoint(name: stretch.label, coordinate: end, icon: stretch.icon, tint: stretch.tint))
        }
        for poi in pois {
            result.append(CompassWaypoint(name: poi.title, coordinate: poi.coordinate, icon: poi.category.icon, tint: poi.category.tint))
        }
        // No segments (route logged with zero transport legs) but a real
        // track still exists — fall back to a single "route end" waypoint
        // rather than showing "NO ACTIVE ROUTE" for a route that does have one.
        if result.isEmpty, let end = trackPoints.last?.coordinate {
            result.append(CompassWaypoint(name: "Route end", coordinate: end, icon: "flag.checkered", tint: NTColor.accent))
        }
        return result
    }
}

private struct WaypointsSheet: View {
    let waypoints: [CompassWaypoint]
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, wp in
                    Button { onSelect(index) } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(wp.tint)
                                Image(systemName: wp.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                            }
                            .frame(width: 32, height: 32)

                            Text(wp.name).font(NTFont.body(15, .semibold))
                            Spacer()
                            if index == current {
                                Image(systemName: "checkmark").foregroundStyle(NTColor.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(NTColor.pine)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NTColor.pineDeep)
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Waypoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }
}

/// Real, not decorative — saves as an actual comment on the route (reuses
/// the same `route_comments` backend `CommentsView` already writes to), so
/// a field note left mid-hike is genuinely visible to anyone reading the
/// route afterward, not lost.
private struct LogNoteSheet: View {
    let routeId: String
    let waypointName: String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let waypointName {
                    Text("NEAR \(waypointName.uppercased())")
                        .font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                }
                TextEditor(text: $text)
                    .scrollContentBackground(.hidden)
                    .font(NTFont.body(15, .regular))
                    .frame(minHeight: 140)
                    .padding(10)
                    .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                Spacer()
            }
            .padding(20)
            .background(NTColor.pineDeep)
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Log a note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !body.isEmpty else { return }
                        isSaving = true
                        Task {
                            try? await RouteRepository.shared.postComment(routeId: routeId, body: body)
                            dismiss()
                        }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct CompassNeedleTip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.7))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    CompassView(
        routeId: "00000000-0000-0000-0000-000000000000",
        segments: RouteDetailInfo.zagarPass.segments,
        trackPoints: RouteDetailInfo.zagarPass.trackPoints,
        onClose: {}
    )
}

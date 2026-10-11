import SwiftUI
import UniformTypeIdentifiers
import CoreLocation
import MapboxMaps
import PhotosUI

/// 14b · Import — was one of the three "how did you get the line" options
/// in `LogRouteStartView` that did nothing at all before this. Real GPX/KML
/// parsing (`RouteFileParser`), same distance/ascent math `RouteTracker`
/// uses for a live recording (`TrackMath`, a batch version of the same
/// formulas), then feeds the exact same `RecordResult` → `NewRouteDraft`
/// pipeline `RecordTrackView` and `DrawRouteView` both feed — nothing
/// downstream (`RouteUploadDetailsView`, publish) needed to change.
///
/// Photos — same structural gap `DrawRouteView` had: an imported track has
/// no live GPS fix to geotag a photo with, so there was nowhere honest for
/// one to come from. Adds a small preview map of the parsed track (there
/// was none before — this screen showed only stat numbers) with the same
/// "pick a photo, then tap the map to place it" interaction `DrawRouteView`
/// uses, not a guessed location.
struct ImportRouteView: View {
    /// Set when this screen is the landing point for a file shared in from
    /// outside the app (Files' "Open In"/"Copy to Nomad", or another app's
    /// Share Sheet — see `PendingImportCoordinator`) rather than reached by
    /// tapping "Import a file" and picking one here. When set, the file is
    /// parsed automatically on appear — there's no "Choose file" step to
    /// skip, the choosing already happened outside this app.
    var pendingFileURL: URL? = nil
    var onFinish: (RecordResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var parsed: ParsedFile?
    @State private var transport: Transport = .foot
    @State private var photos: [DraftPhoto] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var photoUploadError: String?
    @State private var pendingPhotoUrl: String?
    @State private var previewViewport: Viewport = .styleDefault
    @State private var hasHandledPendingURL = false
    private let importSessionId = UUID().uuidString

    private struct ParsedFile {
        let fileName: String
        let points: [ParsedTrackPoint]
        let waypoints: [ParsedWaypoint]
        let distanceKM: Double
        let ascentM: Double
        let highPointM: Double
    }

    /// Dynamically constructed rather than declared in Info.plist — GPX/KML
    /// aren't system UTTypes, and this is enough for the picker to filter
    /// and show the right icon without an Info.plist UTI export/import
    /// declaration for a two-format, read-only picker.
    private var allowedTypes: [UTType] {
        [UTType(filenameExtension: "gpx"), UTType(filenameExtension: "kml"), .xml].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header.padding(.horizontal, 26).padding(.top, 20)
                if let parsed {
                    // A ScrollView now that a preview map + photo controls
                    // can push this past one screen on smaller phones —
                    // the plain fixed VStack below was fine when this was
                    // just three stat rows.
                    ScrollView(showsIndicators: false) {
                        previewContent(parsed).padding(.horizontal, 26).padding(.bottom, 24)
                    }
                } else {
                    intro.padding(.horizontal, 26).padding(.bottom, 24)
                    Spacer()
                }
            }
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: allowedTypes, onCompletion: handlePicked)
        .task {
            guard let pendingFileURL, !hasHandledPendingURL else { return }
            hasHandledPendingURL = true
            handlePicked(.success(pendingFileURL))
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NTColor.milk(0.08)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Import a file").font(NTFont.body(15, .semibold))
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isParsing {
                ProgressView().tint(NTColor.milk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
            } else {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(NTColor.water)
                    .padding(.top, 50)

                Text("Import a GPX\nor KML file")
                    .font(NTFont.heading(30, .extraBold))
                    .foregroundStyle(NTColor.milk)

                Text("Export a track from Garmin Connect, Strava, AllTrails, Komoot or any app that saves a GPX or KML file.")
                    .font(NTFont.body(14, .light))
                    .foregroundStyle(NTColor.milk(0.62))

                if let errorMessage {
                    Text(errorMessage)
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(NTColor.hardBright)
                }

                Button {
                    showPicker = true
                } label: {
                    Text("Choose file")
                        .font(NTFont.body(15, .semibold))
                        .foregroundStyle(Color(hex: 0x231007))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(NTColor.water, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private func previewContent(_ parsed: ParsedFile) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(NTColor.sage)
                Text(parsed.fileName)
                    .font(NTFont.heading(20, .bold))
                    .foregroundStyle(NTColor.milk)
                    .lineLimit(1)
                Text("\(parsed.points.count) points read")
                    .font(NTFont.mono(11, .medium)).tracking(0.4)
                    .foregroundStyle(NTColor.milk(0.5))
                if !parsed.waypoints.isEmpty {
                    Text("\(parsed.waypoints.count) waypoint\(parsed.waypoints.count == 1 ? "" : "s") → pins")
                        .font(NTFont.mono(11, .medium)).tracking(0.4)
                        .foregroundStyle(NTColor.water)
                }
            }
            .padding(.top, 30)

            HStack(spacing: 0) {
                stat(String(format: "%.2f", parsed.distanceKM), "KM", "DISTANCE")
                stat(String(format: "%.0f", parsed.ascentM), "M", "ASCENT")
                stat(String(format: "%.0f", parsed.highPointM), "M", "HIGH POINT")
            }
            .padding(20)
            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))

            previewMap(parsed)

            VStack(alignment: .leading, spacing: 10) {
                Text("TRANSPORT").font(NTFont.mono(9.5, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                TransportPicker(selection: $transport)
            }

            Button {
                finish(parsed)
            } label: {
                Text("Use this track")
                    .font(NTFont.body(15, .semibold))
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                self.parsed = nil
            } label: {
                Text("Choose a different file")
                    .font(NTFont.body(13.5, .medium))
                    .foregroundStyle(NTColor.milk(0.6))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private func previewMap(_ parsed: ParsedFile) -> some View {
        let coordinates = parsed.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("ROUTE PREVIEW").font(NTFont.mono(9.5, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                Spacer()
                if pendingPhotoUrl != nil {
                    Text("TAP TO PLACE PHOTO")
                        .font(NTFont.mono(9.5, .semibold)).tracking(0.6)
                        .foregroundStyle(NTColor.water)
                }
            }
            ZStack {
                Map(viewport: $previewViewport) {
                    if coordinates.count > 1 {
                        PolylineAnnotation(lineCoordinates: coordinates)
                            .lineColor(UIColor(NTColor.accent))
                            .lineWidth(3.5)
                            .lineJoin(.round)
                    }
                    ForEvery(photos, id: \.id) { photo in
                        if let lat = photo.lat, let lng = photo.lng {
                            MapViewAnnotation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                                photoMarker
                            }
                        }
                    }
                    // Real `<wpt>` pins from the file itself — shown here
                    // immediately so "waypoints became pins" is visible
                    // before the user even reaches the next screen, not a
                    // promise that only turns out true later.
                    ForEvery(Array(parsed.waypoints.enumerated()), id: \.offset) { _, waypoint in
                        MapViewAnnotation(coordinate: CLLocationCoordinate2D(latitude: waypoint.lat, longitude: waypoint.lng)) {
                            POIMapMarker(category: .other)
                        }
                    }
                }
                .mapStyle(.standard)
                .onMapTapGesture { context in
                    guard let url = pendingPhotoUrl else { return }
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(NTMotion.spring) {
                        photos.append(DraftPhoto(imageUrl: url, lat: context.coordinate.latitude, lng: context.coordinate.longitude))
                        pendingPhotoUrl = nil
                    }
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
            .onAppear {
                previewViewport = Viewport.fitting(coordinates, padding: EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
            }

            if let photoUploadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12))
                    Text(LocalizedStringKey(photoUploadError)).font(NTFont.body(12, .medium))
                }
                .foregroundStyle(Color(hex: 0xE58272))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(hex: 0xB33A2B).opacity(0.18), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                HStack(spacing: 9) {
                    if isUploadingPhoto {
                        ProgressView().tint(NTColor.milk(0.7))
                    } else {
                        Image(systemName: "camera.fill").font(.system(size: 13))
                    }
                    addPhotoLabel.font(NTFont.body(13, .medium))
                }
                .foregroundStyle(NTColor.milk(0.75))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(NTColor.milk(0.08), in: Capsule())
                .overlay(Capsule().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .disabled(isUploadingPhoto || pendingPhotoUrl != nil)
        }
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                isUploadingPhoto = true
                withAnimation { photoUploadError = nil }
                defer { isUploadingPhoto = false; photoPickerItem = nil }
                let data: Data
                do {
                    guard let loaded = try await newItem.loadTransferable(type: Data.self) else {
                        withAnimation { photoUploadError = "Couldn't read that photo — try picking it again." }
                        return
                    }
                    data = loaded
                } catch {
                    withAnimation { photoUploadError = "Couldn't load that photo (it may still be downloading from iCloud) — try again." }
                    return
                }
                do {
                    let url = try await RouteRepository.shared.uploadRoutePhotoFile(data, routeId: importSessionId)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation { pendingPhotoUrl = url }
                } catch {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    withAnimation { photoUploadError = "Upload failed — check your connection and try again." }
                }
            }
        }
        .onChange(of: photoUploadError) { _, newValue in
            guard newValue != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                withAnimation { photoUploadError = nil }
            }
        }
    }

    private var addPhotoLabel: Text {
        if pendingPhotoUrl != nil {
            return Text("Now tap the map…")
        }
        if photos.isEmpty {
            return Text("Add a photo")
        }
        return Text("Add another photo") + Text(verbatim: " (\(photos.count))")
    }

    private var photoMarker: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(NTColor.water))
            .overlay(Circle().stroke(NTColor.milk, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    private func stat(_ value: String, _ unit: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            (Text(value).font(NTFont.mono(16, .semibold)) + Text(" " + unit).font(NTFont.mono(9, .medium)).foregroundStyle(NTColor.milk(0.55)))
            Text(label).font(NTFont.mono(8.5, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        errorMessage = nil
        switch result {
        case .failure:
            errorMessage = "Couldn't open that file — try again."
        case .success(let url):
            isParsing = true
            Task {
                defer { isParsing = false }
                let needsSecurityScope = url.startAccessingSecurityScopedResource()
                defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let result = try RouteFileParser.parse(fileURL: url)
                    let coordinates = result.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    let elevations = result.points.compactMap(\.elevation)
                    parsed = ParsedFile(
                        fileName: url.lastPathComponent,
                        points: result.points,
                        waypoints: result.waypoints,
                        distanceKM: TrackMath.distanceKM(coordinates),
                        ascentM: elevations.isEmpty ? 0 : TrackMath.ascentM(elevations),
                        highPointM: elevations.isEmpty ? 0 : TrackMath.highPointM(elevations)
                    )
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
                }
            }
        }
    }

    private func finish(_ parsed: ParsedFile) {
        let trackPoints = TrackMath.downsample(parsed.points.map { TrackPoint(lat: $0.lat, lng: $0.lng) })
        // Real `<wpt>` entries become real pins — the same `DraftPOI` shape
        // and the same publish pipeline `RecordTrackView`'s live-dropped
        // pins already use, so nothing downstream needed to change.
        let waypointPOIs = parsed.waypoints.map { waypoint in
            DraftPOI(lat: waypoint.lat, lng: waypoint.lng, category: .other, title: waypoint.name ?? "Waypoint")
        }
        onFinish(RecordResult(
            distanceKM: parsed.distanceKM, ascentM: parsed.ascentM, highPointM: parsed.highPointM,
            points: trackPoints, pois: waypointPOIs, photos: photos, transport: transport
        ))
    }
}

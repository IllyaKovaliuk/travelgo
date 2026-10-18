import SwiftUI
import MapboxMaps
import CoreLocation
import PhotosUI

/// 14c · Draw — the third "how did you get the line" option that did
/// nothing before this. Tap the satellite map to lay down waypoints;
/// distance is real (`TrackMath.distanceKM`, same ground-distance math as
/// a live recording), ascent/high point are honestly 0 — tapping a flat
/// map screen has no elevation data, and this app has never fabricated a
/// stat it can't back with something real. Feeds the same `RecordResult`
/// pipeline `RecordTrackView`/`ImportRouteView` do.
///
/// Photos — previously the one producer of `RecordResult` with no photo
/// step at all, which is exactly why a drawn route could never show a
/// photo pin on its map no matter what: there was structurally nothing to
/// geotag. Same `PhotosPicker` → `uploadRoutePhotoFile` pipeline
/// `RecordTrackView` uses, but geotagged by a deliberate tap on the map
/// (picked photo "arms" placement mode, the header hint swaps to say so,
/// the next tap places it) rather than "wherever the user physically is
/// right now" — there's no live GPS fix to borrow here, and a guessed
/// location would be a lie `RecordTrackView`'s version never has to tell.
struct DrawRouteView: View {
    var onFinish: (RecordResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var transport: Transport = .foot
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 15), zoom: 1.6, bearing: 0, pitch: 0
    )
    @State private var photos: [DraftPhoto] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var photoUploadError: String?
    /// Non-nil the instant a picked photo finishes uploading — the next
    /// map tap consumes it (places the pin) instead of adding a path
    /// point. `uploadRoutePhotoFile` wants a route id to group storage
    /// paths under; same role as `RecordTrackView.recordingSessionId`.
    @State private var pendingPhotoUrl: String?
    private let drawSessionId = UUID().uuidString

    private var distanceKM: Double { TrackMath.distanceKM(points) }

    var body: some View {
        ZStack(alignment: .top) {
            Map(viewport: $viewport) {
                if points.count > 1 {
                    PolylineAnnotation(lineCoordinates: points)
                        .lineColor(UIColor(NTColor.accent))
                        .lineWidth(4)
                        .lineJoin(.round)
                        .lineOpacity(0.95)
                }
                ForEvery(Array(points.enumerated()), id: \.offset) { index, coordinate in
                    MapViewAnnotation(coordinate: coordinate) {
                        pointMarker(isLast: index == points.count - 1)
                    }
                }
                ForEvery(photos, id: \.id) { photo in
                    if let lat = photo.lat, let lng = photo.lng {
                        MapViewAnnotation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng)) {
                            photoMarker
                        }
                    }
                }
            }
            .mapStyle(NomadMap.style(satellite: false))
            .onMapTapGesture { context in
                if let url = pendingPhotoUrl {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(NTMotion.spring) {
                        photos.append(DraftPhoto(imageUrl: url, lat: context.coordinate.latitude, lng: context.coordinate.longitude))
                        pendingPhotoUrl = nil
                    }
                } else {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(NTMotion.spring) { points.append(context.coordinate) }
                }
            }
            .ignoresSafeArea()

            VStack {
                header
                Spacer()
                bottomPanel
            }
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(pendingPhotoUrl != nil ? "Tap the map to place this photo" : "Tap to lay down the path")
                .font(NTFont.mono(11, .semibold)).tracking(0.6)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(pendingPhotoUrl != nil ? NTColor.water.opacity(0.75) : NTColor.pine.opacity(0.75)))
                .overlay(Capsule().stroke(NTColor.milk(0.18), lineWidth: 1))

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _ = withAnimation(NTMotion.spring) { points.popLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(points.isEmpty)
            .opacity(points.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private func pointMarker(isLast: Bool) -> some View {
        Circle()
            .fill(isLast ? NTColor.accent : NTColor.milk)
            .frame(width: isLast ? 12 : 8, height: isLast ? 12 : 8)
            .overlay(Circle().stroke(NTColor.pine, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    /// Three real `Text(_:)` branches, not a ternary of string literals —
    /// a ternary of plain literals resolves to `Text(String)` and silently
    /// never localizes (same trap caught and fixed in
    /// `RouteDetailView.downloadButtonLabel`).
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

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                stat(String(format: "%.2f", distanceKM), "KM", "DISTANCE")
                stat("\(points.count)", "", "POINTS")
            }

            TransportPicker(selection: $transport)

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

            HStack(spacing: 12) {
                Button {
                    withAnimation(NTMotion.spring) { points.removeAll() }
                } label: {
                    Text("Clear")
                        .font(NTFont.body(14, .semibold))
                        .foregroundStyle(NTColor.milk(0.7))
                        .frame(width: 90, height: 54)
                        .background(NTColor.milk(0.1), in: Capsule())
                        .overlay(Capsule().stroke(NTColor.milk(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(points.isEmpty)
                .opacity(points.isEmpty ? 0.4 : 1)

                Button {
                    finish()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Use this path").font(NTFont.body(15, .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(points.count < 2)
                .opacity(points.count < 2 ? 0.4 : 1)
            }
        }
        .padding(18)
        .background(NTColor.pine.opacity(0.92), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                isUploadingPhoto = true
                withAnimation { photoUploadError = nil }
                defer { isUploadingPhoto = false; photoPickerItem = nil }
                // Same real do/catch RecordTrackView's photo upload uses —
                // no silent `try?` swallow, real distinct messages for the
                // two most common real failures.
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
                    let url = try await RouteRepository.shared.uploadRoutePhotoFile(data, routeId: drawSessionId)
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

    private func stat(_ value: String, _ unit: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(value).font(NTFont.mono(20, .semibold)) + Text(unit.isEmpty ? "" : " " + unit).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55)))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finish() {
        let trackPoints = points.map { TrackPoint(lat: $0.latitude, lng: $0.longitude) }
        onFinish(RecordResult(distanceKM: distanceKM, ascentM: 0, highPointM: 0, points: trackPoints, pois: [], photos: photos, transport: transport))
    }
}

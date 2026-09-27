import SwiftUI
import PhotosUI

struct RecordResult {
    let distanceKM: Double
    let ascentM: Double
    let highPointM: Double
    let points: [TrackPoint]
    let pois: [DraftPOI]
    /// Defaults empty so `ImportRouteView`/`DrawRouteView` (the other two
    /// producers of `RecordResult`, neither of which offers a photo step)
    /// don't need to change at all.
    let photos: [DraftPhoto]
    /// The transport actually selected during recording (see
    /// `RecordTrackView.transport`) — real now, rather than always landing
    /// on `NewRouteDraft`'s silent `.overland` default.
    let transport: Transport

    init(distanceKM: Double, ascentM: Double, highPointM: Double, points: [TrackPoint], pois: [DraftPOI], photos: [DraftPhoto] = [], transport: Transport) {
        self.distanceKM = distanceKM
        self.ascentM = ascentM
        self.highPointM = highPointM
        self.points = points
        self.pois = pois
        self.photos = photos
        self.transport = transport
    }
}

/// 14 · Recording — live. Real CoreLocation recording via `RouteTracker`:
/// distance/ascent/the stored polyline all come from actual GPS fixes, not
/// a simulated pace. Elapsed time is real wall-clock time.
struct RecordTrackView: View {
    var onFinish: (RecordResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tracker = RouteTracker()
    /// Real wall-clock bookkeeping instead of a per-second incremented
    /// counter — `Timer.publish` does not fire while the app is suspended
    /// in the background, so an incremented counter would silently
    /// under-count by however long the phone sat backgrounded (and the
    /// Live Activity, fed from the same value, would show the same stale
    /// time). Deriving `elapsed` from `Date()` self-heals the instant the
    /// timer resumes ticking in the foreground, no matter how long the gap
    /// was — this is the same pattern the SOS Live Activity state already
    /// uses (`Date.now.timeIntervalSince(triggeredAt)`).
    @State private var recordingStartedAt = Date()
    @State private var pausedAccumulated: TimeInterval = 0
    @State private var pauseStartedAt: Date?
    @State private var isPaused = false
    /// Wasn't chosen anywhere before this — the details step afterward
    /// (`RouteUploadDetailsView`) picked it up from `NewRouteDraft`'s
    /// silent `.overland` default. Choosing it here for real, before/while
    /// recording, is what makes the Live Activity's transport icon a real
    /// reflection of what's happening instead of a hardcoded hiking glyph.
    /// `LogRouteFlow.onFinish` now seeds `draft.transport` from this too.
    @State private var transport: Transport = .foot
    @State private var droppedPOIs: [DraftPOI] = []
    @State private var pendingPin: TrackPoint?
    @State private var showSOS = false
    // Part 2a — photos geotagged live, mid-recording. `photoPickerItem` is
    // PhotosUI's own selection handle, not the photo itself; the real
    // upload happens in `.onChange` below once its `Data` loads.
    @State private var droppedPhotos: [DraftPhoto] = []
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    /// `uploadRoutePhotoFile` wants a route id to group storage paths under
    /// — there isn't a real one yet mid-recording (the route doesn't exist
    /// until publish), so this is just an opaque per-session grouping key,
    /// same role `DraftPOI`/`DraftPhoto` already play for the DB row.
    private let recordingSessionId = UUID().uuidString
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            terrain

            VStack {
                header
                Spacer()
                if tracker.authorizationDenied {
                    locationDeniedCard
                } else {
                    TransportPicker(selection: $transport, onChange: { _ in pushIslandUpdate() })
                        .padding(.horizontal, 22).padding(.bottom, 12)
                    statsCard
                    if !droppedPOIs.isEmpty || !droppedPhotos.isEmpty {
                        droppedPinsRow.padding(.horizontal, 22).padding(.top, 12)
                    }
                }
                Spacer().frame(height: 18)
                controls
            }
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            recordingStartedAt = Date()
            tracker.start()
            LiveActivityManager.shared.startRecording(
                routeName: nil, transportIcon: transport.icon, transportColorHex: transport.colorHexValue
            )
        }
        .onDisappear {
            tracker.stop()
            // Covers leaving via the X button (abandoned, never hit
            // Finish) — idempotent with the explicit call in Finish below.
            LiveActivityManager.shared.endRecording()
        }
        .onReceive(timer) { _ in
            // Just a redraw tick now — `elapsed` is computed from real
            // timestamps (see its declaration above), so this doesn't need
            // to do the incrementing itself, only wake the view up once a
            // second so the on-screen clock visibly moves.
            guard !isPaused else { return }
            // Throttled — the island's own elapsed timer ticks visually on
            // its own, this just needs to keep distance/ascent/speed fresh.
            if Int(elapsed) % 5 == 0 {
                pushIslandUpdate()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .nomadIslandTogglePause)) { _ in
            togglePause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .nomadIslandFinish)) { _ in
            finishRecording()
        }
        .fullScreenCover(isPresented: $showSOS) {
            SOSView(
                onClose: { showSOS = false },
                onTriggered: { LiveActivityManager.shared.triggerSOS() },
                onCancelled: { LiveActivityManager.shared.cancelSOS() }
            )
        }
        .sheet(isPresented: Binding(get: { pendingPin != nil }, set: { if !$0 { pendingPin = nil } })) {
            if let pin = pendingPin {
                DropPinSheet(onSave: { category, title, note in
                    droppedPOIs.append(DraftPOI(lat: pin.lat, lng: pin.lng, category: category, title: title, note: note))
                    pendingPin = nil
                }, onCancel: { pendingPin = nil })
                .presentationDetents([.medium])
            }
        }
    }

    private var droppedPinsRow: some View {
        HStack(spacing: 14) {
            if !droppedPOIs.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").font(.system(size: 14)).foregroundStyle(NTColor.sage)
                    Text("\(droppedPOIs.count) PIN\(droppedPOIs.count == 1 ? "" : "S") DROPPED")
                        .font(NTFont.mono(10.5, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
                }
            }
            if !droppedPhotos.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "photo.fill").font(.system(size: 13)).foregroundStyle(NTColor.water)
                    Text("\(droppedPhotos.count) PHOTO\(droppedPhotos.count == 1 ? "" : "S")")
                        .font(NTFont.mono(10.5, .semibold)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
                }
            }
            Spacer()
        }
    }

    private var locationDeniedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill").font(.system(size: 26)).foregroundStyle(Color(hex: 0xE58272))
            Text("Location access needed to record a track").font(NTFont.body(14.5, .semibold))
            Text("Enable it in Settings to log real distance, ascent and your path.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 22)
    }

    private var terrain: some View {
        ZStack {
            NTColor.pineDeep.ignoresSafeArea()
            // Flat ground + a faint straight-line contour pattern instead of
            // the old soft organic blobs — still reads as "terrain," just
            // without the decorative shapes that don't belong in this
            // aesthetic anymore.
            TopoLines(lineCount: 6, spacing: 28)
                .stroke(NTColor.pineShadow, lineWidth: 1)
                .opacity(0.6)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xE58272)).frame(width: 7, height: 7)
                    .opacity(isPaused ? 1 : 0.4)
                    .overlay(
                        Circle().fill(Color(hex: 0xE58272))
                            .scaleEffect(isPaused ? 1 : 1.8)
                            .opacity(isPaused ? 0 : 0.6)
                            .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: isPaused)
                    )
                Text(isPaused ? "PAUSED" : "RECORDING")
                    .font(NTFont.mono(11, .semibold)).tracking(0.8)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color(hex: 0xB33A2B).opacity(0.25)))
            .overlay(Capsule().stroke(Color(hex: 0xB33A2B).opacity(0.5), lineWidth: 1))

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showSOS = true
            } label: {
                Image(systemName: "sos")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xE58272))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var statsCard: some View {
        VStack(spacing: 16) {
            Text(formattedTime)
                .font(NTFont.mono(46, .semibold))
                .contentTransition(.numericText())

            HStack(spacing: 0) {
                stat(String(format: "%.2f", tracker.distanceKM), "KM", "DISTANCE")
                stat(String(format: "%.0f", tracker.ascentM), "M", "ASCENT")
                stat(String(format: "%.1f", tracker.distanceKM > 0 ? tracker.distanceKM / (elapsed / 3600 + 0.001) : 0), "KM/H", "AVG SPEED")
            }
        }
        .padding(24)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 22)
    }

    private func stat(_ value: String, _ unit: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 6) {
            (Text(value).font(NTFont.mono(18, .semibold)) + Text(" " + unit).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55)))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                togglePause()
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1.4))
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                finishRecording()
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish").font(NTFont.body(15, .semibold))
                }
                .foregroundStyle(NTColor.pine)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)
            .ntPressable()

            Button {
                guard let here = tracker.points.last else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                pendingPin = here
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 17))
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1.4))
            }
            .buttonStyle(.plain)
            .disabled(tracker.points.isEmpty)
            .opacity(tracker.points.isEmpty ? 0.4 : 1)

            // Part 2a — same geotagged-to-here idea as the pin button
            // above, just carrying a real photo instead of a note. Disabled
            // while uploading (not while `tracker.points.isEmpty`, unlike
            // the pin — the very first fix hasn't landed yet in that
            // window, but a photo taken in the first second or two of a
            // recording is still real and still worth keeping, just
            // without a geotag).
            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                if isUploadingPhoto {
                    ProgressView().tint(NTColor.milk)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(NTColor.milk(0.1)))
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1.4))
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 17))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(NTColor.milk(0.1)))
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1.4))
                }
            }
            .disabled(isUploadingPhoto)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .onChange(of: photoPickerItem) { _, newItem in
            guard let newItem else { return }
            let here = tracker.points.last
            Task {
                isUploadingPhoto = true
                defer { isUploadingPhoto = false; photoPickerItem = nil }
                guard let data = try? await newItem.loadTransferable(type: Data.self) else { return }
                guard let url = try? await RouteRepository.shared.uploadRoutePhotoFile(data, routeId: recordingSessionId) else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                droppedPhotos.append(DraftPhoto(imageUrl: url, lat: here?.lat, lng: here?.lng))
            }
        }
    }

    /// Wall-clock elapsed time since `recordingStartedAt`, minus however
    /// long has been spent paused — accurate even across a stretch where
    /// the app was backgrounded and `timer` above never fired.
    private var elapsed: TimeInterval {
        var total = Date().timeIntervalSince(recordingStartedAt) - pausedAccumulated
        if let pauseStartedAt {
            total -= Date().timeIntervalSince(pauseStartedAt)
        }
        return max(0, total)
    }

    private var formattedTime: String {
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }

    /// Shared by the in-app Pause button and the island's own Pause/Resume
    /// button (`ToggleRecordingPauseIntent`, via NotificationCenter) so
    /// both paths stay identical.
    private func togglePause() {
        withAnimation { isPaused.toggle() }
        if isPaused {
            pauseStartedAt = Date()
            tracker.pause()
        } else {
            if let pauseStartedAt {
                pausedAccumulated += Date().timeIntervalSince(pauseStartedAt)
            }
            pauseStartedAt = nil
            tracker.resume()
        }
        // Not on the periodic throttle — the island's PAUSED state and
        // button label shouldn't lag behind a toggle that just happened.
        pushIslandUpdate()
    }

    /// Shared by the in-app Finish button and the island's own Finish
    /// button (`FinishRecordingIntent`, via NotificationCenter).
    private func finishRecording() {
        tracker.stop()
        LiveActivityManager.shared.endRecording()
        onFinish(RecordResult(
            distanceKM: tracker.distanceKM, ascentM: tracker.ascentM, highPointM: tracker.highPointM,
            points: tracker.storedPoints, pois: droppedPOIs, photos: droppedPhotos, transport: transport
        ))
    }

    private func pushIslandUpdate() {
        let avgSpeed = tracker.distanceKM > 0 ? tracker.distanceKM / (elapsed / 3600 + 0.001) : 0
        LiveActivityManager.shared.updateRecording(.init(
            distanceKM: tracker.distanceKM, elapsedSeconds: Int(elapsed), ascentM: tracker.ascentM,
            avgSpeedKMH: avgSpeed, isPaused: isPaused,
            transportIcon: transport.icon, transportColorHex: transport.colorHexValue
        ))
    }
}

private extension Transport {
    /// `dbHex` ("#RRGGBB") converted once to the `UInt32` `NTColor.init(hex:)`
    /// already takes — avoids a second hex-string parser existing in the
    /// widget extension target just for this.
    var colorHexValue: UInt32 { UInt32(dbHex.dropFirst(), radix: 16) ?? 0x5FA777 }
}

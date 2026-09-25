import SwiftUI
import MapboxMaps
import CoreLocation
import AVFoundation

/// 06b · Navigation mode — the real "Navigate" destination from Route
/// Detail (was a plain compass dial before; that's still reachable from
/// here via the compass-icon button, not removed). A locked, pitched,
/// heading-following 3D camera via Mapbox's own `Viewport.followPuck` —
/// not hand-rolled camera interpolation, Mapbox already does the smooth
/// tracking/anti-jitter work `followPuck` exists for.
///
/// Guidance is real trail geometry, not routing-engine turn-by-turn — this
/// app records and replays a GPS track, it doesn't route against a road
/// network (see `TrackGuidance`'s own doc comment). Off-track detection,
/// remaining distance and ETA are all computed by `NavigationSession`
/// against the route's actual recorded/smoothed polyline.
struct NavigationModeView: View {
    let route: Route
    var onClose: () -> Void

    @State private var session: NavigationSession
    @State private var viewport: Viewport
    @State private var showSOS = false
    @State private var showCompass = false
    @State private var voice = VoiceAnnouncer()

    private let stretches: [MapSegmentStretch]

    init(route: Route, onClose: @escaping () -> Void) {
        self.route = route
        self.onClose = onClose
        let stretches = MapSegmentStretch.compute(trackPoints: route.detail.trackPoints, segments: route.detail.segments)
        self.stretches = stretches
        _session = State(initialValue: NavigationSession(stretches: stretches, totalDistanceKM: route.distanceKM))
        // Waze/Maps-style locked 3D chase camera — pitched toward the
        // horizon, rotated to the live course. Mapbox's own recommendation
        // is to transition into `followPuck` with the default animation
        // (see `Viewport.followPuck`'s doc comment), so this is the
        // starting viewport, not something animated into after the fact.
        _viewport = State(initialValue: .followPuck(zoom: 18, bearing: .course, pitch: 65))
    }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer

            VStack(spacing: 0) {
                topControls

                if session.authorizationDenied {
                    locationDeniedCard.padding(.horizontal, 14).padding(.top, 10)
                } else {
                    if let guidance = session.guidance {
                        maneuverBanner(guidance)
                            .padding(.horizontal, 14)
                            .padding(.top, 10)
                    }
                    if session.isOffTrack {
                        offTrackBanner
                    }
                }

                Spacer(minLength: 0)
                bottomHUD
            }
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .onChange(of: session.traveledDistanceKM) { _, _ in
            voice.announce(session.guidance)
        }
        .onChange(of: session.isOffTrack) { _, isOff in
            if isOff { voice.announceOffTrack() }
        }
        .fullScreenCover(isPresented: $showSOS) {
            SOSView(
                onClose: { showSOS = false },
                onTriggered: { LiveActivityManager.shared.triggerSOS() },
                onCancelled: { LiveActivityManager.shared.cancelSOS() }
            )
        }
        .fullScreenCover(isPresented: $showCompass) {
            CompassView(
                routeId: route.id, segments: route.detail.segments,
                trackPoints: route.detail.trackPoints, pois: route.detail.pois,
                onClose: { showCompass = false }
            )
        }
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(viewport: $viewport) {
            RouteSegmentMapContent(stretches: stretches, showLabels: false)
            Puck2D(bearing: .course)
                .showsAccuracyRing(true)
                .accuracyRingColor(UIColor(NTColor.accent).withAlphaComponent(0.15))
                .accuracyRingBorderColor(UIColor(NTColor.accent).withAlphaComponent(0.5))
        }
        .mapStyle(.standardSatellite)
        .ignoresSafeArea()
    }

    // MARK: - Top controls

    private var topControls: some View {
        HStack {
            Spacer()
            iconButton("location.north.line.fill", tint: NTColor.milk) { showCompass = true }
            iconButton("sos", tint: NTColor.hardBright) { showSOS = true }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func iconButton(_ systemName: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(NTColor.pine.opacity(0.75)))
                .overlay(Circle().stroke(NTColor.milk(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Maneuver banner

    private func maneuverBanner(_ guidance: TrackGuidance) -> some View {
        HStack(spacing: 16) {
            Image(systemName: guidance.direction.icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(NTColor.pine)
                .frame(width: 64, height: 64)
                .background(Circle().fill(NTColor.accent))

            VStack(alignment: .leading, spacing: 4) {
                Text(Self.formattedDistance(guidance.distanceToTurnM))
                    .font(NTFont.mono(28, .semibold))
                    .foregroundStyle(NTColor.milk)
                    .contentTransition(.numericText())
                if let label = guidance.label {
                    Text(label)
                        .font(NTFont.body(14, .medium))
                        .foregroundStyle(NTColor.milk(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(NTColor.pine.opacity(0.92), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
    }

    private var offTrackBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(NTColor.milk)
            Text("OFF ROUTE — \(Int(session.distanceFromTrackM.rounded())) M FROM TRACK")
                .font(NTFont.mono(11, .semibold)).tracking(0.4)
            Spacer(minLength: 0)
        }
        .foregroundStyle(NTColor.milk)
        .padding(.horizontal, 16).padding(.vertical, 11)
        .background(NTColor.hard.opacity(0.9), in: Capsule())
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var locationDeniedCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.slash.fill").font(.system(size: 22)).foregroundStyle(NTColor.hardBright)
            Text("Location access needed to navigate")
                .font(NTFont.body(14, .semibold))
            Text("Enable it in Settings to track your position against this route.")
                .font(NTFont.body(12, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(18)
        .background(NTColor.pine.opacity(0.92), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
    }

    // MARK: - Bottom HUD

    private var bottomHUD: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                hudStat(String(format: "%.0f", session.speedKMH), "KM/H")
                hudStat(etaText, "ETA")
                hudStat(String(format: "%.1f", session.remainingDistanceKM), "KM LEFT")
                hudStat(session.altitudeM > 0 ? "\(Int(session.altitudeM.rounded()))" : "—", "ALT M")
            }

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.default) { viewport = .followPuck(zoom: 18, bearing: .course, pitch: 65) }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(NTColor.milk(0.1)))
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    voice.isEnabled.toggle()
                } label: {
                    Image(systemName: voice.isEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 54, height: 54)
                        .background(Circle().fill(NTColor.milk(0.1)))
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    session.stop()
                    onClose()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark")
                        Text("End").font(NTFont.body(15, .semibold))
                    }
                    .foregroundStyle(NTColor.milk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(NTColor.hard, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(NTColor.pine.opacity(0.92), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: -2)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }

    private func hudStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(NTFont.mono(17, .semibold)).contentTransition(.numericText())
            Text(label).font(NTFont.mono(9, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var etaText: String {
        guard let eta = session.etaDate else { return "—" }
        return eta.formatted(date: .omitted, time: .shortened)
    }

    private static func formattedDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1f km", meters / 1000) : "\(Int(meters.rounded())) m"
    }
}

/// Real spoken guidance via on-device `AVSpeechSynthesizer` — not just a
/// UI toggle that quietly does nothing, which is exactly the kind of
/// placeholder this app has repeatedly replaced with the real thing
/// elsewhere (file import, draw-on-map, social sign-in). Debounced by a
/// (direction, distance-bucket) key so the same turn doesn't get announced
/// on every single location tick — only when it's actually new information.
@MainActor
@Observable
final class VoiceAnnouncer {
    var isEnabled = true
    private let synthesizer = AVSpeechSynthesizer()
    private var lastKey: String?
    private var announcedOffTrack = false

    func announce(_ guidance: TrackGuidance?) {
        guard isEnabled, let guidance, guidance.direction != .straight else { return }
        let bucket: String
        if guidance.distanceToTurnM < 30 { bucket = "near" }
        else if guidance.distanceToTurnM < 150 { bucket = "mid" }
        else { return } // too far out to be useful guidance yet

        let key = "\(guidance.direction)-\(bucket)"
        guard key != lastKey else { return }
        lastKey = key
        speak(phrase(for: guidance, bucket: bucket))
    }

    func announceOffTrack() {
        guard isEnabled, !announcedOffTrack else { return }
        announcedOffTrack = true
        speak("You're off route.")
    }

    private func phrase(for guidance: TrackGuidance, bucket: String) -> String {
        let base: String
        switch guidance.direction {
        case .straight: base = "Continue straight"
        case .bearLeft: base = "Bear left"
        case .bearRight: base = "Bear right"
        case .sharpLeft: base = "Sharp left ahead"
        case .sharpRight: base = "Sharp right ahead"
        }
        return bucket == "near" ? base : "\(base) in \(Int(guidance.distanceToTurnM)) meters"
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
    }
}

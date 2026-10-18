import SwiftUI
import MapboxMaps
import CoreLocation

// MARK: - Map layers

/// Glowing amber/red contours over risky stretches of the route, the radar
/// frames (one raster layer each, cross-faded by opacity), and the scrub
/// marker. Takes plain values so SwiftUI re-renders it when they change.
struct MeteoMapContent: MapContent {
    /// The whole route as colored runs: green = clear, yellow = caution, red = danger.
    let segments: [RiskSegment]
    let radarFrames: [RadarFrame]
    let radarIndex: Int
    let radarEnabled: Bool
    let scrubCoordinate: CLLocationCoordinate2D?
    let scrubRisk: StormRisk

    /// RainViewer renders tiles only up to zoom 7; Mapbox over-zooms above that.
    private static func radarSource(_ frame: RadarFrame) -> RasterSource {
        var source = RasterSource(id: "meteo-radar-src-\(frame.id)")
        source.tiles = [frame.tileURL]
        source.tileSize = 256
        source.maxzoom = 7
        return source
    }

    var body: some MapContent {
        if radarEnabled {
            ForEvery(radarFrames) { frame in
                Self.radarSource(frame)
                RasterLayer(id: "meteo-radar-lyr-\(frame.id)", source: "meteo-radar-src-\(frame.id)")
                    .rasterOpacity(frame.id == radarIndex ? 0.7 : 0)
                    .rasterOpacityTransition(StyleTransition(duration: 0.45, delay: 0))
                    .rasterFadeDuration(0)
            }
        }

        ForEvery(segments) { segment in
            let sourceId = "meteo-risk-\(segment.id)"
            GeoJSONSource(id: sourceId).data(.geometry(.lineString(LineString(segment.coordinates))))
            // Outer glow — stronger the worse the weather
            LineLayer(id: "\(sourceId)-glow", source: sourceId)
                .lineColor(UIColor(segment.risk.color))
                .lineWidth(segment.risk == .clear ? 18 : 24)
                .lineBlur(10)
                .lineOpacity(segment.risk == .clear ? 0.55 : 0.9)
                .lineCap(.round)
                .lineJoin(.round)
            // Solid colored line with a white edge so it reads on any map
            LineLayer(id: "\(sourceId)-core", source: sourceId)
                .lineColor(UIColor(segment.risk.color))
                .lineWidth(8)
                .lineCap(.round)
                .lineJoin(.round)
                .lineBorderColor(UIColor.white.withAlphaComponent(0.95))
                .lineBorderWidth(2)
        }

        if let scrubCoordinate {
            MapViewAnnotation(coordinate: scrubCoordinate) {
                ZStack {
                    Circle().fill(scrubRisk.color.opacity(0.3)).frame(width: 34, height: 34)
                    Circle().fill(NTColor.ink).frame(width: 16, height: 16)
                    Circle().stroke(scrubRisk.color, lineWidth: 3).frame(width: 16, height: 16)
                }
                .shadow(color: scrubRisk.color.opacity(0.9), radius: 8)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Risk track (scrubber / departure strip)

/// A row of risk-colored cells with a draggable thumb — used both as the
/// route scrubber and as the "when should I leave" danger-window strip.
struct RiskTrack: View {
    let risks: [StormRisk]
    @Binding var value: Double   // 0…1
    var onChange: ((Double) -> Void)? = nil

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(risks.enumerated()), id: \.offset) { _, risk in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(risk.color.opacity(risk == .clear ? 0.28 : 0.95))
                    }
                }
                .frame(height: 12)
                .shadow(color: .black.opacity(0.3), radius: 2)

                Capsule()
                    .fill(NTColor.milk)
                    .frame(width: 5, height: 26)
                    .shadow(color: .cyan.opacity(0.8), radius: 6)
                    .offset(x: max(0, min(w - 5, value * w - 2.5)))
            }
            .frame(height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let v = max(0, min(1, g.location.x / max(w, 1)))
                    value = v
                    onChange?(v)
                }
            )
        }
        .frame(height: 28)
    }
}

// MARK: - HUD widget

/// Minimal always-on readout: altitude-adjusted temperature, wind (with
/// gusts, labelled), and — for Pro — the honest age of the radar data.
struct MeteoHUDWidget: View {
    let weather: WeatherPoint?
    let showRadar: Bool
    let radarEnabled: Bool
    let radarFailed: Bool
    /// Newest frame's timestamp — the real age of the data.
    let radarLatest: Date?
    /// Frame currently replayed in the loop (not the data age).
    let radarReplayTime: Date?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: weather?.symbol ?? "cloud.fill").foregroundStyle(.cyan)
                Text(weather.map { String(format: "%+.0f°C", $0.temperature) } ?? "--")
                    .font(NTFont.mono(20, .semibold))
            }
            row("ALT", weather.map { String(localized: "\(Int($0.elevationM)) m") } ?? "--")
            row("WIND", weather.map { String(localized: "\(Int($0.wind.rounded())) · G\(Int($0.gust.rounded())) km/h") } ?? "--")
            if showRadar {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let status = radarStatus(now: context.date)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle().fill(status.color).frame(width: 6, height: 6)
                            Text(status.text).font(NTFont.mono(9, .medium)).tracking(0.6)
                                .foregroundStyle(NTColor.milk(0.75))
                        }
                        if radarEnabled, !radarFailed, let t = radarReplayTime {
                            Text("REPLAY \(t.formatted(.dateTime.hour().minute()))")
                                .font(NTFont.mono(8.5, .medium)).tracking(0.5).foregroundStyle(NTColor.milk(0.4))
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .foregroundStyle(NTColor.milk)
        .background(NTColor.pineDeep.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.cyan.opacity(0.55), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.25), radius: 8)
    }

    private func row(_ k: LocalizedStringKey, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).font(NTFont.mono(9, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5)).frame(width: 34, alignment: .leading)
            Text(v).font(NTFont.mono(12, .semibold))
        }
    }

    /// "LIVE" only while the data is fresh (≤ 30 min); otherwise show its age.
    private func radarStatus(now: Date) -> (text: LocalizedStringKey, color: Color) {
        if isLoading { return ("SYNCING…", NTColor.gold) }
        if !radarEnabled { return ("RADAR OFF", NTColor.milk(0.4)) }
        if radarFailed { return ("RADAR OFFLINE", NTColor.hard) }
        guard let latest = radarLatest else { return ("RADAR OFFLINE", NTColor.hard) }
        let minutes = max(0, Int(now.timeIntervalSince(latest) / 60))
        if minutes <= 30 { return ("RADAR LIVE · \(minutes) MIN AGO", NTColor.sage) }
        let age = minutes >= 120 ? String(localized: "\(minutes / 60) H") : String(localized: "\(minutes) MIN")
        return ("RADAR · DATA \(age) OLD", NTColor.gold)
    }
}

// MARK: - Timeline panel

struct MeteoTimelinePanel: View {
    let model: MeteoViewModel
    let onClose: () -> Void

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("METEO-TERMINAL // ROUTE WX")
                    .font(NTFont.mono(10.5, .semibold)).tracking(1).foregroundStyle(.cyan)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.radarEnabled.toggle()
                } label: {
                    Label("RADAR", systemImage: "dot.radiowaves.left.and.right")
                        .font(NTFont.mono(9.5, .semibold)).tracking(0.6)
                        .foregroundStyle(model.radarEnabled ? NTColor.pine : NTColor.milk(0.7))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(model.radarEnabled ? Color.cyan : NTColor.milk(0.1)))
                }.buttonStyle(.plain)
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 26, height: 26)
                        .background(Circle().fill(NTColor.milk(0.12)))
                }.buttonStyle(.plain)
            }

            if model.isLoading {
                HStack(spacing: 8) { ProgressView().tint(.cyan); Text("Pulling forecast…").font(NTFont.body(12.5, .light)) }
                    .padding(.vertical, 20)
            } else if model.failed {
                Text("Couldn't load the forecast. Check your connection and reopen.")
                    .font(NTFont.body(12.5, .light)).foregroundStyle(Color(hex: 0xE58272)).padding(.vertical, 16)
            } else {
                // Departure window strip + one-tap best window
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("DEPART").font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                        Spacer()
                        Text(model.departureOffsetH == 0 ? String(localized: "NOW") : model.departure.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased())
                            .font(NTFont.mono(11, .semibold))
                    }
                    RiskTrack(
                        risks: model.departureRisks,
                        value: Binding(
                            get: { Double(model.departureOffsetH) / Double(MeteoViewModel.maxDepartureOffsetH) },
                            set: { _ in }
                        ),
                        onChange: { v in
                            let h = Int((v * Double(MeteoViewModel.maxDepartureOffsetH)).rounded())
                            if h != model.departureOffsetH { UISelectionFeedbackGenerator().selectionChanged(); model.departureOffsetH = h }
                        }
                    )
                    bestWindowRow
                }

                // Route scrubber
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("ROUTE").font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                        Spacer()
                        Text("KM \(String(format: "%.1f", model.scrubKM)) · ETA \(model.scrubDate.formatted(.dateTime.hour().minute()))")
                            .font(NTFont.mono(11, .semibold))
                    }
                    RiskTrack(risks: model.routeRisks, value: $model.progress)
                    Text(model.paceNote).font(NTFont.body(10, .light)).foregroundStyle(NTColor.milk(0.45))
                }

                if let w = model.currentWeather {
                    HStack(spacing: 8) {
                        readout("TEMP", String(format: "%+.0f°", w.temperature), unit: " ", icon: "thermometer.medium")
                        readout("WIND", "\(Int(w.wind.rounded()))", unit: "gusts \(Int(w.gust.rounded())) km/h", icon: "wind", warn: w.gust >= 30)
                        readout("RAIN", "\(Int(w.probability.rounded()))%", unit: "\(String(format: "%.1f", w.precip)) mm/h", icon: "cloud.rain.fill", warn: w.precip >= 1)
                        readout("ALT", "\(Int(w.elevationM))", unit: "m", icon: "mountain.2.fill")
                    }
                    HStack(alignment: .top, spacing: 6) {
                        Text(w.risk.emoji)
                        if w.risk == .clear {
                            Text("Conditions OK at this point").foregroundStyle(w.risk.color)
                        } else {
                            Text(w.reason).foregroundStyle(w.risk.color)
                        }
                    }
                    .font(NTFont.mono(11, .semibold))
                }
            }
        }
        .padding(14)
        .foregroundStyle(NTColor.milk)
        .background(NTColor.pineDeep.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.2), radius: 14, y: 4)
    }

    /// "Leave 07:00–10:00, done by 13:00 — weather turns ~15:00" + apply button.
    private var bestWindowRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                if let w = model.bestWindow {
                    let fmt: (Date) -> String = { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
                    switch w.risk {
                    case .clear:
                        Text("Leave \(fmt(w.start)) – \(fmt(w.end)), done by \(fmt(w.finishBy))")
                            .foregroundStyle(StormRisk.clear.color)
                    case .caution:
                        Text("No fully clear window in 36 h. Calmest: leave \(fmt(w.start)) (caution)")
                            .foregroundStyle(StormRisk.caution.color)
                    case .danger:
                        Text("No safe window in the next 36 h")
                            .foregroundStyle(StormRisk.danger.color)
                    }
                    if let turns = w.weatherTurnsAt, w.risk == .clear {
                        Text("Weather turns around \(fmt(turns))").foregroundStyle(NTColor.milk(0.55))
                    }
                }
            }
            .font(NTFont.body(10.5, .medium))
            Spacer(minLength: 6)
            if model.bestWindow != nil {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.applyBestWindow()
                } label: {
                    Label("BEST WINDOW", systemImage: "sparkles")
                        .font(NTFont.mono(9.5, .semibold)).tracking(0.5)
                        .foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Capsule().fill(Color.cyan))
                }.buttonStyle(.plain)
            }
        }
    }

    private func readout(_ title: LocalizedStringKey, _ value: String, unit: LocalizedStringKey, icon: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(title).font(NTFont.mono(8.5, .medium)).tracking(0.7)
            }.foregroundStyle(NTColor.milk(0.5))
            Text(value).font(NTFont.mono(16, .semibold)).foregroundStyle(warn ? NTColor.gold : NTColor.milk)
            Text(unit).font(NTFont.mono(9, .medium)).foregroundStyle(NTColor.milk(0.5)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Free-tier teaser

/// Blurred preview of the full terminal with an unlock prompt — the
/// point-weather HUD stays free, the timeline/radar/colored route are Pro.
struct MeteoProTeaser: View {
    let model: MeteoViewModel
    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            MeteoTimelinePanel(model: model, onClose: {})
                .blur(radius: 7)
                .allowsHitTesting(false)
            VStack(spacing: 10) {
                Image(systemName: "lock.fill").font(.system(size: 20)).foregroundStyle(NTColor.gold)
                Text("Meteo-Terminal is a Pro feature").font(NTFont.body(14.5, .semibold))
                Text("Plan the departure, see storm zones on your route and the live radar.")
                    .font(NTFont.body(11.5, .light)).foregroundStyle(NTColor.milk(0.7)).multilineTextAlignment(.center)
                Button(action: onUnlock) {
                    Text("Unlock with Pro").font(NTFont.body(13.5, .semibold)).foregroundStyle(NTColor.pine)
                        .padding(.horizontal, 22).frame(height: 40).background(Capsule().fill(NTColor.milk))
                }.buttonStyle(.plain)
            }
            .foregroundStyle(NTColor.milk)
            .padding(18)
        }
    }
}

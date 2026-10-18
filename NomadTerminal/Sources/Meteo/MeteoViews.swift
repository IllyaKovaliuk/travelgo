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

/// Minimal always-on readout: altitude-adjusted temperature, wind, radar sync.
struct MeteoHUDWidget: View {
    let weather: WeatherPoint?
    let radarEnabled: Bool
    let radarFailed: Bool
    let radarSyncedAt: Date?
    let radarFrameTime: Date?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: weather?.symbol ?? "cloud.fill").foregroundStyle(.cyan)
                Text(weather.map { String(format: "%+.0f°C", $0.temperature) } ?? "--")
                    .font(NTFont.mono(20, .semibold))
            }
            row("ALT", weather.map { "\(Int($0.elevationM)) m" } ?? "--")
            row("WIND", weather.map { "\(Int($0.wind.rounded())) km/h" } ?? "--")
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(statusText).font(NTFont.mono(9, .medium)).tracking(0.6)
                    .foregroundStyle(NTColor.milk(0.7))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .foregroundStyle(NTColor.milk)
        .background(NTColor.pineDeep.opacity(0.9), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.cyan.opacity(0.55), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.25), radius: 8)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(spacing: 8) {
            Text(k).font(NTFont.mono(9, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5)).frame(width: 34, alignment: .leading)
            Text(v).font(NTFont.mono(12, .semibold))
        }
    }

    private var statusColor: Color {
        if isLoading { return NTColor.gold }
        if !radarEnabled { return NTColor.milk(0.4) }
        return radarFailed ? NTColor.hard : NTColor.sage
    }
    private var statusText: String {
        if isLoading { return "SYNCING…" }
        if !radarEnabled { return "RADAR OFF" }
        if radarFailed { return "RADAR OFFLINE" }
        if let t = radarFrameTime { return "RADAR LIVE · \(t.formatted(.dateTime.hour().minute()))" }
        return "RADAR LIVE"
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
                // Departure window strip
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("DEPART").font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                        Spacer()
                        Text(model.departureOffsetH == 0 ? "NOW" : model.departure.formatted(.dateTime.weekday(.abbreviated).hour().minute()).uppercased())
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
                    Text(windowSummary).font(NTFont.body(10.5, .light)).foregroundStyle(NTColor.milk(0.55))
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
                }

                if let w = model.currentWeather {
                    HStack(spacing: 8) {
                        readout("TEMP", String(format: "%+.0f°", w.temperature), icon: "thermometer.medium")
                        readout("GUSTS", "\(Int(w.gust.rounded()))", unit: "km/h", icon: "wind", warn: w.gust >= 45)
                        readout("RAIN", "\(Int(w.probability.rounded()))%", unit: String(format: "%.1fmm", w.precip), icon: "cloud.rain.fill", warn: w.precip >= 1)
                        readout("ALT", "\(Int(w.elevationM))", unit: "m", icon: "mountain.2.fill")
                    }
                    HStack(spacing: 6) {
                        Circle().fill(w.risk.color).frame(width: 7, height: 7)
                        Text("\(w.risk.label) AT THIS POINT").font(NTFont.mono(10, .semibold)).tracking(0.6).foregroundStyle(w.risk.color)
                    }
                }
            }
        }
        .padding(14)
        .foregroundStyle(NTColor.milk)
        .background(NTColor.pineDeep.opacity(0.94), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.cyan.opacity(0.5), lineWidth: 1))
        .shadow(color: .cyan.opacity(0.2), radius: 14, y: 4)
    }

    private var windowSummary: String {
        let r = model.worstRisk
        switch r {
        case .clear: return "No storm windows on this route at that departure."
        case .caution: return "Caution zones on the route — marked amber on the map."
        case .danger: return "Dangerous weather on the route — marked red. Try a different departure."
        }
    }

    private func readout(_ title: String, _ value: String, unit: String? = nil, icon: String, warn: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9))
                Text(title).font(NTFont.mono(8.5, .medium)).tracking(0.7)
            }.foregroundStyle(NTColor.milk(0.5))
            Text(value).font(NTFont.mono(16, .semibold)).foregroundStyle(warn ? NTColor.gold : NTColor.milk)
            Text(unit ?? " ").font(NTFont.mono(9, .medium)).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

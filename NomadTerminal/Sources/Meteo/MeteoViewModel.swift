import Foundation
import CoreLocation
import Observation

/// A slice of the route with the storm risk expected when you reach it.
struct RiskSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let risk: StormRisk
}

@MainActor
@Observable
final class MeteoViewModel {
    // Inputs
    private let track: [CLLocationCoordinate2D]
    private let cumulative: [Double]   // meters from start, per track point
    private let totalMeters: Double
    let durationHours: Double

    // Forecast
    private(set) var stations: [MeteoStation] = []
    private(set) var isLoading = true
    private(set) var failed = false

    // Radar
    private(set) var radarFrames: [RadarFrame] = []
    private(set) var radarIndex = 0
    var radarEnabled = true
    private(set) var radarSyncedAt: Date?
    private(set) var radarFailed = false

    // Timeline state
    static let maxDepartureOffsetH = 36
    var departureOffsetH = 0 { didSet { recompute() } }
    /// 0…1 — how far along the route the scrubber is.
    var progress: Double = 0

    // Derived (recomputed when forecast / departure changes)
    private(set) var segments: [RiskSegment] = []
    private(set) var departureRisks: [StormRisk] = []

    private let base = Date()
    var departure: Date { base.addingTimeInterval(Double(departureOffsetH) * 3600) }
    var scrubDate: Date { departure.addingTimeInterval(progress * durationHours * 3600) }
    var scrubCoordinate: CLLocationCoordinate2D? { coordinate(atFraction: progress) }
    var scrubKM: Double { progress * totalMeters / 1000 }
    var currentWeather: WeatherPoint? { weather(atFraction: progress, date: scrubDate) }
    var worstRisk: StormRisk { segments.map(\.risk).max() ?? .clear }

    init(trackPoints: [TrackPoint], transport: Transport) {
        let coords = trackPoints.map(\.coordinate)
        track = coords
        var cum: [Double] = [0]
        for i in 1..<max(coords.count, 1) {
            cum.append(cum[i - 1] + HazardGeometry.meters(coords[i - 1], coords[i]))
        }
        cumulative = cum
        totalMeters = cum.last ?? 0
        let speedKMH: Double
        switch transport {
        case .foot: speedKMH = 4.5
        case .bike: speedKMH = 14
        case .overland: speedKMH = 35
        case .water: speedKMH = 6
        case .climb: speedKMH = 2.5
        case .paraglide: speedKMH = 28
        }
        durationHours = max(0.25, min(24, totalMeters / 1000 / speedKMH))
    }

    func load() async {
        guard track.count > 1 else { isLoading = false; failed = true; return }
        isLoading = true; failed = false
        let n = 8
        let fractions = (0..<n).map { Double($0) / Double(n - 1) }
        let coords = fractions.compactMap { coordinate(atFraction: $0) }
        async let radar = try? MeteoService.fetchRadar()
        do {
            stations = try await MeteoService.fetchStations(coordinates: coords, fractions: fractions)
            failed = stations.isEmpty
        } catch {
            failed = true
        }
        if let frames = await radar, !frames.isEmpty {
            radarFrames = frames
            radarIndex = frames.count - 1
            radarSyncedAt = Date()
        } else {
            radarFailed = true
        }
        isLoading = false
        recompute()
    }

    func advanceRadar() {
        guard radarEnabled, radarFrames.count > 1 else { return }
        radarIndex = (radarIndex + 1) % radarFrames.count
    }

    // MARK: Geometry

    func coordinate(atFraction f: Double) -> CLLocationCoordinate2D? {
        guard track.count > 1, totalMeters > 0 else { return track.first }
        let target = max(0, min(1, f)) * totalMeters
        var i = 1
        while i < cumulative.count - 1 && cumulative[i] < target { i += 1 }
        let segLen = cumulative[i] - cumulative[i - 1]
        let t = segLen > 0 ? (target - cumulative[i - 1]) / segLen : 0
        let a = track[i - 1], b = track[i]
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    private func slice(from f0: Double, to f1: Double) -> [CLLocationCoordinate2D] {
        guard track.count > 1, totalMeters > 0 else { return [] }
        var out: [CLLocationCoordinate2D] = []
        if let s = coordinate(atFraction: f0) { out.append(s) }
        for (i, d) in cumulative.enumerated() where d / totalMeters > f0 && d / totalMeters < f1 { out.append(track[i]) }
        if let e = coordinate(atFraction: f1) { out.append(e) }
        return out
    }

    // MARK: Weather lookup

    /// Interpolates between the two stations around `f`.
    func weather(atFraction f: Double, date: Date) -> WeatherPoint? {
        guard !stations.isEmpty else { return nil }
        let f = max(0, min(1, f))
        guard let hi = stations.firstIndex(where: { $0.fraction >= f }) else { return stations.last!.at(date) }
        if hi == 0 { return stations[0].at(date) }
        let a = stations[hi - 1].at(date), b = stations[hi].at(date)
        let span = stations[hi].fraction - stations[hi - 1].fraction
        let t = span > 0 ? (f - stations[hi - 1].fraction) / span : 0
        func l(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return WeatherPoint(
            temperature: l(a.temperature, b.temperature), wind: l(a.wind, b.wind), gust: l(a.gust, b.gust),
            probability: l(a.probability, b.probability), precip: l(a.precip, b.precip),
            code: t < 0.5 ? a.code : b.code, elevationM: l(a.elevationM, b.elevationM)
        )
    }

    private func risk(atFraction f: Double, departure: Date) -> StormRisk {
        weather(atFraction: f, date: departure.addingTimeInterval(f * durationHours * 3600))?.risk ?? .clear
    }

    private func recompute() {
        guard !stations.isEmpty else { segments = []; departureRisks = []; return }
        let count = 24
        segments = (0..<count).map { i in
            let f0 = Double(i) / Double(count), f1 = Double(i + 1) / Double(count)
            return RiskSegment(id: i, coordinates: slice(from: f0, to: f1), risk: risk(atFraction: (f0 + f1) / 2, departure: departure))
        }
        // Worst risk anywhere along the route for each possible departure hour.
        departureRisks = (0...Self.maxDepartureOffsetH).map { offset in
            let dep = base.addingTimeInterval(Double(offset) * 3600)
            return (0...12).map { risk(atFraction: Double($0) / 12, departure: dep) }.max() ?? .clear
        }
    }

    /// Per-slice risks along the route for the scrubber's colored track.
    var routeRisks: [StormRisk] { segments.map(\.risk) }
}

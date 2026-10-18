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
    private(set) var lastError: String?

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

    private let base: Date
    /// Offset 0 = right now; offset k ≥ 1 = the k-th full hour from now
    /// (so suggested times read "07:00", not "07:29").
    private let hourAnchor: Date
    func departureDate(_ offset: Int) -> Date {
        offset == 0 ? base : hourAnchor.addingTimeInterval(Double(offset - 1) * 3600)
    }
    var departure: Date { departureDate(departureOffsetH) }
    var scrubDate: Date { departure.addingTimeInterval(progress * durationHours * 3600) }
    var scrubCoordinate: CLLocationCoordinate2D? { coordinate(atFraction: progress) }
    var scrubKM: Double { progress * totalMeters / 1000 }
    var currentWeather: WeatherPoint? { weather(atFraction: progress, date: scrubDate) }
    var worstRisk: StormRisk { segments.map(\.risk).max() ?? .clear }

    /// Human-readable pace assumption shown under the timeline.
    let paceNote: String

    init(trackPoints: [TrackPoint], transport: Transport, ascentM: Double = 0) {
        let now = Date()
        base = now
        let cal = Calendar.current
        hourAnchor = (cal.date(from: cal.dateComponents([.year, .month, .day, .hour], from: now)) ?? now).addingTimeInterval(3600)
        let coords = trackPoints.map(\.coordinate)
        track = coords
        var cum: [Double] = [0]
        for i in 1..<max(coords.count, 1) {
            cum.append(cum[i - 1] + HazardGeometry.meters(coords[i - 1], coords[i]))
        }
        cumulative = cum
        totalMeters = cum.last ?? 0
        let km = totalMeters / 1000
        // Walking/cycling include climbing time (Naismith's rule for foot:
        // 5 km/h + 1 h per 600 m of ascent); vehicles use a flat average.
        let hours: Double
        var climbs = false
        switch transport {
        case .foot: hours = km / 5 + ascentM / 600; climbs = true
        case .climb: hours = km / 3 + ascentM / 400; climbs = true
        case .bike: hours = km / 15 + ascentM / 500; climbs = true
        case .overland: hours = km / 30
        case .water: hours = km / 6
        case .paraglide: hours = km / 28
        }
        durationHours = max(0.25, min(24, hours))
        let avg = km > 0 ? km / durationHours : 0
        let avgText = String(format: "%.1f", avg)
        paceNote = climbs
            ? String(localized: "ETA assumes ~\(avgText) km/h average, including climbing")
            : String(localized: "ETA assumes ~\(avgText) km/h average")
    }

    func load() async {
        guard track.count > 1 else { isLoading = false; failed = true; return }
        isLoading = true; failed = false
        let n = 8
        let fractions = (0..<n).map { Double($0) / Double(n - 1) }
        let coords = fractions.compactMap { coordinate(atFraction: $0) }
        async let radar = try? MeteoService.fetchRadar()
        // One retry: mobile networks drop the first request surprisingly often.
        for attempt in 1...2 {
            do {
                apply(stations: try await MeteoService.fetchStations(coordinates: coords, fractions: fractions))
                lastError = nil
                break
            } catch {
                failed = true
                lastError = String(describing: error)
                if attempt == 1 { try? await Task.sleep(nanoseconds: 1_200_000_000) }
            }
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

    /// Installs a forecast (also the seam unit tests use).
    func apply(stations new: [MeteoStation]) {
        stations = new
        failed = new.isEmpty
        recompute()
    }

    /// Time of the newest radar frame — the real "age" of the data, as
    /// opposed to the frame currently being replayed in the loop.
    var latestRadarTime: Date? { radarFrames.last?.time }

    // MARK: Best departure window

    struct BestWindow {
        let startOffset: Int
        let endOffset: Int
        let risk: StormRisk
        let start: Date
        let end: Date
        let finishBy: Date
        let weatherTurnsAt: Date?
    }

    /// Longest run of consecutive departure hours with the calmest
    /// achievable risk, restricted to sensible daytime starts (05–18h).
    /// Ties go to the earliest run.
    var bestWindow: BestWindow? {
        let risks = departureRisks
        guard !risks.isEmpty else { return nil }
        let cal = Calendar.current
        func daytime(_ i: Int) -> Bool { (5...18).contains(cal.component(.hour, from: departureDate(i))) }
        let candidates = risks.indices.filter(daytime)
        guard let best = candidates.map({ risks[$0] }).min() else { return nil }

        var bestRun: (start: Int, end: Int)?
        var runStart: Int?
        for i in 0...risks.count {
            let ok = i < risks.count && daytime(i) && risks[i] == best
            if ok { if runStart == nil { runStart = i } }
            else if let s = runStart {
                if bestRun == nil || (i - 1 - s) > (bestRun!.end - bestRun!.start) { bestRun = (s, i - 1) }
                runStart = nil
            }
        }
        guard let run = bestRun else { return nil }
        let start = departureDate(run.start), end = departureDate(run.end)
        // When does it turn? First bad moment for the first departure after the window.
        var turns: Date?
        if run.end + 1 < risks.count, risks[run.end + 1] > best {
            let dep = departureDate(run.end + 1)
            for step in 0...24 {
                let f = Double(step) / 24
                if risk(atFraction: f, departure: dep) > best { turns = dep.addingTimeInterval(f * durationHours * 3600); break }
            }
        }
        return BestWindow(startOffset: run.start, endOffset: run.end, risk: best, start: start, end: end,
                          finishBy: start.addingTimeInterval(durationHours * 3600), weatherTurnsAt: turns)
    }

    func applyBestWindow() {
        if let w = bestWindow { departureOffsetH = w.startOffset }
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
        let count = 48
        segments = (0..<count).map { i in
            let f0 = Double(i) / Double(count), f1 = Double(i + 1) / Double(count)
            return RiskSegment(id: i, coordinates: slice(from: f0, to: f1), risk: risk(atFraction: (f0 + f1) / 2, departure: departure))
        }
        // Worst risk anywhere along the route for each possible departure hour.
        departureRisks = (0...Self.maxDepartureOffsetH).map { offset in
            let dep = departureDate(offset)
            return (0...12).map { risk(atFraction: Double($0) / 12, departure: dep) }.max() ?? .clear
        }
    }

    /// Per-slice risks along the route for the scrubber's colored track.
    var routeRisks: [StormRisk] { segments.map(\.risk) }

    /// Adjacent slices with the same risk merged into one polyline, so the
    /// map draws a handful of colored stretches instead of dozens of layers.
    var riskRuns: [RiskSegment] {
        var runs: [RiskSegment] = []
        for seg in segments {
            if let last = runs.last, last.risk == seg.risk {
                runs[runs.count - 1] = RiskSegment(id: last.id, coordinates: last.coordinates + seg.coordinates, risk: seg.risk)
            } else {
                runs.append(RiskSegment(id: runs.count, coordinates: seg.coordinates, risk: seg.risk))
            }
        }
        return runs
    }
}

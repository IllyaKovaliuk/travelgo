import Foundation
import CoreLocation
import SwiftUI

/// Meteo-Terminal data layer: hourly forecast per sample point along a
/// route (Open-Meteo, no key) and live precipitation radar frames
/// (RainViewer). Both are free public APIs; nothing is stored server-side.

enum StormRisk: Int, Comparable {
    case clear = 0, caution, danger
    static func < (a: StormRisk, b: StormRisk) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .clear: return NTColor.sage
        case .caution: return NTColor.gold
        case .danger: return NTColor.hard
        }
    }
    var label: String {
        switch self {
        case .clear: return "CLEAR"
        case .caution: return "CAUTION"
        case .danger: return "DANGER"
        }
    }

    /// Thresholds chosen for people outdoors, not for a weather app:
    /// gusts ≥ 45 km/h make exposed ridges/water unpleasant, ≥ 70 is
    /// dangerous; thunderstorms are always danger.
    static func classify(code: Int, gust: Double, precip: Double, probability: Double) -> StormRisk {
        if code >= 95 || gust >= 70 || precip >= 5 || (probability >= 70 && precip >= 2.5) || code == 75 || code == 86 { return .danger }
        if gust >= 45 || (precip >= 1 && probability >= 50) || code == 65 || code == 67 || code == 82 || (71...77).contains(code) { return .caution }
        return .clear
    }
}

/// Weather at one place and instant.
struct WeatherPoint {
    var temperature: Double
    var wind: Double
    var gust: Double
    var probability: Double
    var precip: Double
    var code: Int
    var elevationM: Double
    var risk: StormRisk { .classify(code: code, gust: gust, precip: precip, probability: probability) }

    var symbol: String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

/// A forecast sampled at one point along the route.
struct MeteoStation {
    let fraction: Double              // 0…1 along the route
    let coordinate: CLLocationCoordinate2D
    let elevationM: Double            // terrain elevation; temperatures are already adjusted to it
    let hourZero: Date                // time of index 0 (UTC)
    let temperature: [Double]
    let wind: [Double]
    let gust: [Double]
    let probability: [Double]
    let precip: [Double]
    let code: [Int]

    func at(_ date: Date) -> WeatherPoint {
        let n = temperature.count
        guard n > 0 else { return WeatherPoint(temperature: 0, wind: 0, gust: 0, probability: 0, precip: 0, code: 0, elevationM: elevationM) }
        let x = max(0, min(Double(n - 1), date.timeIntervalSince(hourZero) / 3600))
        let i0 = Int(x.rounded(.down)), i1 = min(n - 1, i0 + 1), f = x - Double(i0)
        func lerp(_ a: [Double]) -> Double { a[i0] + (a[i1] - a[i0]) * f }
        return WeatherPoint(
            temperature: lerp(temperature), wind: lerp(wind), gust: lerp(gust),
            probability: lerp(probability), precip: lerp(precip),
            code: code[f < 0.5 ? i0 : i1], elevationM: elevationM
        )
    }
}

struct RadarFrame: Identifiable {
    let id: Int
    let time: Date
    let tileURL: String
}

enum MeteoService {
    enum MeteoError: Error { case badResponse }

    private struct ForecastResponse: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double?]
            let wind_speed_10m: [Double?]
            let wind_gusts_10m: [Double?]
            let precipitation_probability: [Double?]
            let precipitation: [Double?]
            let weather_code: [Int?]
        }
        let elevation: Double?
        let hourly: Hourly
    }

    /// One request for all sample points. Hours are UTC; index 0 is
    /// 00:00 UTC today, covering ~72 h ahead.
    static func fetchStations(coordinates: [CLLocationCoordinate2D], fractions: [Double]) async throws -> [MeteoStation] {
        precondition(coordinates.count == fractions.count)
        let lat = coordinates.map { String(format: "%.4f", $0.latitude) }.joined(separator: ",")
        let lng = coordinates.map { String(format: "%.4f", $0.longitude) }.joined(separator: ",")
        let hourly = "temperature_2m,wind_speed_10m,wind_gusts_10m,precipitation_probability,precipitation,weather_code"
        guard let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)&hourly=\(hourly)&wind_speed_unit=kmh&timezone=UTC&forecast_days=3") else {
            throw MeteoError.badResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MeteoError.badResponse }
        let decoder = JSONDecoder()
        let responses: [ForecastResponse]
        if let many = try? decoder.decode([ForecastResponse].self, from: data) { responses = many }
        else { responses = [try decoder.decode(ForecastResponse.self, from: data)] }
        guard responses.count == coordinates.count else { throw MeteoError.badResponse }

        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        return zip(responses.indices, responses).compactMap { i, r in
            guard let first = r.hourly.time.first, let zero = parser.date(from: first) else { return nil }
            func d(_ a: [Double?]) -> [Double] { a.map { $0 ?? 0 } }
            return MeteoStation(
                fraction: fractions[i], coordinate: coordinates[i], elevationM: r.elevation ?? 0, hourZero: zero,
                temperature: d(r.hourly.temperature_2m), wind: d(r.hourly.wind_speed_10m), gust: d(r.hourly.wind_gusts_10m),
                probability: d(r.hourly.precipitation_probability), precip: d(r.hourly.precipitation),
                code: r.hourly.weather_code.map { $0 ?? 0 }
            )
        }
    }

    private struct RadarResponse: Decodable {
        struct Frame: Decodable { let time: Int; let path: String }
        struct Radar: Decodable { let past: [Frame]; let nowcast: [Frame] }
        let host: String
        let radar: Radar
    }

    /// Latest radar frames (RainViewer serves ~2 h of past frames, 10 min
    /// apart; tiles are only rendered up to zoom 7 and over-zoomed above).
    static func fetchRadar() async throws -> [RadarFrame] {
        guard let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json") else { throw MeteoError.badResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw MeteoError.badResponse }
        let r = try JSONDecoder().decode(RadarResponse.self, from: data)
        return (r.radar.past + r.radar.nowcast).enumerated().map { i, f in
            RadarFrame(id: i, time: Date(timeIntervalSince1970: TimeInterval(f.time)),
                       tileURL: "\(r.host)\(f.path)/256/{z}/{x}/{y}/2/1_1.png")
        }
    }
}

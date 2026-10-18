import XCTest
import CoreLocation
@testable import NomadTerminal

@MainActor
final class MeteoTests: XCTestCase {
    func testRiskClassification() {
        // False-alarm regression: light drizzle, 21% chance, calm wind is just fine.
        XCTAssertEqual(StormRisk.classify(code: 51, gust: 14, precip: 0.7, probability: 21), .clear)
        XCTAssertEqual(StormRisk.classify(code: 0, gust: 10, precip: 0, probability: 0), .clear)
        // Yellow: wind 30+, steady rain
        XCTAssertEqual(StormRisk.classify(code: 3, gust: 35, precip: 0, probability: 0), .caution)
        XCTAssertEqual(StormRisk.classify(code: 61, gust: 20, precip: 1.5, probability: 60), .caution)
        XCTAssertEqual(StormRisk.classify(code: 96, gust: 20, precip: 0, probability: 10), .caution) // unlikely thunder
        // Red: likely thunderstorm, gusts 50+, downpour
        XCTAssertEqual(StormRisk.classify(code: 96, gust: 20, precip: 0, probability: 70), .danger)
        XCTAssertEqual(StormRisk.classify(code: 0, gust: 55, precip: 0, probability: 0), .danger)
        XCTAssertEqual(StormRisk.classify(code: 65, gust: 10, precip: 6, probability: 90), .danger)
    }

    func testReasonNamesTheCause() {
        let w = WeatherPoint(temperature: 10, wind: 20, gust: 55, probability: 70, precip: 1, code: 96, elevationM: 100)
        XCTAssertEqual(w.risk, .danger)
        XCTAssertTrue(w.reason.contains("55"), w.reason)
        XCTAssertTrue(w.reason.contains("70"), w.reason)
        let calm = WeatherPoint(temperature: 10, wind: 5, gust: 10, probability: 0, precip: 0, code: 0, elevationM: 100)
        XCTAssertEqual(calm.reason, "")
    }

    private func line(km: Double) -> [TrackPoint] {
        // ~km of straight east-west track at 50°N (1° lng ≈ 71.5 km)
        let steps = 20
        return (0...steps).map { TrackPoint(lat: 50, lng: 28 + km / 71.5 * Double($0) / Double(steps)) }
    }

    func testFootEtaIncludesClimbing() {
        let flat = MeteoViewModel(trackPoints: line(km: 10), transport: .foot, ascentM: 0)
        let hilly = MeteoViewModel(trackPoints: line(km: 10), transport: .foot, ascentM: 600)
        XCTAssertEqual(flat.durationHours, 2.0, accuracy: 0.1)      // 10 km @ 5 km/h
        XCTAssertEqual(hilly.durationHours, 3.0, accuracy: 0.1)     // + 1 h per 600 m (Naismith)
        let car = MeteoViewModel(trackPoints: line(km: 10), transport: .overland)
        XCTAssertLessThan(car.durationHours, 0.5)
    }

    private func station(code: Int, probability: Double) -> MeteoStation {
        var zero = Calendar(identifier: .gregorian)
        zero.timeZone = TimeZone(identifier: "UTC")!
        let start = zero.startOfDay(for: Date())
        let n = 72
        return MeteoStation(fraction: 0, coordinate: .init(latitude: 50, longitude: 28), elevationM: 100, hourZero: start,
                            temperature: Array(repeating: 10, count: n), wind: Array(repeating: 5, count: n),
                            gust: Array(repeating: 10, count: n), probability: Array(repeating: probability, count: n),
                            precip: Array(repeating: 0, count: n), code: Array(repeating: code, count: n))
    }

    func testBestWindowClearAndDanger() {
        let vm = MeteoViewModel(trackPoints: line(km: 10), transport: .foot)
        let a = station(code: 0, probability: 0), b = MeteoStation(fraction: 1, coordinate: a.coordinate, elevationM: 100, hourZero: a.hourZero,
            temperature: a.temperature, wind: a.wind, gust: a.gust, probability: a.probability, precip: a.precip, code: a.code)
        vm.apply(stations: [a, b])
        let clear = vm.bestWindow
        XCTAssertEqual(clear?.risk, .clear)
        XCTAssertTrue((5...18).contains(Calendar.current.component(.hour, from: clear!.start)))

        let s1 = station(code: 96, probability: 90)
        let s2 = MeteoStation(fraction: 1, coordinate: s1.coordinate, elevationM: 100, hourZero: s1.hourZero,
            temperature: s1.temperature, wind: s1.wind, gust: s1.gust, probability: s1.probability, precip: s1.precip, code: s1.code)
        vm.apply(stations: [s1, s2])
        XCTAssertEqual(vm.bestWindow?.risk, .danger)
    }

    func testStationInterpolatesBetweenHours() {
        let zero = Date(timeIntervalSince1970: 1_800_000_000)
        let st = MeteoStation(fraction: 0, coordinate: .init(latitude: 50, longitude: 28), elevationM: 500, hourZero: zero,
                              temperature: [10, 20], wind: [0, 10], gust: [0, 0], probability: [0, 100], precip: [0, 0], code: [0, 61])
        let mid = st.at(zero.addingTimeInterval(1800))
        XCTAssertEqual(mid.temperature, 15, accuracy: 0.001)
        XCTAssertEqual(mid.probability, 50, accuracy: 0.001)
        // Past the end clamps to the last hour instead of crashing.
        XCTAssertEqual(st.at(zero.addingTimeInterval(99 * 3600)).temperature, 20, accuracy: 0.001)
    }

    func testRouteFractionCoordinate() {
        let pts = [TrackPoint(lat: 50, lng: 28), TrackPoint(lat: 50, lng: 28.1), TrackPoint(lat: 50, lng: 28.2)]
        let vm = MeteoViewModel(trackPoints: pts, transport: .foot)
        XCTAssertEqual(vm.coordinate(atFraction: 0.5)!.longitude, 28.1, accuracy: 1e-6)
        XCTAssertEqual(vm.coordinate(atFraction: 0.25)!.longitude, 28.05, accuracy: 1e-6)
        XCTAssertEqual(vm.coordinate(atFraction: 1)!.longitude, 28.2, accuracy: 1e-6)
    }
}

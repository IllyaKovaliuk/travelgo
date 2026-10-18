import XCTest
import CoreLocation
@testable import NomadTerminal

@MainActor
final class MeteoTests: XCTestCase {
    func testRiskClassification() {
        XCTAssertEqual(StormRisk.classify(code: 0, gust: 10, precip: 0, probability: 0), .clear)
        XCTAssertEqual(StormRisk.classify(code: 3, gust: 50, precip: 0, probability: 0), .caution)
        XCTAssertEqual(StormRisk.classify(code: 61, gust: 20, precip: 1.5, probability: 60), .caution)
        XCTAssertEqual(StormRisk.classify(code: 96, gust: 20, precip: 0, probability: 0), .danger)
        XCTAssertEqual(StormRisk.classify(code: 0, gust: 80, precip: 0, probability: 0), .danger)
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

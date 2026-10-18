import XCTest
import CoreLocation
@testable import NomadTerminal

final class HazardGeometryTests: XCTestCase {
    private func c(_ lat: Double, _ lng: Double) -> CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }

    func testPointOnLineIsZero() {
        let line = [c(50.0, 28.0), c(50.0, 28.01)]
        XCTAssertEqual(HazardGeometry.distance(from: c(50.0, 28.005), toPolyline: line), 0, accuracy: 0.5)
    }

    func testPerpendicularDistance() {
        // ~111 m north of an east-west segment (0.001° lat ≈ 110.5 m)
        let line = [c(50.0, 28.0), c(50.0, 28.01)]
        XCTAssertEqual(HazardGeometry.distance(from: c(50.001, 28.005), toPolyline: line), 110.5, accuracy: 2)
    }

    func testBeyondSegmentEndUsesEndpoint() {
        let line = [c(50.0, 28.0), c(50.0, 28.01)]
        let d = HazardGeometry.distance(from: c(50.0, 28.02), toPolyline: line)
        XCTAssertEqual(d, 0.01 * 111_320 * cos(50 * .pi / 180), accuracy: 5)
    }

    func testSimplifyKeepsCornersAndDropsCollinear() {
        let pts = [TrackPoint(lat: 50, lng: 28), TrackPoint(lat: 50, lng: 28.001), TrackPoint(lat: 50, lng: 28.002),
                   TrackPoint(lat: 50.002, lng: 28.002)]
        let out = TrackMath.simplify(pts, toleranceM: 3)
        XCTAssertEqual(out.count, 3) // start, corner, end — collinear midpoint dropped
        XCTAssertEqual(out[1].lng, 28.002, accuracy: 1e-9)
    }
}

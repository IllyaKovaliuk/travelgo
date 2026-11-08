import XCTest
@testable import NomadTerminal

final class RouteLinksTests: XCTestCase {
    private let id = "3F2504E0-4F89-41D3-9A0C-0305E82C3301"

    func testRoundTrip() {
        XCTAssertEqual(RouteLinks.routeID(from: RouteLinks.url(forRouteID: id)), id)
    }

    func testCustomScheme() {
        XCTAssertEqual(RouteLinks.routeID(from: URL(string: "io.nomadterminal.app://route/\(id)")!), id)
    }

    func testRejectsOtherURLs() {
        XCTAssertNil(RouteLinks.routeID(from: URL(string: "https://nomad-legal.vercel.app/privacy/")!))
        XCTAssertNil(RouteLinks.routeID(from: URL(string: "https://evil.example/route/\(id)")!))
        XCTAssertNil(RouteLinks.routeID(from: URL(string: "https://nomad-legal.vercel.app/route/not-a-uuid")!))
        XCTAssertNil(RouteLinks.routeID(from: URL(fileURLWithPath: "/tmp/track.gpx")))
    }
}

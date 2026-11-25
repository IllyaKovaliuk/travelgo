import XCTest
@testable import NomadTerminal

final class CrewLinksTests: XCTestCase {
    private let code = "a1b2c3d4e5f60789"

    func testRoundTrip() {
        XCTAssertEqual(CrewLinks.inviteCode(from: CrewLinks.url(forInviteCode: code)), code)
    }

    func testCustomScheme() {
        XCTAssertEqual(CrewLinks.inviteCode(from: URL(string: "io.nomadterminal.app://crew/\(code)")!), code)
    }

    func testPastedTextAcceptsLinkOrBareCode() {
        XCTAssertEqual(CrewLinks.inviteCode(fromText: "  https://nomad-legal.vercel.app/crew/\(code) \n"), code)
        XCTAssertEqual(CrewLinks.inviteCode(fromText: code), code)
    }

    func testRejectsOtherURLsAndBadCodes() {
        XCTAssertNil(CrewLinks.inviteCode(from: URL(string: "https://evil.example/crew/\(code)")!))
        XCTAssertNil(CrewLinks.inviteCode(from: URL(string: "https://nomad-legal.vercel.app/route/\(code)")!))
        XCTAssertNil(CrewLinks.inviteCode(from: URL(string: "https://nomad-legal.vercel.app/crew/short")!))
        XCTAssertNil(CrewLinks.inviteCode(from: URL(string: "https://nomad-legal.vercel.app/crew/abc%20def%3Bdrop")!))
        XCTAssertNil(CrewLinks.inviteCode(fromText: "hello world"))
        XCTAssertNil(CrewLinks.inviteCode(from: URL(fileURLWithPath: "/tmp/track.gpx")))
        // A route link is not a crew invite and vice versa.
        XCTAssertNil(RouteLinks.routeID(from: CrewLinks.url(forInviteCode: code)))
    }
}

import XCTest
@testable import NomadTerminal

final class RouteFileParserTests: XCTestCase {
    /// Writes `gpx` to a real temp file with a real `.gpx` extension —
    /// `RouteFileParser.parse` dispatches on the file extension, so this
    /// has to be a real file on disk, not a bare string.
    private func writeGPX(_ gpx: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("gpx")
        try gpx.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    override func tearDownWithError() throws {
        // Best-effort cleanup — a leftover temp file from a failed test
        // isn't worth failing the next run over.
    }

    func testTrackPointsWithTime() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test">
          <trk>
            <trkseg>
              <trkpt lat="50.4501" lon="30.5234">
                <ele>180.5</ele>
                <time>2026-06-01T08:00:00Z</time>
              </trkpt>
              <trkpt lat="50.4510" lon="30.5240">
                <ele>185.0</ele>
                <time>2026-06-01T08:05:30Z</time>
              </trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let url = try writeGPX(gpx)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try RouteFileParser.parse(fileURL: url)

        XCTAssertEqual(result.points.count, 2)
        XCTAssertTrue(result.waypoints.isEmpty)

        guard let first = result.points.first, let second = result.points.last else {
            return XCTFail("expected two points")
        }
        XCTAssertEqual(first.lat, 50.4501, accuracy: 0.0001)
        XCTAssertEqual(first.lng, 30.5234, accuracy: 0.0001)
        XCTAssertEqual(first.elevation, 180.5)

        var expectedComponents = DateComponents()
        expectedComponents.year = 2026; expectedComponents.month = 6; expectedComponents.day = 1
        expectedComponents.hour = 8; expectedComponents.minute = 0; expectedComponents.second = 0
        let expectedFirst = Calendar(identifier: .gregorian).date(from: {
            var c = expectedComponents; c.timeZone = TimeZone(identifier: "UTC"); return c
        }())

        XCTAssertNotNil(first.time, "a <time> on every point should parse to a real Date")
        if let expectedFirst, let actualFirst = first.time {
            XCTAssertEqual(actualFirst.timeIntervalSince1970, expectedFirst.timeIntervalSince1970, accuracy: 1)
        }
        XCTAssertNotNil(second.time)
        if let firstTime = first.time, let secondTime = second.time {
            XCTAssertLessThan(firstTime, secondTime, "the second point's real timestamp should be later")
        }
    }

    func testTrackPointsWithoutTime() throws {
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test">
          <trk>
            <trkseg>
              <trkpt lat="50.4501" lon="30.5234"><ele>180.5</ele></trkpt>
              <trkpt lat="50.4510" lon="30.5240"><ele>185.0</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let url = try writeGPX(gpx)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try RouteFileParser.parse(fileURL: url)

        XCTAssertEqual(result.points.count, 2)
        XCTAssertTrue(result.waypoints.isEmpty)
        // No <time> anywhere in the file — every point should parse
        // cleanly with a real nil, never a fabricated timestamp.
        XCTAssertTrue(result.points.allSatisfy { $0.time == nil })
        XCTAssertEqual(result.points[0].elevation, 180.5)
        XCTAssertEqual(result.points[1].elevation, 185.0)
    }

    func testWaypointsBecomePinsAndDontLeakIntoTrackPoints() throws {
        // Each <wpt> carries its own <ele>/<time> — real exports often do
        // this — which is exactly the case that would leak into the next
        // real track point's elevation/time if the parser's buffers
        // weren't scoped to "not inside a waypoint."
        let gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="test">
          <wpt lat="50.4600" lon="30.5300">
            <ele>999</ele>
            <time>2026-06-01T09:00:00Z</time>
            <name>Camp</name>
          </wpt>
          <wpt lat="50.4610" lon="30.5310">
          </wpt>
          <trk>
            <trkseg>
              <trkpt lat="50.4501" lon="30.5234"><ele>180.5</ele></trkpt>
              <trkpt lat="50.4510" lon="30.5240"><ele>185.0</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """
        let url = try writeGPX(gpx)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try RouteFileParser.parse(fileURL: url)

        XCTAssertEqual(result.waypoints.count, 2)
        XCTAssertEqual(result.waypoints[0].name, "Camp")
        XCTAssertEqual(result.waypoints[0].lat, 50.4600, accuracy: 0.0001)
        XCTAssertNil(result.waypoints[1].name, "a <wpt> with no <name> should parse as nil, not an empty string")

        // The real track points must be unaffected by the waypoints'
        // own <ele>/<time> that came before them in the file.
        XCTAssertEqual(result.points.count, 2)
        XCTAssertEqual(result.points[0].elevation, 180.5, "must not pick up the waypoint's 999")
        XCTAssertNil(result.points[0].time, "must not pick up the waypoint's own <time>")
        XCTAssertEqual(result.points[1].elevation, 185.0)
    }
}

import Foundation

/// A single point out of an imported file, with elevation kept separate
/// from `TrackPoint` (which only ever carries lat/lng — see its own doc
/// comment) since `TrackMath.ascentM`/`highPointM` need it before the
/// points get downsampled into the storage shape. `time` is real when the
/// source file has a `<time>` per point (most real recordings do) and nil
/// when it doesn't (a hand-drawn route export, say) — never fabricated.
struct ParsedTrackPoint {
    let lat: Double
    let lng: Double
    let elevation: Double?
    let time: Date?
}

/// A standalone `<wpt>` — a pin the source app's user dropped, not part of
/// the recorded line. `name` is nil only if the file itself omitted one;
/// `ImportRouteView` falls back to a generic label for display, not here —
/// this stays a faithful parse of what the file actually said.
struct ParsedWaypoint {
    let lat: Double
    let lng: Double
    let name: String?
}

enum RouteFileParseError: LocalizedError {
    case unsupportedFormat
    case unreadable
    case noTrackPoints

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "That's not a GPX or KML file."
        case .unreadable: return "Couldn't open that file — try exporting it again."
        case .noTrackPoints: return "No track points found in that file."
        }
    }
}

/// Real GPX/KML parsing via `Foundation.XMLParser` — no third-party
/// dependency needed for two fairly simple XML schemas. TCX/FIT (Garmin's
/// and Strava's own proprietary formats) aren't handled — both platforms
/// also export plain GPX, which is what `LogRouteStartView`'s "Import a
/// file" actually promises now (copy updated to say so honestly, not
/// claiming native Garmin/Strava format support that isn't there).
enum RouteFileParser {
    /// `waypoints` is always empty for KML — only GPX's `<wpt>` is
    /// collected; KML's own standalone-placemark convention isn't part of
    /// what this app imports right now.
    struct Result {
        let points: [ParsedTrackPoint]
        let waypoints: [ParsedWaypoint]
    }

    static func parse(fileURL: URL) throws -> Result {
        guard let data = try? Data(contentsOf: fileURL) else { throw RouteFileParseError.unreadable }
        let result: Result
        switch fileURL.pathExtension.lowercased() {
        case "gpx": result = try parseGPX(data)
        case "kml": result = Result(points: try parseKML(data), waypoints: [])
        default: throw RouteFileParseError.unsupportedFormat
        }
        guard !result.points.isEmpty else { throw RouteFileParseError.noTrackPoints }
        return result
    }

    private static func parseGPX(_ data: Data) throws -> Result {
        let delegate = GPXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw RouteFileParseError.unreadable }
        return Result(points: delegate.points, waypoints: delegate.waypoints)
    }

    private static func parseKML(_ data: Data) throws -> [ParsedTrackPoint] {
        let delegate = KMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw RouteFileParseError.unreadable }
        return delegate.points
    }
}

/// Both tried in order — most real exports use `Z`-suffixed UTC with
/// fractional seconds, but whole-second timestamps are common too, and a
/// point with a time the formatter can't parse should still import
/// (`time: nil`), not fail the whole file.
private let gpxTimeFormatters: [ISO8601DateFormatter] = {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let whole = ISO8601DateFormatter()
    whole.formatOptions = [.withInternetDateTime]
    return [withFraction, whole]
}()

private func parseGPXTime(_ text: String) -> Date? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    for formatter in gpxTimeFormatters {
        if let date = formatter.date(from: trimmed) { return date }
    }
    return nil
}

/// GPX: `<trkpt lat="…" lon="…"><ele>…</ele><time>…</time></trkpt>` inside
/// `<trk><trkseg>` (a route's actual recorded points), or the equivalent
/// `<rtept>` used by a hand-planned route export instead of a recording.
/// `<wpt>` (standalone waypoints the source app's user dropped — pins, not
/// the path) is collected separately into `waypoints`: real pins, not part
/// of the line, same distinction `DraftPOI` vs. `TrackPoint` already makes
/// everywhere else in this app.
private final class GPXDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [ParsedTrackPoint] = []
    private(set) var waypoints: [ParsedWaypoint] = []

    private var currentLat: Double?
    private var currentLng: Double?
    private var elevationText = ""
    private var inElevation = false
    private var timeText = ""
    private var inTime = false

    private var insideWaypoint = false
    private var waypointLat: Double?
    private var waypointLng: Double?
    private var waypointNameText = ""
    private var inWaypointName = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "trkpt", "rtept":
            currentLat = attributeDict["lat"].flatMap(Double.init)
            currentLng = attributeDict["lon"].flatMap(Double.init)
        case "wpt":
            insideWaypoint = true
            waypointLat = attributeDict["lat"].flatMap(Double.init)
            waypointLng = attributeDict["lon"].flatMap(Double.init)
            waypointNameText = ""
        case "ele" where !insideWaypoint:
            // Guarded the same way `name` is below — a `<wpt>` can carry
            // its own `<ele>`/`<time>` in real exports, and without this
            // guard those would land in the buffers below, which only get
            // *consumed* on the next `trkpt`/`rtept` close — so a
            // waypoint's elevation/time would silently leak onto whatever
            // real track point comes after it.
            inElevation = true
            elevationText = ""
        case "time" where !insideWaypoint:
            inTime = true
            timeText = ""
        case "name" where insideWaypoint:
            // Guarded to `insideWaypoint` on purpose — `<name>` also shows
            // up on `<trk>`/`<rte>` themselves (the route's own name, not
            // a pin's), which must not get captured here.
            inWaypointName = true
            waypointNameText = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inElevation { elevationText += string }
        if inTime { timeText += string }
        if inWaypointName { waypointNameText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "ele":
            inElevation = false
        case "time":
            inTime = false
        case "name" where insideWaypoint:
            inWaypointName = false
        case "trkpt", "rtept":
            if let lat = currentLat, let lng = currentLng {
                let ele = Double(elevationText.trimmingCharacters(in: .whitespacesAndNewlines))
                let time = parseGPXTime(timeText)
                points.append(ParsedTrackPoint(lat: lat, lng: lng, elevation: ele, time: time))
            }
            currentLat = nil
            currentLng = nil
            timeText = ""
        case "wpt":
            if let lat = waypointLat, let lng = waypointLng {
                let name = waypointNameText.trimmingCharacters(in: .whitespacesAndNewlines)
                waypoints.append(ParsedWaypoint(lat: lat, lng: lng, name: name.isEmpty ? nil : name))
            }
            insideWaypoint = false
            waypointLat = nil
            waypointLng = nil
            waypointNameText = ""
        default: break
        }
    }
}

/// KML: a `<LineString><coordinates>` block, space-separated
/// "lon,lat[,elevation]" triples — note the coordinate order is
/// lon-then-lat here, the opposite of GPX's `lat`/`lon` attributes.
private final class KMLDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [ParsedTrackPoint] = []
    private var inCoordinates = false
    private var buffer = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "coordinates" {
            inCoordinates = true
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inCoordinates { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "coordinates" else { return }
        inCoordinates = false
        let tuples = buffer.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        for tuple in tuples {
            let parts = tuple.split(separator: ",")
            guard parts.count >= 2, let lng = Double(parts[0]), let lat = Double(parts[1]) else { continue }
            let elevation = parts.count >= 3 ? Double(parts[2]) : nil
            points.append(ParsedTrackPoint(lat: lat, lng: lng, elevation: elevation, time: nil))
        }
    }
}

import Foundation

/// A single point out of an imported file, with elevation kept separate
/// from `TrackPoint` (which only ever carries lat/lng — see its own doc
/// comment) since `TrackMath.ascentM`/`highPointM` need it before the
/// points get downsampled into the storage shape.
struct ParsedTrackPoint {
    let lat: Double
    let lng: Double
    let elevation: Double?
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
    static func parse(fileURL: URL) throws -> [ParsedTrackPoint] {
        guard let data = try? Data(contentsOf: fileURL) else { throw RouteFileParseError.unreadable }
        let points: [ParsedTrackPoint]
        switch fileURL.pathExtension.lowercased() {
        case "gpx": points = try parseGPX(data)
        case "kml": points = try parseKML(data)
        default: throw RouteFileParseError.unsupportedFormat
        }
        guard !points.isEmpty else { throw RouteFileParseError.noTrackPoints }
        return points
    }

    private static func parseGPX(_ data: Data) throws -> [ParsedTrackPoint] {
        let delegate = GPXDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw RouteFileParseError.unreadable }
        return delegate.points
    }

    private static func parseKML(_ data: Data) throws -> [ParsedTrackPoint] {
        let delegate = KMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { throw RouteFileParseError.unreadable }
        return delegate.points
    }
}

/// GPX: `<trkpt lat="…" lon="…"><ele>…</ele></trkpt>` inside `<trk><trkseg>`
/// (a route's actual recorded points), or the equivalent `<rtept>` used by
/// a hand-planned route export instead of a recording. `<wpt>` (standalone
/// waypoints — pins, not the path) is deliberately not collected here.
private final class GPXDelegate: NSObject, XMLParserDelegate {
    private(set) var points: [ParsedTrackPoint] = []
    private var currentLat: Double?
    private var currentLng: Double?
    private var elevationText = ""
    private var inElevation = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch elementName {
        case "trkpt", "rtept":
            currentLat = attributeDict["lat"].flatMap(Double.init)
            currentLng = attributeDict["lon"].flatMap(Double.init)
        case "ele":
            inElevation = true
            elevationText = ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inElevation { elevationText += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "ele":
            inElevation = false
        case "trkpt", "rtept":
            if let lat = currentLat, let lng = currentLng {
                let ele = Double(elevationText.trimmingCharacters(in: .whitespacesAndNewlines))
                points.append(ParsedTrackPoint(lat: lat, lng: lng, elevation: ele))
            }
            currentLat = nil
            currentLng = nil
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
            points.append(ParsedTrackPoint(lat: lat, lng: lng, elevation: elevation))
        }
    }
}

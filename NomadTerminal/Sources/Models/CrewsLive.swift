import Foundation
import CoreLocation
import SwiftUI

// Mirrors backend/supabase/migrations/20261126000001_crews_live.sql.
// Pure data and presentation arithmetic — every rule lives in Postgres.

// MARK: Polls

enum PollKind: String, Codable, CaseIterable, Identifiable {
    case `where`, route, when, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .where: return String(localized: "Where")
        case .route: return String(localized: "Route")
        case .when: return String(localized: "When")
        case .other: return String(localized: "Other")
        }
    }

    var icon: String {
        switch self {
        case .where: return "mappin.and.ellipse"
        case .route: return "point.topleft.down.to.point.bottomright.curvepath"
        case .when: return "calendar"
        case .other: return "pencil"
        }
    }
}

/// What an option stands for: a place, a Nomad route or a date range.
struct PollPayload: Codable, Hashable {
    var routeId: String?
    var start: String?
    var end: String?
    var name: String?
    enum CodingKeys: String, CodingKey { case routeId = "route_id", start, end, name }
}

struct PollOption: Identifiable, Hashable {
    let id: UUID
    let label: String
    let payload: PollPayload
    let addedBy: UUID?
    let position: Int
}

struct PollVote: Hashable {
    let userId: UUID
    let optionId: UUID
}

struct Poll: Identifiable, Hashable {
    let id: UUID
    let crewId: UUID
    let expeditionId: UUID?
    let dayIndex: Int?
    let kind: PollKind
    let question: String
    let createdBy: UUID?
    let closesAt: Date?
    let allowMemberOptions: Bool
    let closeWhenAllVoted: Bool
    let isClosed: Bool
    let winnerOptionId: UUID?
    var options: [PollOption]
    var votes: [PollVote]

    func count(for option: PollOption) -> Int { votes.filter { $0.optionId == option.id }.count }
    func myVote(_ me: UUID?) -> UUID? { votes.first { $0.userId == me }?.optionId }
    var leaderIds: [UUID] {
        let top = options.map { count(for: $0) }.max() ?? 0
        guard top > 0 else { return [] }
        return options.filter { count(for: $0) == top }.map(\.id)
    }
    var isTied: Bool { leaderIds.count > 1 }
    var winner: PollOption? { options.first { $0.id == winnerOptionId } }
}

// MARK: Awareness roles, alerts

enum AwarenessRole: String, Codable { case lead, sweep }

enum AwarenessMode: String, CaseIterable, Identifiable {
    case road, trail, ascent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .road: return String(localized: "Road")
        case .trail: return String(localized: "Trail")
        case .ascent: return String(localized: "Ascent")
        }
    }
}

enum AlertKind: String, CaseIterable, Identifiable {
    case stoppedOffPlan = "stopped_off_plan", fallingBehind = "falling_behind", groupSpread = "group_spread"
    case offRoute = "off_route", lowBattery = "low_battery", noSignal = "no_signal", turnaround = "turnaround"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .stoppedOffPlan: return String(localized: "Stops off-plan")
        case .fallingBehind: return String(localized: "Falls behind the lead")
        case .groupSpread: return String(localized: "Group spreads out")
        case .offRoute: return String(localized: "Leaves the route")
        case .lowBattery: return String(localized: "Battery low")
        case .noSignal: return String(localized: "No signal")
        case .turnaround: return String(localized: "Turnaround reminder")
        }
    }

    /// Short copy for the banner ("… 4 min").
    var bannerTitle: String {
        switch self {
        case .stoppedOffPlan: return String(localized: "stopped")
        case .fallingBehind: return String(localized: "is falling behind")
        case .groupSpread: return String(localized: "group is spreading out")
        case .offRoute: return String(localized: "left the route")
        case .lowBattery: return String(localized: "battery is low")
        case .noSignal: return String(localized: "lost signal")
        case .turnaround: return String(localized: "turnaround time")
        }
    }

    var isWarning: Bool { self == .lowBattery || self == .noSignal || self == .turnaround ? false : true }
}

/// Default thresholds from the design handoff; the unit depends on the kind and mode.
struct AlertDefaults {
    static func threshold(_ kind: AlertKind, _ mode: AwarenessMode) -> Double {
        switch (kind, mode) {
        case (.stoppedOffPlan, .road): return 2          // minutes
        case (.stoppedOffPlan, .trail): return 5
        case (.stoppedOffPlan, .ascent): return 10
        case (.fallingBehind, .road): return 5_000       // metres behind lead
        case (.fallingBehind, .trail): return 300
        case (.fallingBehind, .ascent): return 150       // vertical gap, metres
        case (.groupSpread, _): return mode == .road ? 10_000 : 1_000
        case (.offRoute, _): return 100
        case (.lowBattery, _): return 20
        case (.noSignal, _): return 30                   // minutes
        case (.turnaround, _): return 0                  // minutes since midnight, 0 = off
        }
    }

    static func unit(_ kind: AlertKind, _ mode: AwarenessMode) -> String {
        switch kind {
        case .stoppedOffPlan, .noSignal: return "MIN"
        case .fallingBehind: return mode == .ascent ? "M ↑" : (mode == .road ? "M" : "M")
        case .groupSpread, .offRoute: return "M"
        case .lowBattery: return "%"
        case .turnaround: return ""
        }
    }
}

struct AlertRule: Hashable {
    let kind: AlertKind
    let mode: AwarenessMode
    var threshold: Double
    var enabled: Bool
}

struct AwarenessEvent: Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    let kind: String          // AlertKind raw value, "regroup" or "ping"
    let value: Double?
    let targetUserId: UUID?
    let lat: Double?
    let lng: Double?
    let createdAt: Date
}

// MARK: Convoy

enum ConvoyReason: String, CaseIterable, Identifiable {
    case flatTire = "flat_tire", fuel, shortBreak = "short_break", lostConvoy = "lost_convoy"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flatTire: return String(localized: "Flat tire")
        case .fuel: return String(localized: "Fuel")
        case .shortBreak: return String(localized: "Short break")
        case .lostConvoy: return String(localized: "Lost the convoy")
        }
    }

    var icon: String {
        switch self {
        case .flatTire: return "exclamationmark.circle"
        case .fuel: return "fuelpump"
        case .shortBreak: return "cup.and.saucer"
        case .lostConvoy: return "location.slash"
        }
    }
}

struct ConvoyEvent: Identifiable, Hashable {
    let id: UUID
    let driverId: UUID
    let kind: String           // stopped | resumed | status | help
    let status: ConvoyReason?
    let etaMin: Int?
    let askOthers: String?     // keep_going | wait
    let lat: Double?
    let lng: Double?
    let createdAt: Date
}

// MARK: Live location

struct LiveFix: Identifiable, Hashable {
    let userId: UUID
    let lat: Double
    let lng: Double
    let altitude: Double?
    let accuracy: Double?
    let speed: Double?
    let heading: Double?
    let battery: Int?
    let recordedAt: Date
    var id: UUID { userId }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lng) }

    enum Freshness { case live, stale, offline }

    /// Never render a stale fix as live: > 2 min is stale, > 60 min is offline.
    func freshness(now: Date = Date()) -> Freshness {
        let age = now.timeIntervalSince(recordedAt)
        if age > 3_600 { return .offline }
        if age > 120 { return .stale }
        return .live
    }

    func ageLabel(now: Date = Date()) -> String {
        let m = Int(now.timeIntervalSince(recordedAt) / 60)
        return m < 60 ? "\(max(m, 1)) MIN" : "\(m / 60) H"
    }
}

struct LiveShare: Hashable {
    let userId: UUID
    let mode: String           // trip_end | recording
    let until: Date
    let lowPower: Bool
}

struct Readiness: Identifiable, Hashable {
    let userId: UUID
    let offlinePct: Int
    let gpsOn: Bool
    let battery: Int?
    let ready: Bool
    var id: UUID { userId }
}

// MARK: Geometry helpers (presentation only)

enum Geo {
    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Bearing in degrees (0 = north) from a to b.
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func compass(_ bearing: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int(((bearing + 22.5).truncatingRemainder(dividingBy: 360)) / 45)]
    }

    static func distanceLabel(_ meters: Double) -> String {
        meters >= 1_000 ? String(format: "%.1f KM", meters / 1_000) : "\(Int(meters.rounded())) M"
    }

    /// Distance along a polyline (metres from its start) of the point closest to `p`, and how far off the line it is.
    static func project(_ p: CLLocationCoordinate2D, onto line: [CLLocationCoordinate2D]) -> (along: Double, off: Double)? {
        guard line.count > 1 else { return nil }
        var best: (along: Double, off: Double)?
        var run = 0.0
        for i in 0..<(line.count - 1) {
            let a = line[i], b = line[i + 1]
            let seg = distance(a, b)
            // equirectangular projection is plenty for segments of a few hundred metres
            let mx = cos(a.latitude * .pi / 180) * 111_320, my = 110_540.0
            let ax = 0.0, ay = 0.0
            let bx = (b.longitude - a.longitude) * mx, by = (b.latitude - a.latitude) * my
            let px = (p.longitude - a.longitude) * mx, py = (p.latitude - a.latitude) * my
            let len2 = bx * bx + by * by
            let t = len2 == 0 ? 0 : max(0, min(1, ((px - ax) * bx + (py - ay) * by) / len2))
            let dx = px - t * bx, dy = py - t * by
            let off = (dx * dx + dy * dy).squareRoot()
            if best == nil || off < best!.off { best = (run + t * seg, off) }
            run += seg
        }
        return best
    }
}

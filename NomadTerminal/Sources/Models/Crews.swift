import Foundation

// Mirrors the crews / expeditions tables
// (backend/supabase/migrations/20261123000002_crews.sql). Pure data: every
// rule — who may see, join, rename, hand over — lives in Postgres.

enum CrewRole: String, Codable, CaseIterable {
    case owner, organizer, member

    var isManager: Bool { self == .owner || self == .organizer }
}

enum ExpeditionRole: String, Codable { case organizer, member }

enum TripType: String, Codable, CaseIterable, Identifiable {
    case roadTrip = "road_trip", hiking, camping, city, ski
    var id: String { rawValue }

    var title: String {
        switch self {
        case .roadTrip: return String(localized: "Road trip")
        case .hiking: return String(localized: "Hiking")
        case .camping: return String(localized: "Camping")
        case .city: return String(localized: "City")
        case .ski: return String(localized: "Ski")
        }
    }

    var icon: String {
        switch self {
        case .roadTrip: return "car.fill"
        case .hiking: return "figure.hiking"
        case .camping: return "tent.fill"
        case .city: return "building.2.fill"
        case .ski: return "snowflake"
        }
    }
}

enum ExpeditionStatus: String, Codable { case planning, active, completed, cancelled }

enum StopKind: String, Codable, CaseIterable, Identifiable {
    case accommodation, food, activity, poi
    var id: String { rawValue }

    var title: String {
        switch self {
        case .accommodation: return String(localized: "Stay")
        case .food: return String(localized: "Food")
        case .activity: return String(localized: "Activity")
        case .poi: return String(localized: "Place")
        }
    }

    var icon: String {
        switch self {
        case .accommodation: return "bed.double.fill"
        case .food: return "fork.knife"
        case .activity: return "figure.walk"
        case .poi: return "mappin.circle.fill"
        }
    }
}

/// A person on a roster (embedded `profiles` row).
struct CrewPerson: Hashable, Decodable {
    let id: UUID
    let username: String
    let displayName: String
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey { case id, username, displayName = "display_name", avatarUrl = "avatar_url" }

    var initials: String {
        displayName.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

struct Crew: Identifiable, Hashable {
    let id: UUID
    let name: String
    let coverImageUrl: String?
    let ownerId: UUID
    let createdAt: Date
}

/// One row of "my crews": the crew, my role in it and how many people it has.
struct CrewListItem: Identifiable, Hashable {
    let crew: Crew
    let myRole: CrewRole
    let memberCount: Int
    var id: UUID { crew.id }
}

struct CrewMember: Identifiable, Hashable {
    let person: CrewPerson
    let role: CrewRole
    let joinedAt: Date
    var id: UUID { person.id }
}

/// What the join screen shows before someone commits (`preview_crew_by_code`).
struct CrewInvitePreview: Hashable {
    let crewId: UUID
    let name: String
    let coverImageUrl: String?
    let memberCount: Int
    let alreadyMember: Bool
}

struct Expedition: Identifiable, Hashable {
    let id: UUID
    let crewId: UUID?
    let name: String
    let coverImageUrl: String?
    let tripType: TripType
    let startDate: Date?
    let endDate: Date?
    let status: ExpeditionStatus
    let organizerId: UUID
    let createdAt: Date
    var startedAt: Date? = nil
    /// "convoy" or "foot" — how the first leg started.
    var startMode: String? = nil
}

struct ExpeditionMember: Identifiable, Hashable {
    let person: CrewPerson
    let role: ExpeditionRole
    var awarenessRole: AwarenessRole? = nil
    /// The driver whose car this person rides in (their own id = they drive).
    var carDriverId: UUID? = nil
    var id: UUID { person.id }
}

/// A Nomad route attached to a trip, with just enough of the route to list it.
struct ExpeditionRouteItem: Identifiable, Hashable {
    let id: UUID
    let routeId: UUID
    let title: String
    let place: String
    let coverImageUrl: String?
    let distanceKm: Double
    var ascentM: Int = 0
    var difficulty: Route.Difficulty? = nil
    var dayIndex: Int?
    var position: Int
}

struct ExpeditionStop: Identifiable, Hashable {
    let id: UUID
    let kind: StopKind
    let title: String
    let notes: String?
    let lat: Double?
    let lng: Double?
    var dayIndex: Int?
    var position: Int
}

/// Itinerary content for one expedition.
struct ExpeditionItinerary {
    var routes: [ExpeditionRouteItem]
    var stops: [ExpeditionStop]

    /// One entry of the by-day view; `day == nil` is the "unscheduled" bucket.
    struct Day: Identifiable {
        let day: Int?
        var routes: [ExpeditionRouteItem]
        var stops: [ExpeditionStop]
        var id: Int { day ?? 0 }
    }

    /// Grouping for display only — ordering is whatever the server stored.
    var days: [Day] {
        let keys = Set(routes.map(\.dayIndex)).union(stops.map(\.dayIndex))
        return keys.sorted { ($0 ?? Int.max) < ($1 ?? Int.max) }.map { key in
            Day(day: key,
                routes: routes.filter { $0.dayIndex == key }.sorted { $0.position < $1.position },
                stops: stops.filter { $0.dayIndex == key }.sorted { $0.position < $1.position })
        }
    }

    // MARK: Reordering (presentation arithmetic only — the server stores it)

    /// Moves a route up (-1) or down (+1) among the routes of its own day.
    mutating func moveRoute(_ id: UUID, by delta: Int) {
        guard let item = routes.first(where: { $0.id == id }) else { return }
        let ids = routes.filter { $0.dayIndex == item.dayIndex }.sorted { $0.position < $1.position }.map(\.id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + delta) else { return }
        var order = ids
        order.swapAt(i, i + delta)
        for (n, rid) in order.enumerated() { if let k = routes.firstIndex(where: { $0.id == rid }) { routes[k].position = n } }
    }

    mutating func moveStop(_ id: UUID, by delta: Int) {
        guard let item = stops.first(where: { $0.id == id }) else { return }
        let ids = stops.filter { $0.dayIndex == item.dayIndex }.sorted { $0.position < $1.position }.map(\.id)
        guard let i = ids.firstIndex(of: id), ids.indices.contains(i + delta) else { return }
        var order = ids
        order.swapAt(i, i + delta)
        for (n, sid) in order.enumerated() { if let k = stops.firstIndex(where: { $0.id == sid }) { stops[k].position = n } }
    }

    /// Moves an item to another day (nil = unscheduled), appended at the end.
    mutating func setDay(routeID id: UUID, day: Int?) {
        guard let k = routes.firstIndex(where: { $0.id == id }) else { return }
        let last = routes.filter { $0.dayIndex == day }.map(\.position).max() ?? -1
        routes[k].dayIndex = day
        routes[k].position = last + 1
    }

    mutating func setDay(stopID id: UUID, day: Int?) {
        guard let k = stops.firstIndex(where: { $0.id == id }) else { return }
        let last = stops.filter { $0.dayIndex == day }.map(\.position).max() ?? -1
        stops[k].dayIndex = day
        stops[k].position = last + 1
    }
}

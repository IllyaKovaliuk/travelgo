import Foundation
import Supabase

/// Crews and expeditions. Thin client over Postgres: the client reads (RLS
/// scopes every table to its members) and every change is a server RPC — no
/// rule is decided here, so an Android client can reuse the same backend.
@MainActor
final class CrewRepository {
    static let shared = CrewRepository()
    private init() {}

    // MARK: Errors

    enum CrewError: LocalizedError {
        case inviteInvalid, crewFull, crewLimit, transferFirst, notAllowed, routeUnavailable, other(String)

        var errorDescription: String? {
            switch self {
            case .inviteInvalid: return String(localized: "This invite is invalid or has expired.")
            case .crewFull: return String(localized: "This crew is full.")
            case .crewLimit: return String(localized: "You've reached the limit of crews you can own.")
            case .transferFirst: return String(localized: "Hand over ownership before leaving.")
            case .notAllowed: return String(localized: "You don't have permission to do that.")
            case .routeUnavailable: return String(localized: "That route isn't available to add.")
            case .other(let message): return message
            }
        }

        init(_ error: Error) {
            let m = error.localizedDescription
            if m.contains("invite invalid or expired") { self = .inviteInvalid }
            else if m.contains("crew is full") { self = .crewFull }
            else if m.contains("crew limit reached") { self = .crewLimit }
            else if m.contains("transfer ownership before leaving") { self = .transferFirst }
            else if m.contains("route not available") { self = .routeUnavailable }
            else if m.contains("not allowed") { self = .notAllowed }
            else { self = .other(m) }
        }
    }

    private func session() async throws -> UUID {
        try await RouteRepository.shared.ensureSession()
    }

    // MARK: Date parsing (timestamps and `date` columns arrive as strings)

    nonisolated private static func parse(_ s: String) -> Date? {
        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = full.date(from: s) { return d }
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = TimeZone(identifier: "UTC")
        day.locale = Locale(identifier: "en_US_POSIX")
        return day.date(from: s)
    }

    nonisolated private static func dayString(_ date: Date?) -> String? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: DTOs

    private struct CrewDTO: Decodable {
        let id: UUID
        let name: String
        let coverImageUrl: String?
        let ownerId: UUID
        let createdAt: String
        enum CodingKeys: String, CodingKey { case id, name, coverImageUrl = "cover_image_url", ownerId = "owner_id", createdAt = "created_at" }

        var model: Crew {
            Crew(id: id, name: name, coverImageUrl: coverImageUrl, ownerId: ownerId,
                 createdAt: CrewRepository.parse(createdAt) ?? Date())
        }
    }

    private struct CountDTO: Decodable { let count: Int }

    private struct ExpeditionDTO: Decodable {
        let id: UUID
        let crewId: UUID?
        let name: String
        let coverImageUrl: String?
        let tripType: TripType
        let startDate: String?
        let endDate: String?
        let status: ExpeditionStatus
        let organizerId: UUID
        let createdAt: String
        enum CodingKeys: String, CodingKey {
            case id, name, status
            case crewId = "crew_id", coverImageUrl = "cover_image_url", tripType = "trip_type"
            case startDate = "start_date", endDate = "end_date", organizerId = "organizer_id", createdAt = "created_at"
        }

        var model: Expedition {
            Expedition(id: id, crewId: crewId, name: name, coverImageUrl: coverImageUrl, tripType: tripType,
                       startDate: startDate.flatMap(CrewRepository.parse), endDate: endDate.flatMap(CrewRepository.parse),
                       status: status, organizerId: organizerId, createdAt: CrewRepository.parse(createdAt) ?? Date())
        }
    }

    // MARK: Crews — reads

    func fetchMyCrews() async throws -> [CrewListItem] {
        let me = try await session()
        struct Row: Decodable {
            let role: CrewRole
            let crews: Nested
            struct Nested: Decodable {
                let id: UUID
                let name: String
                let coverImageUrl: String?
                let ownerId: UUID
                let createdAt: String
                let crewMembers: [CountDTO]
                enum CodingKeys: String, CodingKey {
                    case id, name, coverImageUrl = "cover_image_url", ownerId = "owner_id"
                    case createdAt = "created_at", crewMembers = "crew_members"
                }
            }
        }
        let rows: [Row] = try await supabase.from("crew_members")
            .select("role, crews(id, name, cover_image_url, owner_id, created_at, crew_members(count))")
            .eq("user_id", value: me.uuidString)
            .execute().value
        return rows.map {
            let c = $0.crews
            let crew = Crew(id: c.id, name: c.name, coverImageUrl: c.coverImageUrl, ownerId: c.ownerId,
                            createdAt: Self.parse(c.createdAt) ?? Date())
            return CrewListItem(crew: crew, myRole: $0.role, memberCount: c.crewMembers.first?.count ?? 1)
        }
        .sorted { $0.crew.createdAt > $1.crew.createdAt }
    }

    func fetchCrew(id: UUID) async throws -> Crew {
        let dto: CrewDTO = try await supabase.from("crews")
            .select("id, name, cover_image_url, owner_id, created_at")
            .eq("id", value: id.uuidString)
            .single().execute().value
        return dto.model
    }

    func fetchCrewMembers(crewId: UUID) async throws -> [CrewMember] {
        struct Row: Decodable {
            let role: CrewRole
            let joinedAt: String
            let profiles: CrewPerson
            enum CodingKeys: String, CodingKey { case role, joinedAt = "joined_at", profiles }
        }
        let rows: [Row] = try await supabase.from("crew_members")
            .select("role, joined_at, profiles!crew_members_user_id_fkey(id, username, display_name, avatar_url)")
            .eq("crew_id", value: crewId.uuidString)
            .order("joined_at")
            .execute().value
        return rows.map { CrewMember(person: $0.profiles, role: $0.role, joinedAt: Self.parse($0.joinedAt) ?? Date()) }
    }

    func fetchCrewExpeditions(crewId: UUID) async throws -> [Expedition] {
        let rows: [ExpeditionDTO] = try await supabase.from("expeditions")
            .select()
            .eq("crew_id", value: crewId.uuidString)
            .order("start_date", ascending: true, nullsFirst: false)
            .execute().value
        return rows.map(\.model)
    }

    // MARK: Crews — mutations (RPC only)

    func createCrew(name: String, coverURL: String? = nil) async throws -> UUID {
        try await session()
        struct Params: Encodable { let p_name: String; let p_cover: String? }
        do {
            return try await supabase.rpc("create_crew", params: Params(p_name: name, p_cover: coverURL)).execute().value
        } catch { throw CrewError(error) }
    }

    func updateCrew(id: UUID, name: String, coverURL: String? = nil) async throws {
        struct Params: Encodable { let p_crew_id: UUID; let p_name: String; let p_cover: String? }
        do {
            try await supabase.rpc("update_crew", params: Params(p_crew_id: id, p_name: name, p_cover: coverURL)).execute()
        } catch { throw CrewError(error) }
    }

    func leaveCrew(id: UUID) async throws {
        struct Params: Encodable { let p_crew_id: UUID }
        do { try await supabase.rpc("leave_crew", params: Params(p_crew_id: id)).execute() }
        catch { throw CrewError(error) }
    }

    func deleteCrew(id: UUID) async throws {
        struct Params: Encodable { let p_crew_id: UUID }
        do { try await supabase.rpc("delete_crew", params: Params(p_crew_id: id)).execute() }
        catch { throw CrewError(error) }
    }

    func removeMember(crewId: UUID, userId: UUID) async throws {
        struct Params: Encodable { let p_crew_id: UUID; let p_user_id: UUID }
        do { try await supabase.rpc("remove_crew_member", params: Params(p_crew_id: crewId, p_user_id: userId)).execute() }
        catch { throw CrewError(error) }
    }

    func setMemberRole(crewId: UUID, userId: UUID, role: CrewRole) async throws {
        struct Params: Encodable { let p_crew_id: UUID; let p_user_id: UUID; let p_role: String }
        do {
            try await supabase.rpc("set_crew_member_role",
                                   params: Params(p_crew_id: crewId, p_user_id: userId, p_role: role.rawValue)).execute()
        } catch { throw CrewError(error) }
    }

    // MARK: Invites

    func createInvite(crewId: UUID, maxUses: Int? = nil, ttlDays: Int = 14) async throws -> String {
        struct Params: Encodable { let p_crew_id: UUID; let p_max_uses: Int?; let p_ttl_days: Int }
        do {
            return try await supabase.rpc("create_crew_invite",
                                          params: Params(p_crew_id: crewId, p_max_uses: maxUses, p_ttl_days: ttlDays))
                .execute().value
        } catch { throw CrewError(error) }
    }

    /// Managers only; for anyone else the server silently does nothing.
    func revokeInvite(code: String) async throws {
        struct Params: Encodable { let p_code: String }
        do { try await supabase.rpc("revoke_crew_invite", params: Params(p_code: code)).execute() }
        catch { throw CrewError(error) }
    }

    func previewInvite(code: String) async throws -> CrewInvitePreview? {
        try await session()
        struct Row: Decodable {
            let crewId: UUID
            let name: String
            let coverImageUrl: String?
            let memberCount: Int
            let alreadyMember: Bool
            enum CodingKeys: String, CodingKey {
                case name, crewId = "crew_id", coverImageUrl = "cover_image_url"
                case memberCount = "member_count", alreadyMember = "already_member"
            }
        }
        struct Params: Encodable { let p_code: String }
        let rows: [Row] = try await supabase.rpc("preview_crew_by_code", params: Params(p_code: code)).execute().value
        return rows.first.map {
            CrewInvitePreview(crewId: $0.crewId, name: $0.name, coverImageUrl: $0.coverImageUrl,
                              memberCount: $0.memberCount, alreadyMember: $0.alreadyMember)
        }
    }

    /// Returns the crew id that was joined.
    @discardableResult
    func joinCrew(code: String) async throws -> UUID {
        try await session()
        struct Params: Encodable { let p_code: String }
        do {
            return try await supabase.rpc("join_crew_by_code", params: Params(p_code: code)).execute().value
        } catch { throw CrewError(error) }
    }

    // MARK: Expeditions — reads

    func fetchMyExpeditions() async throws -> [Expedition] {
        let rows: [ExpeditionDTO] = try await supabase.from("expeditions")
            .select()
            .order("start_date", ascending: true, nullsFirst: false)
            .execute().value
        return rows.map(\.model)
    }

    func fetchExpedition(id: UUID) async throws -> Expedition {
        let dto: ExpeditionDTO = try await supabase.from("expeditions")
            .select().eq("id", value: id.uuidString).single().execute().value
        return dto.model
    }

    func fetchExpeditionMembers(expeditionId: UUID) async throws -> [ExpeditionMember] {
        struct Row: Decodable {
            let role: ExpeditionRole
            let profiles: CrewPerson
        }
        let rows: [Row] = try await supabase.from("expedition_members")
            .select("role, profiles!expedition_members_user_id_fkey(id, username, display_name, avatar_url)")
            .eq("expedition_id", value: expeditionId.uuidString)
            .order("joined_at")
            .execute().value
        return rows.map { ExpeditionMember(person: $0.profiles, role: $0.role) }
    }

    func fetchItinerary(expeditionId: UUID) async throws -> ExpeditionItinerary {
        struct RouteRow: Decodable {
            let id: UUID
            let routeId: UUID
            let dayIndex: Int?
            let position: Int
            // nil when the route stopped being readable (made private / removed)
            // — skipped rather than failing the whole itinerary.
            let routes: Route?
            struct Route: Decodable {
                let title: String
                let place: String
                let coverImageUrl: String?
                let distanceKm: Double
                let ascentM: Int?
                let difficulty: String?
                enum CodingKeys: String, CodingKey {
                    case title, place, difficulty, coverImageUrl = "cover_image_url", distanceKm = "distance_km", ascentM = "ascent_m"
                }
            }
            enum CodingKeys: String, CodingKey { case id, position, routes, routeId = "route_id", dayIndex = "day_index" }
        }
        struct StopRow: Decodable {
            let id: UUID
            let kind: StopKind
            let title: String
            let notes: String?
            let lat: Double?
            let lng: Double?
            let dayIndex: Int?
            let position: Int
            enum CodingKeys: String, CodingKey { case id, kind, title, notes, lat, lng, position, dayIndex = "day_index" }
        }
        let routeRows: [RouteRow] = try await supabase.from("expedition_routes")
            .select("id, route_id, day_index, position, routes(title, place, cover_image_url, distance_km, ascent_m, difficulty)")
            .eq("expedition_id", value: expeditionId.uuidString)
            .order("position").execute().value
        let stopRows: [StopRow] = try await supabase.from("expedition_stops")
            .select("id, kind, title, notes, lat, lng, day_index, position")
            .eq("expedition_id", value: expeditionId.uuidString)
            .order("position").execute().value
        return ExpeditionItinerary(
            routes: routeRows.compactMap { row in
                guard let route = row.routes else { return nil }
                return ExpeditionRouteItem(id: row.id, routeId: row.routeId, title: route.title, place: route.place,
                                           coverImageUrl: route.coverImageUrl, distanceKm: route.distanceKm,
                                           ascentM: route.ascentM ?? 0,
                                           difficulty: route.difficulty.flatMap { Route.Difficulty(rawValue: $0.uppercased()) },
                                           dayIndex: row.dayIndex, position: row.position)
            },
            stops: stopRows.map {
                ExpeditionStop(id: $0.id, kind: $0.kind, title: $0.title, notes: $0.notes, lat: $0.lat, lng: $0.lng,
                               dayIndex: $0.dayIndex, position: $0.position)
            })
    }

    // MARK: Expeditions — mutations (RPC only)

    func createExpedition(name: String, crewId: UUID?, tripType: TripType, start: Date?, end: Date?,
                          coverURL: String? = nil) async throws -> UUID {
        try await session()
        struct Params: Encodable {
            let p_name: String; let p_crew_id: UUID?; let p_trip_type: String
            let p_start: String?; let p_end: String?; let p_cover: String?
        }
        do {
            return try await supabase.rpc("create_expedition", params: Params(
                p_name: name, p_crew_id: crewId, p_trip_type: tripType.rawValue,
                p_start: Self.dayString(start), p_end: Self.dayString(end), p_cover: coverURL)).execute().value
        } catch { throw CrewError(error) }
    }

    func updateExpedition(id: UUID, name: String, tripType: TripType, start: Date?, end: Date?,
                          status: ExpeditionStatus? = nil) async throws {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_name: String; let p_trip_type: String
            let p_start: String?; let p_end: String?; let p_status: String?
        }
        do {
            try await supabase.rpc("update_expedition", params: Params(
                p_expedition_id: id, p_name: name, p_trip_type: tripType.rawValue,
                p_start: Self.dayString(start), p_end: Self.dayString(end), p_status: status?.rawValue)).execute()
        } catch { throw CrewError(error) }
    }

    func deleteExpedition(id: UUID) async throws {
        struct Params: Encodable { let p_expedition_id: UUID }
        do { try await supabase.rpc("delete_expedition", params: Params(p_expedition_id: id)).execute() }
        catch { throw CrewError(error) }
    }

    func leaveExpedition(id: UUID) async throws {
        struct Params: Encodable { let p_expedition_id: UUID }
        do { try await supabase.rpc("leave_expedition", params: Params(p_expedition_id: id)).execute() }
        catch { throw CrewError(error) }
    }

    @discardableResult
    func addRoute(expeditionId: UUID, routeId: UUID, day: Int? = nil) async throws -> UUID {
        struct Params: Encodable { let p_expedition_id: UUID; let p_route_id: UUID; let p_day: Int? }
        do {
            return try await supabase.rpc("add_route_to_expedition",
                                          params: Params(p_expedition_id: expeditionId, p_route_id: routeId, p_day: day))
                .execute().value
        } catch { throw CrewError(error) }
    }

    @discardableResult
    func addStop(expeditionId: UUID, kind: StopKind, title: String, notes: String? = nil,
                 lat: Double? = nil, lng: Double? = nil, day: Int? = nil) async throws -> UUID {
        struct Params: Encodable {
            let p_expedition_id: UUID; let p_kind: String; let p_title: String
            let p_notes: String?; let p_lat: Double?; let p_lng: Double?; let p_day: Int?
        }
        do {
            return try await supabase.rpc("add_expedition_stop", params: Params(
                p_expedition_id: expeditionId, p_kind: kind.rawValue, p_title: title,
                p_notes: notes, p_lat: lat, p_lng: lng, p_day: day)).execute().value
        } catch { throw CrewError(error) }
    }

    func removeRoute(itemId: UUID) async throws {
        struct Params: Encodable { let p_item_id: UUID }
        do { try await supabase.rpc("remove_expedition_route", params: Params(p_item_id: itemId)).execute() }
        catch { throw CrewError(error) }
    }

    func removeStop(itemId: UUID) async throws {
        struct Params: Encodable { let p_item_id: UUID }
        do { try await supabase.rpc("remove_expedition_stop", params: Params(p_item_id: itemId)).execute() }
        catch { throw CrewError(error) }
    }

    /// Persists a new day / order for the whole itinerary in one call.
    func reorder(expeditionId: UUID, itinerary: ExpeditionItinerary) async throws {
        struct Item: Encodable { let id: UUID; let day_index: Int?; let position: Int }
        struct Params: Encodable { let p_expedition_id: UUID; let p_routes: [Item]; let p_stops: [Item] }
        let params = Params(
            p_expedition_id: expeditionId,
            p_routes: itinerary.routes.map { Item(id: $0.id, day_index: $0.dayIndex, position: $0.position) },
            p_stops: itinerary.stops.map { Item(id: $0.id, day_index: $0.dayIndex, position: $0.position) })
        do { try await supabase.rpc("reorder_expedition_items", params: params).execute() }
        catch { throw CrewError(error) }
    }
}

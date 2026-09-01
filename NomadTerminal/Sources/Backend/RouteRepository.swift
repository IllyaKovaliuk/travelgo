import Foundation
import Supabase

/// Talks to Postgres/Auth on behalf of the app. Auth starts anonymous —
/// every device gets a real, persisted user row the moment it needs one
/// (liking, saving) — and later upgrades to a real account without losing
/// that data, once the Auth screen ships.
actor RouteRepository {
    static let shared = RouteRepository()

    /// Ensures there's a logged-in (possibly anonymous) session and
    /// returns its user id.
    @discardableResult
    func ensureSession() async throws -> UUID {
        if let session = try? await supabase.auth.session {
            return session.user.id
        }
        let session = try await supabase.auth.signInAnonymously()
        return session.user.id
    }

    func fetchRoutes() async throws -> [Route] {
        let rows: [RouteDTO] = try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*)")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .order("created_at")
            .execute()
            .value
        return rows.map { $0.toRoute() }
    }

    /// Real filtered search — backs the Search screen's "Show results".
    /// Text matching (title/place) happens client-side after the filtered
    /// fetch since the dataset is still small; move to a server-side
    /// `.or(...)` filter once it grows.
    func searchRoutes(query: String, transports: [String], difficulties: [String], minKM: Double, maxKM: Double) async throws -> [Route] {
        let rows: [RouteDTO] = try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*)")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .in("transport", values: transports)
            .in("difficulty", values: difficulties)
            .gte("distance_km", value: minKM)
            .lte("distance_km", value: maxKM)
            .order("created_at")
            .execute()
            .value

        var results = rows.map { $0.toRoute() }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty {
            results = results.filter {
                $0.title.lowercased().contains(trimmed) || $0.place.lowercased().contains(trimmed)
            }
        }
        return results
    }

    private struct LikeRow: Encodable {
        let route_id: String
        let user_id: String
    }

    private struct SaveRowInsert: Codable {
        let route_id: String
        let user_id: String
        let downloaded_offline: Bool
    }

    func setLiked(routeId: String, liked: Bool) async throws {
        let userId = try await ensureSession()
        guard let routeUUID = UUID(uuidString: routeId) else { return }
        if liked {
            try await supabase.from("route_likes")
                .upsert(LikeRow(route_id: routeUUID.uuidString, user_id: userId.uuidString))
                .execute()
        } else {
            try await supabase.from("route_likes")
                .delete()
                .eq("route_id", value: routeUUID.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        }
    }

    func setSaved(routeId: String, saved: Bool, downloadedOffline: Bool = false) async throws {
        let userId = try await ensureSession()
        guard let routeUUID = UUID(uuidString: routeId) else { return }
        if saved {
            try await supabase.from("route_saves")
                .upsert(SaveRowInsert(route_id: routeUUID.uuidString, user_id: userId.uuidString, downloaded_offline: downloadedOffline))
                .execute()
        } else {
            try await supabase.from("route_saves")
                .delete()
                .eq("route_id", value: routeUUID.uuidString)
                .eq("user_id", value: userId.uuidString)
                .execute()
        }
    }

    /// Whether the current session already saved this route — lets a
    /// freshly opened Route Detail show the right button state.
    func isSaved(routeId: String) async -> Bool {
        guard let userId = try? await ensureSession(), let routeUUID = UUID(uuidString: routeId) else { return false }
        let rows: [SaveRowInsert]? = try? await supabase
            .from("route_saves")
            .select("route_id, user_id, downloaded_offline")
            .eq("route_id", value: routeUUID.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return !(rows?.isEmpty ?? true)
    }

    struct SavedRoute {
        let route: Route
        let downloadedOffline: Bool
    }

    /// Everything the current session has saved, richest data first (same
    /// embed shape as `fetchRoutes`) so the Saved screen can render real
    /// cards instead of the mock library.
    func fetchSavedRoutes() async throws -> [SavedRoute] {
        let userId = try await ensureSession()

        struct SaveRow: Decodable {
            let downloadedOffline: Bool
            let routes: RouteDTO
            enum CodingKeys: String, CodingKey {
                case downloadedOffline = "downloaded_offline"
                case routes
            }
        }

        let rows: [SaveRow] = try await supabase
            .from("route_saves")
            .select("downloaded_offline, routes!route_saves_route_id_fkey(*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*))")
            .eq("user_id", value: userId.uuidString)
            .order("created_at")
            .execute()
            .value

        return rows.map { SavedRoute(route: $0.routes.toRoute(), downloadedOffline: $0.downloadedOffline) }
    }

    // MARK: - Publishing

    struct NewRoute {
        var title: String
        var place: String
        var difficulty: String
        var transport: String
        var transportLabel: String
        var distanceKM: Double
        var visibility: String = "public"
    }

    /// Inserts a real row in `routes` under the current session as author.
    /// No segments/requirements yet — the details/gear steps of the log-a-route
    /// flow are still visual-only, so a published route starts bare and can be
    /// filled in from Route Detail later once editing ships.
    func publishRoute(_ input: NewRoute) async throws -> Route {
        let userId = try await ensureSession()

        struct Insert: Encodable {
            let author_id: String
            let title: String
            let place: String
            let difficulty: String
            let transport: String
            let transport_label: String
            let distance_km: Double
            let visibility: String
            let status: String
        }

        let payload = Insert(
            author_id: userId.uuidString,
            title: input.title,
            place: input.place,
            difficulty: input.difficulty,
            transport: input.transport,
            transport_label: input.transportLabel,
            distance_km: input.distanceKM,
            visibility: input.visibility,
            status: "published"
        )

        let row: RouteDTO = try await supabase
            .from("routes")
            .insert(payload)
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*)")
            .single()
            .execute()
            .value
        return row.toRoute()
    }

    // MARK: - Comments

    struct Comment: Identifiable {
        let id: String
        let authorName: String
        let authorInitials: String
        let body: String
        let createdAgo: String
    }

    private struct CommentDTO: Decodable {
        let id: UUID
        let body: String
        let createdAt: String
        let profiles: ProfileDTO
        enum CodingKeys: String, CodingKey {
            case id, body, profiles
            case createdAt = "created_at"
        }
    }

    func fetchComments(routeId: String) async throws -> [Comment] {
        guard let routeUUID = UUID(uuidString: routeId) else { return [] }
        let rows: [CommentDTO] = try await supabase
            .from("route_comments")
            .select("id, body, created_at, profiles!route_comments_author_id_fkey(*)")
            .eq("route_id", value: routeUUID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map {
            Comment(
                id: $0.id.uuidString,
                authorName: $0.profiles.displayName,
                authorInitials: initials(from: $0.profiles.displayName),
                body: $0.body,
                createdAgo: relativeTime(from: $0.createdAt)
            )
        }
    }

    func postComment(routeId: String, body: String) async throws {
        let userId = try await ensureSession()
        guard let routeUUID = UUID(uuidString: routeId) else { return }
        struct Insert: Encodable {
            let route_id: String
            let author_id: String
            let body: String
        }
        try await supabase.from("route_comments")
            .insert(Insert(route_id: routeUUID.uuidString, author_id: userId.uuidString, body: body))
            .execute()
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func relativeTime(from iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let seconds = -date.timeIntervalSinceNow
        if seconds < 60 { return "JUST NOW" }
        if seconds < 3600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86400 { return "\(Int(seconds / 3600))H AGO" }
        return "\(Int(seconds / 86400))D AGO"
    }
}

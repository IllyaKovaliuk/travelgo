import Foundation
import Supabase
import CoreLocation

/// Talks to Postgres/Auth on behalf of the app. Registration is mandatory —
/// `OnboardingContainer` always ends at a real sign-in/sign-up before
/// anyone reaches the feed — so every call in here should find a real
/// session already sitting there.
actor RouteRepository {
    static let shared = RouteRepository()

    /// Returns the current session's user id. Falls back to a throwaway
    /// anonymous sign-in only as a last-resort guard against a caller
    /// somehow running before onboarding's auth gate — not a supported
    /// product path anymore (that's what let people browse without ever
    /// creating a real account, which is exactly what's no longer allowed).
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
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count)")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .order("created_at")
            .execute()
            .value
        return rows.map { $0.toRoute() }
    }

    struct PublicProfile {
        let id: String
        let username: String
        let displayName: String
        let homeLocation: String?
        let kmLogged: Double
        /// Real column on `profiles`, but nothing anywhere in the app
        /// actually increments it (no "mark this route done" action
        /// exists yet) — always 0 for every real account today. Kept in
        /// the model since it's real schema, not fabricated, but callers
        /// should treat it as "not implemented yet," not a real stat.
        let routesCompleted: Int
        let avatarUrl: String?
        let initials: String
    }

    /// Any user's real public profile — `fetchMyProfile()` only ever reads
    /// the *current* session's own row; this is the same shape for an
    /// arbitrary `userId`, for a real "view this person's profile" screen
    /// (tapping an author anywhere) rather than just the "my profile" tab.
    func fetchPublicProfile(userId: String) async throws -> PublicProfile {
        struct Row: Decodable {
            let id: UUID
            let username: String
            let display_name: String
            let home_location: String?
            let km_logged: Double
            let routes_completed: Int
            let avatar_url: String?
        }
        let row: Row = try await supabase
            .from("profiles")
            .select("id, username, display_name, home_location, km_logged, routes_completed, avatar_url")
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        let initials = row.display_name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        return PublicProfile(
            id: row.id.uuidString, username: row.username, displayName: row.display_name,
            homeLocation: row.home_location, kmLogged: row.km_logged, routesCompleted: row.routes_completed,
            avatarUrl: row.avatar_url, initials: initials.isEmpty ? "?" : initials
        )
    }

    /// A specific author's real published routes — same shape/filters as
    /// `fetchRoutes()`, just scoped to one author instead of everyone, for
    /// "routes this person created" on their public profile.
    func fetchUserRoutes(authorId: String) async throws -> [Route] {
        let rows: [RouteDTO] = try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count)")
            .eq("author_id", value: authorId)
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toRoute() }
    }

    /// "Following" feed tab — routes from authors the current session
    /// actually follows. Was previously just relabeled `fetchRoutes()` —
    /// same content under all 3 tabs regardless of which was selected.
    func fetchFollowingRoutes() async throws -> [Route] {
        let userId = try await ensureSession()
        struct FollowRow: Decodable { let followee_id: UUID }
        let follows: [FollowRow] = try await supabase
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: userId.uuidString)
            .execute()
            .value
        guard !follows.isEmpty else { return [] }
        let ids = follows.map { $0.followee_id.uuidString }
        let rows: [RouteDTO] = try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count)")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .in("author_id", values: ids)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toRoute() }
    }

    /// "Nearby" feed tab — published routes sorted by real distance from
    /// `here`, using each route's first recorded GPS point. Routes with no
    /// real track (older/manual entries) have no real distance to sort by,
    /// so they're left out rather than faked into a random position.
    func fetchNearbyRoutes(from here: CLLocationCoordinate2D) async throws -> [Route] {
        let all = try await fetchRoutes()
        let origin = CLLocation(latitude: here.latitude, longitude: here.longitude)
        let withDistance: [(route: Route, distance: CLLocationDistance)] = all.compactMap { route in
            guard let first = route.detail.trackPoints.first else { return nil }
            let point = CLLocation(latitude: first.lat, longitude: first.lng)
            return (route, origin.distance(from: point))
        }
        return withDistance.sorted { $0.distance < $1.distance }.map(\.route)
    }

    /// Every distinct region (`place`) among published public routes, for
    /// Search's Region picker — real values from the actual data instead of
    /// a hardcoded list that drifts from what's really out there.
    struct RouteLocation {
        let place: String
        let coordinate: CLLocationCoordinate2D
        let coverImageUrl: String?
    }

    /// Lightweight — just place + one representative coordinate (+ cover
    /// photo, for the region-picker's photo pins) per route. Skips the
    /// heavy segments/requirements/POI/like/comment embeds `fetchRoutes`
    /// carries since none of that is needed here.
    func fetchRouteLocations() async throws -> [RouteLocation] {
        struct Row: Decodable { let place: String; let track_points: [TrackPoint]; let cover_image_url: String? }
        let rows: [Row] = try await supabase
            .from("routes")
            .select("place, track_points, cover_image_url")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .execute()
            .value
        return rows.compactMap { row in
            guard let first = row.track_points.first else { return nil }
            return RouteLocation(place: row.place, coordinate: first.coordinate, coverImageUrl: row.cover_image_url)
        }
    }

    func fetchRegions() async throws -> [String] {
        struct PlaceRow: Decodable { let place: String }
        let rows: [PlaceRow] = try await supabase
            .from("routes")
            .select("place")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .execute()
            .value
        return Array(Set(rows.map(\.place))).sorted()
    }

    /// A single route's raw DTO (not the mapped `Route`) — used by
    /// `OfflineRouteStore` to cache exactly what the server sent, so
    /// replaying it later through the same `toRoute()` mapper can never
    /// drift from the live shape.
    func fetchRouteDTO(id: String) async throws -> RouteDTO {
        try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count)")
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    /// Real filtered search — backs the Search screen's "Show results".
    /// Text matching (title/place) happens client-side after the filtered
    /// fetch since the dataset is still small; move to a server-side
    /// `.or(...)` filter once it grows.
    func searchRoutes(
        query: String, transports: [String], difficulties: [String],
        minKM: Double, maxKM: Double, minAscentM: Double? = nil, maxAscentM: Double? = nil, region: String? = nil
    ) async throws -> [Route] {
        var builder = supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count)")
            .eq("status", value: "published")
            .eq("visibility", value: "public")
            .in("transport", values: transports)
            .in("difficulty", values: difficulties)
            .gte("distance_km", value: minKM)
            .lte("distance_km", value: maxKM)
        // Ascent is nullable (older/manual routes) — only filter on it when
        // the caller narrowed the range, so a default full-range slider
        // doesn't silently exclude every route missing that field.
        if let minAscentM { builder = builder.gte("ascent_m", value: minAscentM) }
        if let maxAscentM { builder = builder.lte("ascent_m", value: maxAscentM) }
        if let region { builder = builder.eq("place", value: region) }

        let rows: [RouteDTO] = try await builder
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
    func isLiked(routeId: String) async -> Bool {
        guard let userId = try? await ensureSession(), let routeUUID = UUID(uuidString: routeId) else { return false }
        struct LikeRow: Decodable { let route_id: String }
        let rows: [LikeRow]? = try? await supabase
            .from("route_likes")
            .select("route_id")
            .eq("route_id", value: routeUUID.uuidString)
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
        return !(rows?.isEmpty ?? true)
    }

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

    private struct FollowRow: Codable {
        let follower_id: String
        let followee_id: String
    }

    func setFollowing(authorId: String, following: Bool) async throws {
        let userId = try await ensureSession()
        guard authorId != userId.uuidString else { return } // can't follow yourself
        if following {
            try await supabase.from("follows")
                .upsert(FollowRow(follower_id: userId.uuidString, followee_id: authorId))
                .execute()
        } else {
            try await supabase.from("follows")
                .delete()
                .eq("follower_id", value: userId.uuidString)
                .eq("followee_id", value: authorId)
                .execute()
        }
    }

    /// Whether the current session already follows this author — lets a
    /// freshly rendered card show the right button state.
    func isFollowing(authorId: String) async -> Bool {
        guard let userId = try? await ensureSession() else { return false }
        let rows: [FollowRow]? = try? await supabase
            .from("follows")
            .select("follower_id, followee_id")
            .eq("follower_id", value: userId.uuidString)
            .eq("followee_id", value: authorId)
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
            .select("downloaded_offline, routes!route_saves_route_id_fkey(*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count))")
            .eq("user_id", value: userId.uuidString)
            .order("created_at")
            .execute()
            .value

        return rows.map { SavedRoute(route: $0.routes.toRoute(), downloadedOffline: $0.downloadedOffline) }
    }

    // MARK: - Cover photos

    /// Uploads a picked photo to the `route-covers` bucket and returns its
    /// public URL. Called from the log-a-route flow before publish.
    func uploadCoverImage(_ data: Data) async throws -> String {
        let userId = try await ensureSession()
        let path = "\(userId.uuidString)/\(UUID().uuidString).jpg"
        try await supabase.storage.from("route-covers").upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg")
        )
        return try supabase.storage.from("route-covers").getPublicURL(path: path).absoluteString
    }

    // MARK: - Avatar photo

    /// Same bucket as cover photos (no new bucket/policy needed — the
    /// existing `route-covers` insert policy is just "any authenticated
    /// user," not scoped per-folder, so this is exactly as safe/unsafe as
    /// cover uploads already were), but at a *fixed* path per user
    /// (`avatars/<id>/avatar.jpg`, `upsert: true`) so re-uploading replaces
    /// the old photo instead of piling up orphaned files every time
    /// someone changes it.
    func uploadAvatarImage(_ data: Data) async throws -> String {
        let userId = try await ensureSession()
        let path = "avatars/\(userId.uuidString)/avatar.jpg"
        try await supabase.storage.from("route-covers").upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true)
        )
        // The bucket is public and the same file path is reused every time,
        // so a CDN/browser cache would otherwise keep serving the old photo
        // under the same URL — a real cache-busting query param, not
        // decoration.
        let base = try supabase.storage.from("route-covers").getPublicURL(path: path).absoluteString
        return "\(base)?v=\(Int(Date().timeIntervalSince1970))"
    }

    func updateMyAvatarUrl(_ url: String) async throws {
        let userId = try await ensureSession()
        struct Update: Encodable { let avatar_url: String }
        try await supabase.from("profiles")
            .update(Update(avatar_url: url))
            .eq("id", value: userId.uuidString)
            .execute()
    }

    /// Real count of rows in `follows` where this user is the one being
    /// followed — backs the "FOLLOWERS" stat on both the current session's
    /// own profile and anyone else's.
    func fetchFollowerCount(userId: String) async -> Int {
        struct CountRow: Decodable { let followee_id: String }
        let rows: [CountRow] = (try? await supabase
            .from("follows")
            .select("followee_id")
            .eq("followee_id", value: userId)
            .execute()
            .value) ?? []
        return rows.count
    }

    // MARK: - Publishing

    struct NewRoute {
        var title: String
        var place: String
        var difficulty: String
        var transport: String
        var transportLabel: String
        var distanceKM: Double
        var ascentM: Int = 0
        var highPointM: Int = 0
        var season: String = ""
        var duration: String = ""
        var quote: String = ""
        var trackPoints: [TrackPoint] = []
        var segments: [NewSegment] = []
        var requirements: [NewRequirement] = []
        var pois: [NewPOI] = []
        var coverImageUrl: String? = nil
        var visibility: String = "public"
    }

    struct NewSegment {
        var icon: String
        var name: String
        var distanceKM: Double
        var tint: String
    }

    struct NewPOI {
        var lat: Double
        var lng: Double
        var category: String
        var title: String
        var note: String?
    }

    struct NewRequirement {
        var icon: String
        var title: String
        var subtitle: String
        var tint: String
    }

    /// Inserts a real row in `routes` under the current session as author,
    /// plus any segments/requirements the log-a-route flow collected.
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
            let ascent_m: Int
            let high_point_m: Int
            let season: String?
            let duration: String?
            let quote: String?
            let track_points: [TrackPoint]
            let cover_image_url: String?
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
            ascent_m: input.ascentM,
            high_point_m: input.highPointM,
            season: input.season.isEmpty ? nil : input.season,
            duration: input.duration.isEmpty ? nil : input.duration,
            quote: input.quote.isEmpty ? nil : input.quote,
            track_points: input.trackPoints,
            cover_image_url: input.coverImageUrl,
            visibility: input.visibility,
            status: "published"
        )

        let inserted: RouteDTO = try await supabase
            .from("routes")
            .insert(payload)
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count)")
            .single()
            .execute()
            .value

        if !input.segments.isEmpty {
            struct SegmentInsert: Encodable {
                let route_id: String, icon: String, name: String, distance_km: Double, tint: String, sort_order: Int
            }
            let rows = input.segments.enumerated().map {
                SegmentInsert(route_id: inserted.id.uuidString, icon: $1.icon, name: $1.name, distance_km: $1.distanceKM, tint: $1.tint, sort_order: $0)
            }
            try await supabase.from("route_segments").insert(rows).execute()
        }

        if !input.requirements.isEmpty {
            struct RequirementInsert: Encodable {
                let route_id: String, icon: String, title: String, subtitle: String, tint: String, sort_order: Int
            }
            let rows = input.requirements.enumerated().map {
                RequirementInsert(route_id: inserted.id.uuidString, icon: $1.icon, title: $1.title, subtitle: $1.subtitle, tint: $1.tint, sort_order: $0)
            }
            try await supabase.from("route_requirements").insert(rows).execute()
        }

        if !input.pois.isEmpty {
            struct POIInsert: Encodable {
                let route_id: String, lat: Double, lng: Double, category: String, title: String, note: String?, sort_order: Int
            }
            let rows = input.pois.enumerated().map {
                POIInsert(route_id: inserted.id.uuidString, lat: $1.lat, lng: $1.lng, category: $1.category, title: $1.title, note: $1.note, sort_order: $0)
            }
            try await supabase.from("route_points_of_interest").insert(rows).execute()
        }

        // Re-fetch so the returned Route carries the segments/requirements/
        // POIs just inserted (the first response predates them).
        if !input.segments.isEmpty || !input.requirements.isEmpty || !input.pois.isEmpty {
            return try await fetchRouteDTO(id: inserted.id.uuidString).toRoute()
        }
        return inserted.toRoute()
    }

    /// Edits a published route's segments/requirements — RLS already allows
    /// this ("Owners manage their route's segments/requirements", `for all`,
    /// same policy publish's insert already relies on); this was purely a
    /// missing client-side screen, not a missing backend capability. A full
    /// replace (delete then re-insert) rather than diffing row-by-row —
    /// simple, and the whole set is always small (a handful of segments/
    /// requirements), same tradeoff the log-a-route builder UI already makes.
    func updateRouteExtras(routeId: String, segments: [NewSegment], requirements: [NewRequirement]) async throws -> Route {
        try await supabase.from("route_segments").delete().eq("route_id", value: routeId).execute()
        try await supabase.from("route_requirements").delete().eq("route_id", value: routeId).execute()

        if !segments.isEmpty {
            struct SegmentInsert: Encodable {
                let route_id: String, icon: String, name: String, distance_km: Double, tint: String, sort_order: Int
            }
            let rows = segments.enumerated().map {
                SegmentInsert(route_id: routeId, icon: $1.icon, name: $1.name, distance_km: $1.distanceKM, tint: $1.tint, sort_order: $0)
            }
            try await supabase.from("route_segments").insert(rows).execute()
        }

        if !requirements.isEmpty {
            struct RequirementInsert: Encodable {
                let route_id: String, icon: String, title: String, subtitle: String, tint: String, sort_order: Int
            }
            let rows = requirements.enumerated().map {
                RequirementInsert(route_id: routeId, icon: $1.icon, title: $1.title, subtitle: $1.subtitle, tint: $1.tint, sort_order: $0)
            }
            try await supabase.from("route_requirements").insert(rows).execute()
        }

        return try await fetchRouteDTO(id: routeId).toRoute()
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

    // MARK: - Moderation

    enum ReportTarget: String { case route, comment }

    /// Files a report — the DB auto-hides content once it collects reports
    /// from 3 distinct people (see the `content_reports` trigger). Silently
    /// no-ops on a duplicate report from the same person (unique constraint).
    func report(_ target: ReportTarget, id: String, reason: String) async throws {
        let userId = try await ensureSession()
        struct Insert: Encodable {
            let target_type: String
            let target_id: String
            let reporter_id: String
            let reason: String
        }
        try await supabase.from("content_reports")
            .insert(Insert(target_type: target.rawValue, target_id: id, reporter_id: userId.uuidString, reason: reason))
            .execute()
    }

    // MARK: - My profile (real data for the Profile tab — replaces the old hardcoded "Sana Kadyrova")

    struct MyProfile {
        let username: String
        let displayName: String
        let homeLocation: String?
        let kmLogged: Double
        let routesCompleted: Int
        let badgeCount: Int
        let avatarUrl: String?
        /// True for a device that's only ever been anonymously
        /// auto-signed-in (liked/saved something pre-signup) — Profile
        /// shows a "sign in" prompt instead of pretending this is a real
        /// account with a name.
        let isAnonymous: Bool
    }

    private struct MyProfileRow: Decodable {
        let username: String
        let display_name: String
        let home_location: String?
        let km_logged: Double
        let routes_completed: Int
        let avatar_url: String?
    }

    func fetchMyProfile() async throws -> MyProfile {
        let userId = try await ensureSession()
        let isAnon = (try? await supabase.auth.session)?.user.isAnonymous ?? true
        let row: MyProfileRow = try await supabase
            .from("profiles")
            .select("username, display_name, home_location, km_logged, routes_completed, avatar_url")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        struct BadgeRow: Decodable { let badge_id: UUID }
        let badgeRows: [BadgeRow] = (try? await supabase
            .from("user_badges")
            .select("badge_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value) ?? []
        return MyProfile(
            username: row.username, displayName: row.display_name, homeLocation: row.home_location,
            kmLogged: row.km_logged, routesCompleted: row.routes_completed, badgeCount: badgeRows.count,
            avatarUrl: row.avatar_url, isAnonymous: isAnon
        )
    }

    enum ProfileUpdateError: LocalizedError {
        case usernameTaken
        case other(String)
        var errorDescription: String? {
            switch self {
            case .usernameTaken: return "That username's taken — try another."
            case .other(let message): return message
            }
        }
    }

    /// Lets someone fix their own name/username/home after the fact — the
    /// signup form only asks for a display name once, and an account
    /// created before that field existed (or signed in with a generic
    /// auto-assigned name) had no way to correct it.
    func updateMyProfile(displayName: String, username: String, homeLocation: String) async throws {
        let userId = try await ensureSession()
        struct Update: Encodable {
            let display_name: String
            let username: String
            let home_location: String?
        }
        do {
            try await supabase.from("profiles")
                .update(Update(display_name: displayName, username: username, home_location: homeLocation.isEmpty ? nil : homeLocation))
                .eq("id", value: userId.uuidString)
                .execute()
        } catch {
            let message = error.localizedDescription
            if message.contains("duplicate key") || message.contains("profiles_username_key") {
                throw ProfileUpdateError.usernameTaken
            }
            throw ProfileUpdateError.other(message)
        }
    }

    struct MyBadge: Identifiable {
        let key: String
        let title: String
        let subtitle: String
        let icon: String
        let colorStart: String
        let colorEnd: String
        let earned: Bool
        var id: String { key }
    }

    /// The full badge catalog with each one flagged for whether *this*
    /// user actually earned it — so the grid shows real locked/unlocked
    /// state instead of every badge just looking earned.
    func fetchMyBadges() async throws -> [MyBadge] {
        let userId = try await ensureSession()
        struct BadgeRow: Decodable {
            let key: String, title: String, subtitle: String, icon: String
            let color_start: String, color_end: String
        }
        let all: [BadgeRow] = try await supabase.from("badges").select("*").execute().value
        struct EarnedRow: Decodable { let badge_id: UUID }
        let earnedIds: Set<UUID> = Set(((try? await supabase
            .from("user_badges")
            .select("badge_id")
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value) as [EarnedRow]?)?.map(\.badge_id) ?? [])
        struct BadgeIdRow: Decodable { let key: String, id: UUID }
        let idsByKey: [String: UUID] = Dictionary(uniqueKeysWithValues: (try? await supabase
            .from("badges").select("key, id").execute().value as [BadgeIdRow]?)?.map { ($0.key, $0.id) } ?? [])
        return all.map { row in
            let earned = idsByKey[row.key].map { earnedIds.contains($0) } ?? false
            return MyBadge(key: row.key, title: row.title, subtitle: row.subtitle, icon: row.icon,
                            colorStart: row.color_start, colorEnd: row.color_end, earned: earned)
        }
    }

    struct MyRoute: Identifiable {
        let id: String
        let title: String
        let meta: String
        let likes: Int
        let saves: Int
    }

    /// The current user's own published routes, for Profile's "My routes"
    /// tab — was 2 hardcoded rows before.
    func fetchMyRoutes() async throws -> [MyRoute] {
        let userId = try await ensureSession()
        struct CountWrap: Decodable { let count: Int }
        struct Row: Decodable {
            let id: UUID, title: String, place: String, distance_km: Double
            let transport_label: String, status: String
            let likes: [CountWrap], saves: [CountWrap]
        }
        let rows: [Row] = try await supabase
            .from("routes")
            .select("id, title, place, distance_km, transport_label, status, likes:route_likes(count), saves:route_saves(count)")
            .eq("author_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map {
            let meta = "\(String(format: "%.1f", $0.distance_km)) KM · \($0.transport_label) · \($0.status.uppercased())"
            return MyRoute(id: $0.id.uuidString, title: $0.title.replacingOccurrences(of: "\n", with: " "),
                            meta: meta, likes: $0.likes.first?.count ?? 0, saves: $0.saves.first?.count ?? 0)
        }
    }

    // MARK: - NomadPoints (loyalty ledger — see backend/supabase/migrations/20260908000001_points.sql)

    struct PointsSummary {
        let balance: Int
        let bonusProUntil: Date?
    }

    struct PointsLedgerEntry: Identifiable, Decodable {
        let id: UUID
        let delta: Int
        let reason: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, delta, reason
            case createdAt = "created_at"
        }
    }

    struct PointReward: Identifiable, Decodable {
        let key: String
        let title: String
        let description: String
        let cost: Int
        let kind: String
        let sortOrder: Int
        var id: String { key }

        enum CodingKeys: String, CodingKey {
            case key, title, description, cost, kind
            case sortOrder = "sort_order"
        }
    }

    private struct ProfilePointsRow: Decodable {
        let points_balance: Int
        let bonus_pro_until: String?
    }

    /// Current balance + any bonus-Pro grant from redeeming points — both are
    /// server-computed only (see `award_points`/`redeem_reward`), never
    /// client-writable, so this always reflects the real, audited total.
    func fetchPointsSummary() async throws -> PointsSummary {
        let userId = try await ensureSession()
        let row: ProfilePointsRow = try await supabase
            .from("profiles")
            .select("points_balance, bonus_pro_until")
            .eq("id", value: userId.uuidString)
            .single()
            .execute()
            .value
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let until = row.bonus_pro_until.flatMap { formatter.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
        return PointsSummary(balance: row.points_balance, bonusProUntil: until)
    }

    /// Recent ledger history — every earn/redeem/reversal, newest first, for
    /// the Rewards screen's activity list.
    func fetchPointsLedger(limit: Int = 50) async throws -> [PointsLedgerEntry] {
        let userId = try await ensureSession()
        return try await supabase
            .from("points_ledger")
            .select("id, delta, reason, created_at")
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// The redeemable catalog — real data (`point_rewards`), not hardcoded,
    /// so adding/pricing new rewards is a DB change, not an app update.
    func fetchRewardCatalog() async throws -> [PointReward] {
        try await supabase
            .from("point_rewards")
            .select("key, title, description, cost, kind, sort_order")
            .order("sort_order")
            .execute()
            .value
    }

    enum RedeemError: LocalizedError {
        case insufficientPoints
        case alreadyOwned
        case other(String)
        var errorDescription: String? {
            switch self {
            case .insufficientPoints: return "Not enough points yet — keep logging routes."
            case .alreadyOwned: return "You already have this one."
            case .other(let message): return message
            }
        }
    }

    /// Spends points via the server-side `redeem_reward` function — the only
    /// place a redemption can happen, so a client can never grant itself
    /// points or Pro time directly.
    func redeemReward(key: String) async throws {
        _ = try await ensureSession()
        struct Params: Encodable { let p_reward_key: String }
        do {
            try await supabase.rpc("redeem_reward", params: Params(p_reward_key: key)).execute()
        } catch {
            let message = error.localizedDescription
            if message.contains("insufficient points") {
                throw RedeemError.insufficientPoints
            }
            if message.contains("already owned") {
                throw RedeemError.alreadyOwned
            }
            throw RedeemError.other(message)
        }
    }

    private func initials(from name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func relativeTime(from iso: String) -> String {
        let seconds = -(parseISODate(iso)?.timeIntervalSinceNow ?? 0)
        if seconds < 60 { return "JUST NOW" }
        if seconds < 3600 { return "\(Int(seconds / 60))M AGO" }
        if seconds < 86400 { return "\(Int(seconds / 3600))H AGO" }
        return "\(Int(seconds / 86400))D AGO"
    }

    private func parseISODate(_ iso: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    // MARK: - Notifications

    enum NotificationKind: String { case follow, comment, like, badge, newRoute }

    struct NotificationItem: Identifiable {
        let id: String
        let kind: NotificationKind
        let text: String
        let sub: String?
        let createdAt: Date
        let createdAgo: String
        let avatarInitials: String?
    }

    /// Assembles a real feed from four independent sources instead of one
    /// notifications table (there isn't one) — merged and sorted client-side
    /// by timestamp. Mirrors the same "reuse what already tracks this" move
    /// as the Profile Activity tab reusing the NomadPoints ledger.
    func fetchNotifications() async throws -> [NotificationItem] {
        let userId = try await ensureSession()
        let uid = userId.uuidString

        struct FollowRow: Decodable { let createdAt: String; let profiles: ProfileDTO
            enum CodingKeys: String, CodingKey { case profiles; case createdAt = "created_at" } }
        struct LikeRow: Decodable { let createdAt: String; let profiles: ProfileDTO; let routes: RouteTitleDTO
            enum CodingKeys: String, CodingKey { case profiles, routes; case createdAt = "created_at" } }
        struct CommentRow: Decodable { let createdAt: String; let profiles: ProfileDTO; let routes: RouteTitleDTO
            enum CodingKeys: String, CodingKey { case profiles, routes; case createdAt = "created_at" } }
        struct RouteTitleDTO: Decodable { let title: String }
        struct BadgeEarnedRow: Decodable { let earnedAt: String; let badges: BadgeDTO
            enum CodingKeys: String, CodingKey { case badges; case earnedAt = "earned_at" } }
        struct BadgeDTO: Decodable { let title: String }
        struct FollowingIdRow: Decodable { let followeeId: String
            enum CodingKeys: String, CodingKey { case followeeId = "followee_id" } }
        struct NewRouteRow: Decodable { let title: String; let createdAt: String; let profiles: ProfileDTO
            enum CodingKeys: String, CodingKey { case title, profiles; case createdAt = "created_at" } }

        async let follows: [FollowRow] = (try? await supabase
            .from("follows")
            .select("created_at, profiles!follows_follower_id_fkey(*)")
            .eq("followee_id", value: uid)
            .order("created_at", ascending: false)
            .limit(15)
            .execute().value) ?? []

        // !inner qualifies the embed so .eq("routes.author_id", …) actually
        // filters — a plain embed can't be filtered on in PostgREST.
        async let likes: [LikeRow] = (try? await supabase
            .from("route_likes")
            .select("created_at, profiles!route_likes_user_id_fkey(*), routes!inner(title)")
            .eq("routes.author_id", value: uid)
            .neq("user_id", value: uid)
            .order("created_at", ascending: false)
            .limit(15)
            .execute().value) ?? []

        async let comments: [CommentRow] = (try? await supabase
            .from("route_comments")
            .select("created_at, profiles!route_comments_author_id_fkey(*), routes!inner(title)")
            .eq("routes.author_id", value: uid)
            .neq("author_id", value: uid)
            .order("created_at", ascending: false)
            .limit(15)
            .execute().value) ?? []

        async let badgesEarned: [BadgeEarnedRow] = (try? await supabase
            .from("user_badges")
            .select("earned_at, badges(title)")
            .eq("user_id", value: uid)
            .order("earned_at", ascending: false)
            .limit(10)
            .execute().value) ?? []

        let followingIds: [FollowingIdRow] = (try? await supabase
            .from("follows")
            .select("followee_id")
            .eq("follower_id", value: uid)
            .execute().value) ?? []
        async let newRoutes: [NewRouteRow] = followingIds.isEmpty ? [] : ((try? await supabase
            .from("routes")
            .select("title, created_at, profiles!routes_author_id_fkey(*)")
            .in("author_id", values: followingIds.map(\.followeeId))
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .limit(10)
            .execute().value) ?? [])

        var items: [NotificationItem] = []

        for row in await follows {
            items.append(.init(
                id: "follow-\(row.profiles.id)-\(row.createdAt)", kind: .follow,
                text: "\(row.profiles.displayName) started following you", sub: nil,
                createdAt: parseISODate(row.createdAt) ?? .distantPast, createdAgo: relativeTime(from: row.createdAt),
                avatarInitials: initials(from: row.profiles.displayName)
            ))
        }
        for row in await likes {
            items.append(.init(
                id: "like-\(row.profiles.id)-\(row.createdAt)", kind: .like,
                text: "\(row.profiles.displayName) liked \(row.routes.title)", sub: nil,
                createdAt: parseISODate(row.createdAt) ?? .distantPast, createdAgo: relativeTime(from: row.createdAt),
                avatarInitials: nil
            ))
        }
        for row in await comments {
            items.append(.init(
                id: "comment-\(row.profiles.id)-\(row.createdAt)", kind: .comment,
                text: "\(row.profiles.displayName) commented on \(row.routes.title)", sub: nil,
                createdAt: parseISODate(row.createdAt) ?? .distantPast, createdAgo: relativeTime(from: row.createdAt),
                avatarInitials: nil
            ))
        }
        for row in await badgesEarned {
            items.append(.init(
                id: "badge-\(row.badges.title)-\(row.earnedAt)", kind: .badge,
                text: "You earned \(row.badges.title)", sub: nil,
                createdAt: parseISODate(row.earnedAt) ?? .distantPast, createdAgo: relativeTime(from: row.earnedAt),
                avatarInitials: nil
            ))
        }
        for row in await newRoutes {
            items.append(.init(
                id: "route-\(row.profiles.id)-\(row.createdAt)", kind: .newRoute,
                text: "\(row.profiles.displayName) published a new route", sub: row.title,
                createdAt: parseISODate(row.createdAt) ?? .distantPast, createdAgo: relativeTime(from: row.createdAt),
                avatarInitials: initials(from: row.profiles.displayName)
            ))
        }

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Moderation admin (review/reinstate auto-hidden content)

    /// Backs onto `security definer` RPCs (see
    /// `backend/supabase/migrations/20260914000001_moderation_admin_rpcs.sql`)
    /// that bypass RLS — there's no admin-role system in this app, so these
    /// are reachable by any signed-in user, same trust model the original
    /// moderation migration already accepted ("acceptable trade-off at this
    /// scale"). Fine while the founder is the only real user of this screen.
    struct HiddenRoute: Identifiable, Decodable {
        let id: UUID
        let title: String
        let place: String
        let authorId: UUID
        let authorName: String
        let reportCount: Int
        let reasons: [String]?
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, title, place, reasons
            case authorId = "author_id"
            case authorName = "author_name"
            case reportCount = "report_count"
            case createdAt = "created_at"
        }
    }

    struct HiddenComment: Identifiable, Decodable {
        let id: UUID
        let body: String
        let routeId: UUID
        let routeTitle: String
        let authorId: UUID
        let authorName: String
        let reportCount: Int
        let reasons: [String]?
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, body, reasons
            case routeId = "route_id"
            case routeTitle = "route_title"
            case authorId = "author_id"
            case authorName = "author_name"
            case reportCount = "report_count"
            case createdAt = "created_at"
        }
    }

    func fetchHiddenRoutes() async throws -> [HiddenRoute] {
        try await ensureSession()
        return try await supabase.rpc("admin_list_hidden_routes").execute().value
    }

    func fetchHiddenComments() async throws -> [HiddenComment] {
        try await ensureSession()
        return try await supabase.rpc("admin_list_hidden_comments").execute().value
    }

    func reinstateRoute(id: String) async throws {
        try await ensureSession()
        struct Params: Encodable { let target_id: String }
        try await supabase.rpc("admin_reinstate_route", params: Params(target_id: id)).execute()
    }

    func reinstateComment(id: String) async throws {
        try await ensureSession()
        struct Params: Encodable { let target_id: String }
        try await supabase.rpc("admin_reinstate_comment", params: Params(target_id: id)).execute()
    }
}

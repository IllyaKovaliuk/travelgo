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

    // No client-side `.eq("visibility", "public")` anywhere in this file
    // (removed from every query below, not just this one) — RLS
    // (`route_readable_by_viewer()`) is the real authority on which rows a
    // given viewer may read: public-published to everyone, followers-
    // published to real followers, everything to the owner. Filtering to
    // "public" again on the client used to silently hide followers-
    // visibility routes from the very followers RLS already allowed to see
    // them — the feed/profile/search just never asked Postgres for them.
    func fetchRoutes() async throws -> [Route] {
        let rows: [RouteDTO] = try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
            .eq("status", value: "published")
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
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
            .eq("author_id", value: authorId)
            .eq("status", value: "published")
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toRoute() }
    }

    /// "Following" feed tab — routes from authors the current session
    /// actually follows. Was previously just relabeled `fetchRoutes()` —
    /// same content under all 3 tabs regardless of which was selected.
    /// This is specifically where dropping the client's own visibility
    /// filter matters most: a followed author's followers-visibility
    /// routes belong here, and RLS (real follow-row check) is what decides
    /// that now, not a client filter that used to flatly exclude them.
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
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
            .eq("status", value: "published")
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
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
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
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
            .eq("status", value: "published")
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
            .select("downloaded_offline, routes!route_saves_route_id_fkey(*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count))")
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
        var photos: [NewPhoto] = []
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

    /// A photo taken mid-recording and geotagged (see `RecordTrackView`) —
    /// already uploaded to storage by the time it reaches here (`imageUrl`
    /// is real, not raw `Data`), so publishing only has to insert the
    /// `route_photos` row once the route itself finally has a real id.
    struct NewPhoto {
        var imageUrl: String
        var lat: Double?
        var lng: Double?
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
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
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

        if !input.photos.isEmpty {
            struct PhotoInsert: Encodable {
                let route_id: String, uploader_id: String, image_url: String, lat: Double?, lng: Double?
            }
            let rows = input.photos.map {
                PhotoInsert(route_id: inserted.id.uuidString, uploader_id: userId.uuidString, image_url: $0.imageUrl, lat: $0.lat, lng: $0.lng)
            }
            try await supabase.from("route_photos").insert(rows).execute()
        }

        // Re-fetch so the returned Route carries the segments/requirements/
        // POIs just inserted (the first response predates them). Photos
        // aren't part of the `Route`/`RouteDetailInfo` model at all (same
        // as comments — see `RoutePhotosSection`'s own fetch), so they
        // don't factor into whether a re-fetch is needed here.
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

    // MARK: - Photos on routes

    /// Same data pattern as `Comment` above (user + route + timestamp +
    /// content), not a separate system — see `route_photos`'s table
    /// comment. `lat`/`lng` are only real when this was taken mid-recording
    /// and geotagged to where in the track the person was; nil for an
    /// after-the-fact library upload.
    struct RoutePhoto: Identifiable {
        let id: String
        let imageUrl: String
        let caption: String?
        let lat: Double?
        let lng: Double?
        let uploaderId: String
        let uploaderName: String
        let uploaderInitials: String
        let createdAgo: String
    }

    private struct RoutePhotoDTO: Decodable {
        let id: UUID
        let imageUrl: String
        let caption: String?
        let lat: Double?
        let lng: Double?
        let createdAt: String
        let profiles: ProfileDTO
        enum CodingKeys: String, CodingKey {
            case id, caption, lat, lng, profiles
            case imageUrl = "image_url"
            case createdAt = "created_at"
        }
    }

    func fetchPhotos(routeId: String) async throws -> [RoutePhoto] {
        guard let routeUUID = UUID(uuidString: routeId) else { return [] }
        let rows: [RoutePhotoDTO] = try await supabase
            .from("route_photos")
            .select("id, image_url, caption, lat, lng, created_at, profiles!route_photos_uploader_id_fkey(*)")
            .eq("route_id", value: routeUUID.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map {
            RoutePhoto(
                id: $0.id.uuidString, imageUrl: $0.imageUrl, caption: $0.caption, lat: $0.lat, lng: $0.lng,
                uploaderId: $0.profiles.id.uuidString, uploaderName: $0.profiles.displayName,
                uploaderInitials: initials(from: $0.profiles.displayName), createdAgo: relativeTime(from: $0.createdAt)
            )
        }
    }

    /// Uploads a picked photo to the `route-photos` bucket and returns its
    /// public URL. Used both for an after-the-fact library add on Route
    /// Detail and, via `NewRouteDraft.photos`, for a photo added live
    /// mid-recording (uploaded immediately so the draft only ever carries a
    /// URL, same as `coverImageUrl` already does — never raw image `Data`
    /// sitting in memory for the rest of the flow).
    func uploadRoutePhotoFile(_ data: Data, routeId: String) async throws -> String {
        let userId = try await ensureSession()
        let path = "\(userId.uuidString)/\(routeId)/\(UUID().uuidString).jpg"
        try await supabase.storage.from("route-photos").upload(
            path, data: data, options: FileOptions(contentType: "image/jpeg")
        )
        return try supabase.storage.from("route-photos").getPublicURL(path: path).absoluteString
    }

    /// Inserts the `route_photos` row itself — split from the upload above
    /// so a mid-recording photo can upload right away (real route id not
    /// known yet) while the DB row only gets created once the route
    /// actually exists (see `publishRoute`'s `photos` batch insert, same
    /// deferred pattern POIs already use).
    func addPhoto(routeId: String, imageUrl: String, lat: Double?, lng: Double?, caption: String?) async throws {
        let userId = try await ensureSession()
        guard let routeUUID = UUID(uuidString: routeId) else { return }
        struct Insert: Encodable {
            let route_id: String
            let uploader_id: String
            let image_url: String
            let lat: Double?
            let lng: Double?
            let caption: String?
        }
        try await supabase.from("route_photos")
            .insert(Insert(route_id: routeUUID.uuidString, uploader_id: userId.uuidString, image_url: imageUrl, lat: lat, lng: lng, caption: caption))
            .execute()
    }

    func deletePhoto(id: String) async throws {
        try await ensureSession()
        try await supabase.from("route_photos").delete().eq("id", value: id).execute()
    }

    // MARK: - Visits journal (passive detection, separate from LogRoute)

    /// Entirely private — unlike routes/comments/photos, nobody but the
    /// owner ever reads these (see `visits`' single RLS policy). `status`
    /// is the honesty gate from the spec: `pending` visits are real
    /// detections nobody has looked at yet and never feed any stat;
    /// `kept` is the only status `ProfileView.countriesVisited` counts;
    /// `dismissed` just means "reviewed and discarded," kept around rather
    /// than deleted so `VisitsMonitor` doesn't re-surface the same spot
    /// right after someone dismissed it.
    struct Visit: Identifiable, Decodable {
        let id: UUID
        let lat: Double
        let lng: Double
        let placeName: String?
        let arrivalAt: String
        let departureAt: String?
        let status: String
        let linkedRouteId: UUID?
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, lat, lng, status
            case placeName = "place_name"
            case arrivalAt = "arrival_at"
            case departureAt = "departure_at"
            case linkedRouteId = "linked_route_id"
            case createdAt = "created_at"
        }
    }

    func fetchVisits() async throws -> [Visit] {
        let userId = try await ensureSession()
        return try await supabase
            .from("visits")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("arrival_at", ascending: false)
            .execute()
            .value
    }

    /// Only kept visits — what `ProfileView.countriesVisited` unions with
    /// `myRoutes` to compute the real stat. A dedicated, narrow query
    /// rather than reusing `fetchVisits()` and filtering client-side, so
    /// the profile stats header doesn't pull every pending/dismissed row
    /// (which can genuinely add up — Visits monitoring runs constantly in
    /// the background) just to throw most of it away.
    func fetchKeptVisitPlaces() async throws -> [String] {
        let userId = try await ensureSession()
        struct Row: Decodable { let placeName: String?; enum CodingKeys: String, CodingKey { case placeName = "place_name" } }
        let rows: [Row] = try await supabase
            .from("visits")
            .select("place_name")
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "kept")
            .execute()
            .value
        return rows.compactMap(\.placeName)
    }

    /// `VisitsMonitor` calls this for a departure-only `CLVisit` callback,
    /// to find the still-open row from the matching arrival to update in
    /// place instead of inserting a duplicate. A plain bounding-box match
    /// (no PostGIS in this schema) — generous enough for CLVisit's own
    /// coordinate jitter between its arrival and departure reports for
    /// what is, physically, the same stay.
    func findOpenVisit(nearLat lat: Double, lng: Double, degreeTolerance: Double = 0.01) async throws -> Visit? {
        let userId = try await ensureSession()
        let rows: [Visit] = try await supabase
            .from("visits")
            .select()
            .eq("user_id", value: userId.uuidString)
            .eq("status", value: "pending")
            .is("departure_at", value: nil)
            .gte("lat", value: lat - degreeTolerance)
            .lte("lat", value: lat + degreeTolerance)
            .gte("lng", value: lng - degreeTolerance)
            .lte("lng", value: lng + degreeTolerance)
            .order("arrival_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    @discardableResult
    func insertPendingVisit(lat: Double, lng: Double, placeName: String?, arrivalAt: Date, departureAt: Date?) async throws -> Visit {
        let userId = try await ensureSession()
        struct Insert: Encodable {
            let user_id: String
            let lat: Double
            let lng: Double
            let place_name: String?
            let arrival_at: String
            let departure_at: String?
        }
        let iso = ISO8601DateFormatter()
        return try await supabase.from("visits")
            .insert(Insert(
                user_id: userId.uuidString, lat: lat, lng: lng, place_name: placeName,
                arrival_at: iso.string(from: arrivalAt), departure_at: departureAt.map(iso.string(from:))
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func updateVisitDeparture(id: String, departureAt: Date) async throws {
        try await ensureSession()
        struct Update: Encodable { let departure_at: String }
        try await supabase.from("visits")
            .update(Update(departure_at: ISO8601DateFormatter().string(from: departureAt)))
            .eq("id", value: id)
            .execute()
    }

    /// `status` is `"kept"` or `"dismissed"` — the only user-driven
    /// transition out of `"pending"`. Nothing else in this app writes
    /// `status` back to `"pending"`.
    func setVisitStatus(id: String, status: String) async throws {
        try await ensureSession()
        struct Update: Encodable { let status: String }
        try await supabase.from("visits").update(Update(status: status)).eq("id", value: id).execute()
    }

    func attachRouteToVisit(id: String, routeId: String) async throws {
        try await ensureSession()
        struct Update: Encodable { let linked_route_id: String }
        try await supabase.from("visits").update(Update(linked_route_id: routeId)).eq("id", value: id).execute()
    }

    func deleteVisit(id: String) async throws {
        try await ensureSession()
        try await supabase.from("visits").delete().eq("id", value: id).execute()
    }

    // MARK: - Emergency contacts

    /// Real, private, owner-only (see `emergency_contacts`'s single RLS
    /// policy) — was a dead Settings row before this with nothing behind
    /// it, and `SOSView`'s own "contacts row" showed a hardcoded fake
    /// "Giorgi K." name. At least one of `phone`/`email` is required (a
    /// real DB constraint, not just a client-side check) — a contact with
    /// neither is unreachable, so there'd be no point saving it.
    struct EmergencyContact: Identifiable, Decodable {
        let id: UUID
        let name: String
        let phone: String?
        let email: String?
    }

    func fetchEmergencyContacts() async throws -> [EmergencyContact] {
        let userId = try await ensureSession()
        return try await supabase
            .from("emergency_contacts")
            .select("id, name, phone, email")
            .eq("user_id", value: userId.uuidString)
            .order("created_at")
            .execute()
            .value
    }

    func addEmergencyContact(name: String, phone: String?, email: String?) async throws {
        let userId = try await ensureSession()
        struct Insert: Encodable {
            let user_id: String
            let name: String
            let phone: String?
            let email: String?
        }
        try await supabase.from("emergency_contacts")
            .insert(Insert(user_id: userId.uuidString, name: name, phone: phone, email: email))
            .execute()
    }

    func deleteEmergencyContact(id: String) async throws {
        try await ensureSession()
        try await supabase.from("emergency_contacts").delete().eq("id", value: id).execute()
    }

    // MARK: - Analytics

    /// Real, first-party event logging — there was no analytics of any
    /// kind before this (nothing to make "not mock", there was just
    /// nothing). Fire-and-forget on purpose: a logging call should never
    /// be able to fail a real user action, so failures are swallowed
    /// silently rather than surfaced or retried.
    /// `nonisolated` on purpose — this is meant to be dropped into any
    /// call site (view code, `SubscriptionManager`, wherever) without
    /// needing `await` or wrapping in a `Task`, matching "fire-and-forget,
    /// should never block or fail a real user action."
    nonisolated func logEvent(_ name: String, metadata: [String: String] = [:]) {
        Task {
            let userId = try? await ensureSession()
            struct Insert: Encodable {
                let user_id: String?
                let event_name: String
                let metadata: [String: String]
            }
            try? await supabase.from("analytics_events")
                .insert(Insert(user_id: userId?.uuidString, event_name: name, metadata: metadata))
                .execute()
        }
    }

    struct AnalyticsSummary: Decodable {
        let totalUsers: Int
        let totalRoutesPublished: Int
        let signups7d: Int
        let routesPublished7d: Int
        let dau: Int
        let wau: Int
        let sosTriggers7d: Int
        let topEvents7d: [TopEvent]

        struct TopEvent: Decodable, Identifiable {
            let eventName: String
            let count: Int
            var id: String { eventName }
            enum CodingKeys: String, CodingKey { case eventName = "event_name", count }
        }

        enum CodingKeys: String, CodingKey {
            case totalUsers = "total_users"
            case totalRoutesPublished = "total_routes_published"
            case signups7d = "signups_7d"
            case routesPublished7d = "routes_published_7d"
            case dau, wau
            case sosTriggers7d = "sos_triggers_7d"
            case topEvents7d = "top_events_7d"
        }
    }

    /// Real aggregate numbers, computed server-side by `admin_analytics_
    /// summary()` — which itself re-checks `is_admin` and throws if the
    /// caller isn't one, so this is safe to call even if a client-side
    /// admin check were ever bypassed.
    func fetchAnalyticsSummary() async throws -> AnalyticsSummary {
        try await ensureSession()
        return try await supabase.rpc("admin_analytics_summary").execute().value
    }

    // MARK: - Moderation

    enum ReportTarget: String { case route, comment, photo }

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
        /// `nil` is real now, not a decoding bug — `profiles.display_name`
        /// became nullable so `handle_new_user()` could stop faking a
        /// "New Nomad" identity for accounts without one yet (see the
        /// `require_real_author_name_trigger` migration). A brand-new
        /// social sign-in genuinely has no name until `AuthView` sets one
        /// right after auth succeeds.
        let displayName: String?
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
        /// Real server-side role check (`profiles.is_admin`), not a
        /// client-side guess — gates whether Settings even shows the
        /// Moderation/Analytics rows. The RPCs behind those screens check
        /// this too on the server, so hiding the row is real UX, not the
        /// actual security boundary.
        let isAdmin: Bool
        /// `profiles.is_super_admin` — the one role that can appoint/
        /// revoke other admins (`admin_set_admin_role`). Only the
        /// founder's real account has this.
        let isSuperAdmin: Bool
        /// A real, unique, server-generated code (see
        /// `20260929000004_referrals.sql`) — every account has had one
        /// since that migration, existing accounts included (backfilled).
        let referralCode: String
    }

    private struct MyProfileRow: Decodable {
        let username: String
        let display_name: String?
        let home_location: String?
        let km_logged: Double
        let routes_completed: Int
        let avatar_url: String?
        let is_admin: Bool
        let is_super_admin: Bool
        let referral_code: String
    }

    func fetchMyProfile() async throws -> MyProfile {
        let userId = try await ensureSession()
        let isAnon = (try? await supabase.auth.session)?.user.isAnonymous ?? true
        let row: MyProfileRow = try await supabase
            .from("profiles")
            .select("username, display_name, home_location, km_logged, routes_completed, avatar_url, is_admin, is_super_admin, referral_code")
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
            avatarUrl: row.avatar_url, isAnonymous: isAnon, isAdmin: row.is_admin, isSuperAdmin: row.is_super_admin,
            referralCode: row.referral_code
        )
    }

    /// How many real signups have redeemed this session's own referral
    /// code — backs the real count on `ProfileView`'s invite card (used to
    /// be static text with no way to know if it ever worked).
    func fetchReferralCount() async throws -> Int {
        let userId = try await ensureSession()
        struct Row: Decodable { let id: UUID }
        let rows: [Row] = try await supabase
            .from("referrals")
            .select("id")
            .eq("referrer_id", value: userId.uuidString)
            .execute()
            .value
        return rows.count
    }

    enum RedeemReferralError: LocalizedError {
        case invalidCode
        case alreadyRedeemed
        case selfReferral
        case other(String)
        var errorDescription: String? {
            switch self {
            case .invalidCode: return "That code doesn't match anyone — check it and try again."
            case .alreadyRedeemed: return "You've already used a referral code."
            case .selfReferral: return "That's your own code."
            case .other(let message): return message
            }
        }
    }

    /// Called once, right after a fresh sign-up, only if the person
    /// actually entered a code — never required. See
    /// `redeem_referral_code` for the real points payout on both sides.
    func redeemReferralCode(_ code: String) async throws {
        try await ensureSession()
        struct Params: Encodable { let p_code: String }
        do {
            try await supabase.rpc("redeem_referral_code", params: Params(p_code: code)).execute()
        } catch {
            let message = error.localizedDescription
            if message.contains("invalid code") { throw RedeemReferralError.invalidCode }
            if message.contains("already redeemed") { throw RedeemReferralError.alreadyRedeemed }
            if message.contains("cannot refer yourself") { throw RedeemReferralError.selfReferral }
            throw RedeemReferralError.other(message)
        }
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

    /// Display-name-only partial update — used right after a real Apple/
    /// Google sign-in when the provider actually handed over a name
    /// (Apple's `fullName`, only ever shared on someone's very first
    /// authorization; Google's `full_name`/`name` claim). Deliberately not
    /// `updateMyProfile` — that one replaces `username` too, and would risk
    /// clobbering the auto-generated one with nothing to put back since a
    /// social sign-in never collects a username at all.
    func updateDisplayName(_ displayName: String) async throws {
        let userId = try await ensureSession()
        struct Update: Encodable { let display_name: String }
        try await supabase.from("profiles")
            .update(Update(display_name: displayName))
            .eq("id", value: userId.uuidString)
            .execute()
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

    /// The current session's own routes — *every* status (draft/hidden
    /// included), unlike `fetchUserRoutes` (which only shows what's
    /// actually public, right for viewing someone *else's* profile). Full
    /// `Route` shape rather than the old lightweight `MyRoute` — Profile's
    /// stats header (km/countries/streak/verified) needs the real
    /// `trackPoints`/`createdAt`/`place` on every one of your own routes,
    /// not just a title and two counts.
    func fetchMyRoutesFull() async throws -> [Route] {
        let userId = try await ensureSession()
        let rows: [RouteDTO] = try await supabase
            .from("routes")
            .select("*, profiles!routes_author_id_fkey(*), route_segments(*), route_requirements(*), route_points_of_interest(*), likes:route_likes(count), comments:route_comments(count), saves:route_saves(count)")
            .eq("author_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
        return rows.map { $0.toRoute() }
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

    struct HiddenPhoto: Identifiable, Decodable {
        let id: UUID
        let imageUrl: String
        let caption: String?
        let routeId: UUID
        let routeTitle: String
        let uploaderId: UUID
        let uploaderName: String
        let reportCount: Int
        let reasons: [String]?
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, caption, reasons
            case imageUrl = "image_url"
            case routeId = "route_id"
            case routeTitle = "route_title"
            case uploaderId = "uploader_id"
            case uploaderName = "uploader_name"
            case reportCount = "report_count"
            case createdAt = "created_at"
        }
    }

    func fetchHiddenPhotos() async throws -> [HiddenPhoto] {
        try await ensureSession()
        return try await supabase.rpc("admin_list_hidden_photos").execute().value
    }

    func reinstatePhoto(id: String) async throws {
        try await ensureSession()
        struct Params: Encodable { let target_id: String }
        try await supabase.rpc("admin_reinstate_photo", params: Params(target_id: id)).execute()
    }

    // MARK: - Admin: direct hide/delete (not just reinstate-after-report)

    private struct TargetIDParams: Encodable { let target_id: String }

    func adminDeleteRoute(id: String) async throws {
        try await ensureSession()
        try await supabase.rpc("admin_delete_route", params: TargetIDParams(target_id: id)).execute()
    }

    func adminDeleteComment(id: String) async throws {
        try await ensureSession()
        try await supabase.rpc("admin_delete_comment", params: TargetIDParams(target_id: id)).execute()
    }

    func adminDeletePhoto(id: String) async throws {
        try await ensureSession()
        try await supabase.rpc("admin_delete_photo", params: TargetIDParams(target_id: id)).execute()
    }

    func adminHideRoute(id: String) async throws {
        try await ensureSession()
        try await supabase.rpc("admin_hide_route", params: TargetIDParams(target_id: id)).execute()
    }

    func adminHideComment(id: String) async throws {
        try await ensureSession()
        try await supabase.rpc("admin_hide_comment", params: TargetIDParams(target_id: id)).execute()
    }

    func adminHidePhoto(id: String) async throws {
        try await ensureSession()
        try await supabase.rpc("admin_hide_photo", params: TargetIDParams(target_id: id)).execute()
    }

    // MARK: - Super admin: user management

    struct AdminUser: Identifiable, Decodable {
        let id: UUID
        let username: String
        let displayName: String?
        let isAdmin: Bool
        let isSuperAdmin: Bool
        let isBanned: Bool
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, username
            case displayName = "display_name"
            case isAdmin = "is_admin"
            case isSuperAdmin = "is_super_admin"
            case isBanned = "is_banned"
            case createdAt = "created_at"
        }
    }

    /// Empty `query` returns the 50 most recent accounts — a real starting
    /// point for user management, not just a dead search box.
    func searchUsers(_ query: String) async throws -> [AdminUser] {
        try await ensureSession()
        struct Params: Encodable { let query: String }
        return try await supabase.rpc("admin_search_users", params: Params(query: query)).execute().value
    }

    /// Only a super admin can actually do this — `admin_set_admin_role`
    /// re-checks `is_super_admin` server-side and throws for anyone else.
    func setAdminRole(userId: String, isAdmin: Bool) async throws {
        try await ensureSession()
        struct Params: Encodable { let target_user_id: String; let make_admin: Bool }
        try await supabase.rpc("admin_set_admin_role", params: Params(target_user_id: userId, make_admin: isAdmin)).execute()
    }

    /// A real ban — blocks future sign-ins at the auth layer
    /// (`auth.users.banned_until`) and immediately blocks new
    /// routes/comments/photos (see the `is_banned` checks added to those
    /// tables' write policies). Any admin can do this, not just a super
    /// admin — banning a super admin is refused server-side.
    func setUserBanned(userId: String, banned: Bool) async throws {
        try await ensureSession()
        struct Params: Encodable { let target_user_id: String; let banned: Bool }
        try await supabase.rpc("admin_set_user_banned", params: Params(target_user_id: userId, banned: banned)).execute()
    }

    struct AdminUserPhoto: Identifiable, Decodable {
        let id: UUID
        let imageUrl: String
        let routeId: UUID
        let routeTitle: String
        let hidden: Bool
        let createdAt: String
        enum CodingKeys: String, CodingKey {
            case id, hidden
            case imageUrl = "image_url"
            case routeId = "route_id"
            case routeTitle = "route_title"
            case createdAt = "created_at"
        }
    }

    struct AdminUserRoute: Identifiable, Decodable {
        let id: UUID
        let title: String
        let status: String
        let createdAt: String
        enum CodingKeys: String, CodingKey {
            case id, title, status
            case createdAt = "created_at"
        }
    }

    /// Real per-user content browsing — the actual "block/delete a
    /// specific person's photos" workflow, not limited to whatever
    /// already collected 3 reports.
    func fetchUserPhotos(userId: String) async throws -> [AdminUserPhoto] {
        try await ensureSession()
        struct Params: Encodable { let target_user_id: String }
        return try await supabase.rpc("admin_list_user_photos", params: Params(target_user_id: userId)).execute().value
    }

    func fetchUserRoutesForAdmin(userId: String) async throws -> [AdminUserRoute] {
        try await ensureSession()
        struct Params: Encodable { let target_user_id: String }
        return try await supabase.rpc("admin_list_user_routes", params: Params(target_user_id: userId)).execute().value
    }
}

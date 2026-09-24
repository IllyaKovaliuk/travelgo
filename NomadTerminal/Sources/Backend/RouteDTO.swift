import Foundation
import SwiftUI
import CoreLocation

/// Wire-format rows straight off Postgres — decoded, then mapped into the
/// existing `Route` / `RouteDetailInfo` / `Author` view models so nothing
/// downstream (SwiftUI views) needs to change.
struct ProfileDTO: Codable {
    let id: UUID
    let username: String
    let displayName: String
    let homeLocation: String?
    let kmLogged: Double
    let routesCompleted: Int
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case homeLocation = "home_location"
        case kmLogged = "km_logged"
        case routesCompleted = "routes_completed"
        case avatarUrl = "avatar_url"
    }
}

struct SegmentDTO: Codable {
    let icon: String
    let name: String
    let distanceKm: Double
    let tint: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case icon, name, tint
        case distanceKm = "distance_km"
        case sortOrder = "sort_order"
    }
}

struct RequirementDTO: Codable {
    let icon: String
    let title: String
    let subtitle: String?
    let tint: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case icon, title, subtitle, tint
        case sortOrder = "sort_order"
    }
}

struct POIDTO: Codable {
    let id: UUID
    let lat: Double
    let lng: Double
    let category: String
    let title: String
    let note: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, lat, lng, category, title, note
        case sortOrder = "sort_order"
    }
}

struct RouteDTO: Codable {
    let id: UUID
    let title: String
    let place: String
    let coverImageUrl: String?
    let difficulty: String
    let transport: String
    let transportLabel: String
    let secondaryBadgeIcon: String?
    let secondaryBadgeLabel: String?
    let distanceKm: Double
    let coordinates: String?
    let season: String?
    let duration: String?
    let ascentM: Int?
    let highPointM: Int?
    let elevationProfile: [Double]
    let elevationPeakLabel: String?
    let quote: String?
    let quoteAuthor: String?
    let trackPoints: [TrackPoint]
    let profiles: ProfileDTO
    let routeSegments: [SegmentDTO]
    let routeRequirements: [RequirementDTO]
    let routePointsOfInterest: [POIDTO]
    /// Real aggregate counts via the `likes:route_likes(count)` embed —
    /// PostgREST returns a one-element array wrapper, not a bare int.
    let likes: [CountWrap]
    let comments: [CountWrap]

    struct CountWrap: Codable { let count: Int }

    enum CodingKeys: String, CodingKey {
        case id, title, place, difficulty, transport, coordinates, season, duration, quote, profiles, likes, comments
        case coverImageUrl = "cover_image_url"
        case transportLabel = "transport_label"
        case secondaryBadgeIcon = "secondary_badge_icon"
        case secondaryBadgeLabel = "secondary_badge_label"
        case distanceKm = "distance_km"
        case ascentM = "ascent_m"
        case highPointM = "high_point_m"
        case elevationProfile = "elevation_profile"
        case elevationPeakLabel = "elevation_peak_label"
        case quoteAuthor = "quote_author"
        case trackPoints = "track_points"
        case routeSegments = "route_segments"
        case routeRequirements = "route_requirements"
        case routePointsOfInterest = "route_points_of_interest"
    }
}

// MARK: - Mapping into the existing UI models

extension RouteDTO {
    func toRoute() -> Route {
        let sortedSegments = routeSegments.sorted { $0.sortOrder < $1.sortOrder }
        let sortedRequirements = routeRequirements.sorted { $0.sortOrder < $1.sortOrder }

        let detail = RouteDetailInfo(
            coordinates: coordinates ?? "",
            season: season ?? "",
            duration: duration ?? "",
            ascentM: ascentM ?? 0,
            highPointM: highPointM ?? 0,
            elevationProfile: elevationProfile.isEmpty ? [0, 0] : elevationProfile,
            elevationPeakLabel: elevationPeakLabel ?? "",
            quote: quote ?? "",
            quoteAuthor: quoteAuthor ?? "",
            requirements: sortedRequirements.map {
                .init(icon: $0.icon, title: $0.title, subtitle: $0.subtitle ?? "", tint: Color(hex: $0.tint))
            },
            segments: sortedSegments.map {
                .init(icon: $0.icon, name: $0.name, distanceKM: $0.distanceKm, tint: Color(hex: $0.tint))
            },
            trackPoints: trackPoints,
            pois: routePointsOfInterest.sorted { $0.sortOrder < $1.sortOrder }.map {
                .init(id: $0.id.uuidString, coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng), category: POICategory(rawValue: $0.category) ?? .other, title: $0.title, note: $0.note)
            }
        )

        let authorGradientPairs: [Color] = [NTColor.water, NTColor.pineRaised]

        return Route(
            id: id.uuidString,
            title: title,
            place: place,
            coverPlaceholder: title,
            coverImageUrl: coverImageUrl,
            difficulty: Route.Difficulty(rawValue: difficulty.uppercased()) ?? .moderate,
            transport: Transport(fromKey: transport),
            transportLabel: transportLabel,
            author: Author(
                id: profiles.id.uuidString,
                name: profiles.displayName,
                handle: "@" + profiles.username,
                routeCount: profiles.routesCompleted,
                initials: initials(from: profiles.displayName),
                gradient: authorGradientPairs,
                avatarUrl: profiles.avatarUrl
            ),
            stats: [
                .init(value: String(format: "%.1f", distanceKm), unit: "KM", label: "DISTANCE"),
                .init(value: "\(highPointM ?? 0)", unit: "M", label: "MAX ALT")
            ],
            distanceKM: distanceKm,
            secondaryBadge: secondaryBadgeIcon.map { (icon: $0, label: secondaryBadgeLabel ?? "") },
            detail: detail,
            likeCount: likes.first?.count ?? 0,
            commentCount: comments.first?.count ?? 0
        )
    }

    private func initials(from name: String) -> String {
        let parts = name.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}

private extension Color {
    /// Local helper — hex strings come from the DB as "#RRGGBB".
    init(hex string: String) {
        var s = string
        if s.hasPrefix("#") { s.removeFirst() }
        let value = UInt32(s, radix: 16) ?? 0x5FA777
        self = Color(hex: value)
    }
}

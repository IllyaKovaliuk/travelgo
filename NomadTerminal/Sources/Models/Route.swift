import SwiftUI

/// Core content model — a logged route. Mock data for now; shape mirrors
/// what the eventual backend record will look like closely enough that
/// swapping a real API response in later shouldn't touch the views.
struct Route: Identifiable {
    let id: String
    let title: String
    let place: String
    let coverPlaceholder: String
    /// A real uploaded photo, if the author added one — Supabase Storage
    /// public URL. `nil` falls back to the decorative placeholder.
    var coverImageUrl: String? = nil
    let difficulty: Difficulty
    let transport: Transport
    let transportLabel: String
    let author: Author
    let stats: [StatItem]
    let distanceKM: Double
    let secondaryBadge: (icon: String, label: String)?
    let detail: RouteDetailInfo
    /// Real aggregate counts (route_likes/route_comments/route_saves), not
    /// per-card local state — every route-fetching query embeds these now.
    var likeCount: Int = 0
    var commentCount: Int = 0
    var saveCount: Int = 0
    /// Real `routes.created_at`, when this came from a live fetch — `nil`
    /// for the 3 mock routes (predate real publish timestamps). Backs any
    /// time-windowed computation (an activity streak, a weekly/monthly
    /// leaderboard, a contribution heatmap) — never fabricated when the
    /// real row doesn't have one.
    var createdAt: Date? = nil

    enum Difficulty: String, CaseIterable {
        case easy = "EASY", moderate = "MODERATE", hard = "HARD"
        var color: Color {
            switch self {
            case .easy: return NTColor.sage
            case .moderate: return NTColor.gold
            case .hard: return NTColor.hard
            }
        }
        /// The raw enum key stored in Postgres (`easy`/`moderate`/`hard`).
        var dbKey: String { rawValue.lowercased() }
    }

    struct StatItem: Identifiable {
        let id = UUID()
        let value: String
        let unit: String
        let label: String
    }
}

/// `CaseIterable` deliberately — every call site that lists "all transport
/// types" (Search filters, the segment picker in log-a-route/edit) uses
/// `Transport.allCases` instead of a hand-typed array now, so adding a new
/// case here can't silently leave one of those pickers missing it again
/// (bike/paraglide were added after foot/water/climb/overland already had
/// several hardcoded `[.overland, .foot, .water, .climb]` arrays scattered
/// around — exactly the kind of thing that's easy to miss one of).
enum Transport: String, CaseIterable {
    case overland = "4×4", foot = "FOOT", water = "WATER", climb = "CLIMB", bike = "BIKE", paraglide = "PARAGLIDE"

    var color: Color {
        switch self {
        case .overland: return NTColor.accent
        case .foot: return NTColor.sage
        case .water: return NTColor.water
        case .climb: return NTColor.extreme
        case .bike: return NTColor.gold
        case .paraglide: return NTColor.extreme
        }
    }

    var icon: String {
        switch self {
        case .overland: return "car.side"
        case .foot: return "figure.hiking"
        case .water: return "water.waves"
        case .climb: return "mountain.2.fill"
        case .bike: return "bicycle"
        case .paraglide: return "figure.paragliding"
        }
    }

    /// The raw enum key stored in Postgres (`overland`/`foot`/`water`/`climb`/
    /// `bike`/`paraglide`), as opposed to `rawValue` which is the display
    /// label ("4×4"/"FOOT"/…).
    var dbKey: String {
        switch self {
        case .overland: return "overland"
        case .foot: return "foot"
        case .water: return "water"
        case .climb: return "climb"
        case .bike: return "bike"
        case .paraglide: return "paraglide"
        }
    }

    /// Matches `color` above — stored alongside a published segment so it
    /// renders with the same tint on Route Detail.
    var dbHex: String {
        switch self {
        case .overland: return "#E8743B"
        case .foot: return "#5FA777"
        case .water: return "#3E92CC"
        case .climb: return "#7A5FBF"
        case .bike: return "#E0A458"
        case .paraglide: return "#7A5FBF"
        }
    }

    init(fromKey key: String) {
        switch key {
        case "overland": self = .overland
        case "foot": self = .foot
        case "water": self = .water
        case "climb": self = .climb
        case "bike": self = .bike
        case "paraglide": self = .paraglide
        default: self = .foot
        }
    }

    /// Reverse of `icon` — `route_segments` has no `transport` column of its
    /// own (only `icon`/`tint`/`name`, set from a `Transport` case at write
    /// time — see `EditRouteExtrasView`), so this recovers which transport a
    /// already-published segment used, for display logic that needs the
    /// real case (dash pattern, transition markers) rather than just the
    /// baked icon/color. Every `Segment.icon` is always one of these six
    /// exact SF Symbol names, so the match is exhaustive in practice.
    init?(fromIcon icon: String) {
        guard let match = Transport.allCases.first(where: { $0.icon == icon }) else { return nil }
        self = match
    }
}

struct Author: Identifiable {
    let id: String
    let name: String
    let handle: String
    let routeCount: Int
    let initials: String
    let gradient: [Color]
    var avatarUrl: String? = nil
}

extension Route {
    static let mock: [Route] = [
        Route(
            id: "zagar-pass",
            title: "Zagar Pass\nat first light",
            place: "SVANETI, GEORGIA",
            coverPlaceholder: "Cover — misty ridge track, Land Cruiser, muted grade",
            coverImageUrl: "https://smdnbjvelqsgjoubognc.supabase.co/storage/v1/object/public/route-covers/seed/zagar-pass.jpg",
            difficulty: .hard,
            transport: .overland,
            transportLabel: "4×4",
            author: Author(id: "tm", name: "Tamar Meladze", handle: "@tamarondirt", routeCount: 214, initials: "TM", gradient: [NTColor.water, NTColor.pineRaised]),
            stats: [
                .init(value: "62.4", unit: "KM", label: "DISTANCE"),
                .init(value: "2410", unit: "M", label: "MAX ALT"),
                .init(value: "7", unit: "HRS", label: "MOVING"),
                .init(value: "S 3", unit: "/4", label: "SEGMENTS")
            ],
            distanceKM: 62.4,
            secondaryBadge: (icon: Transport.foot.icon, label: "FOOT 4KM"),
            detail: .zagarPass
        ),
        Route(
            id: "emerald-corridor",
            title: "The Emerald\nCorridor",
            place: "SOČA VALLEY, SLOVENIA",
            coverPlaceholder: "Cover — kayak on slate-grey river, low mist",
            coverImageUrl: "https://smdnbjvelqsgjoubognc.supabase.co/storage/v1/object/public/route-covers/seed/emerald-corridor.jpg",
            difficulty: .moderate,
            transport: .water,
            transportLabel: "KAYAK",
            author: Author(id: "lk", name: "Luka Kranjc", handle: "@lkpaddles", routeCount: 61, initials: "LK", gradient: [NTColor.extreme, NTColor.pineRaised]),
            stats: [
                .init(value: "18.9", unit: "KM", label: "RIVER"),
                .init(value: "III", unit: "GRADE", label: "RAPIDS"),
                .init(value: "11", unit: "°C", label: "WATER")
            ],
            distanceKM: 18.9,
            secondaryBadge: nil,
            detail: .emeraldCorridor
        ),
        Route(
            id: "naranjo-north-face",
            title: "Naranjo\nnorth face",
            place: "PICOS DE EUROPA, SPAIN",
            coverPlaceholder: "Cover — solo climber silhouette, granite, dusk",
            coverImageUrl: "https://smdnbjvelqsgjoubognc.supabase.co/storage/v1/object/public/route-covers/seed/naranjo-north-face.jpg",
            difficulty: .hard,
            transport: .climb,
            transportLabel: "CLIMB · 6b",
            author: Author(id: "ar", name: "Ainara Ruiz", handle: "@ainara.r", routeCount: 39, initials: "AR", gradient: [NTColor.accent, NTColor.pineRaised]),
            stats: [
                .init(value: "540", unit: "M", label: "WALL"),
                .init(value: "12", unit: "P", label: "PITCHES"),
                .init(value: "6b", unit: "+", label: "CRUX")
            ],
            distanceKM: 0.540,
            secondaryBadge: nil,
            detail: .naranjoNorthFace
        )
    ]
}

import SwiftUI

/// Core content model — a logged route. Mock data for now; shape mirrors
/// what the eventual backend record will look like closely enough that
/// swapping a real API response in later shouldn't touch the views.
struct Route: Identifiable {
    let id: String
    let title: String
    let place: String
    let coverPlaceholder: String
    let difficulty: Difficulty
    let transport: Transport
    let transportLabel: String
    let author: Author
    let stats: [StatItem]
    let distanceKM: Double
    let secondaryBadge: (icon: String, label: String)?
    let detail: RouteDetailInfo

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

enum Transport: String {
    case overland = "4×4", foot = "FOOT", water = "WATER", climb = "CLIMB"

    var color: Color {
        switch self {
        case .overland: return NTColor.accent
        case .foot: return NTColor.sage
        case .water: return NTColor.water
        case .climb: return NTColor.extreme
        }
    }

    var icon: String {
        switch self {
        case .overland: return "car.side"
        case .foot: return "figure.hiking"
        case .water: return "water.waves"
        case .climb: return "mountain.2.fill"
        }
    }

    /// The raw enum key stored in Postgres (`overland`/`foot`/`water`/`climb`),
    /// as opposed to `rawValue` which is the display label ("4×4"/"FOOT"/…).
    var dbKey: String {
        switch self {
        case .overland: return "overland"
        case .foot: return "foot"
        case .water: return "water"
        case .climb: return "climb"
        }
    }

    init(fromKey key: String) {
        switch key {
        case "overland": self = .overland
        case "foot": self = .foot
        case "water": self = .water
        case "climb": self = .climb
        default: self = .foot
        }
    }
}

struct Author: Identifiable {
    let id: String
    let name: String
    let handle: String
    let routeCount: Int
    let initials: String
    let gradient: [Color]
}

extension Route {
    static let mock: [Route] = [
        Route(
            id: "zagar-pass",
            title: "Zagar Pass\nat first light",
            place: "SVANETI, GEORGIA",
            coverPlaceholder: "Cover — misty ridge track, Land Cruiser, muted grade",
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

import SwiftUI

/// What kind of thing a dropped pin marks — "here's water", "here's a
/// homestay", "here's a viewpoint". Shared between the log-a-route flow
/// (dropping pins while recording) and Route Detail (showing them on the
/// real map) so both sides agree on the same icon/color per category.
enum POICategory: String, CaseIterable, Codable {
    case foot, vehicle, water, viewpoint, settlement, wildlife, camp, danger, other

    var icon: String {
        switch self {
        case .foot: return "figure.hiking"
        case .vehicle: return "car.side"
        case .water: return "drop.fill"
        case .viewpoint: return "binoculars.fill"
        case .settlement: return "house.fill"
        case .wildlife: return "pawprint.fill"
        case .camp: return "tent.fill"
        case .danger: return "exclamationmark.triangle.fill"
        case .other: return "mappin"
        }
    }

    var label: String {
        switch self {
        case .foot: return "On foot from here"
        case .vehicle: return "By vehicle from here"
        case .water: return "Water source"
        case .viewpoint: return "Viewpoint"
        case .settlement: return "Settlement / homestay"
        case .wildlife: return "Wildlife"
        case .camp: return "Campsite"
        case .danger: return "Hazard"
        case .other: return "Point of interest"
        }
    }

    var tint: Color {
        switch self {
        case .foot: return NTColor.sage
        case .vehicle: return NTColor.accent
        case .water: return NTColor.water
        case .viewpoint: return NTColor.gold
        case .settlement: return NTColor.accentDeep
        case .wildlife: return NTColor.extreme
        case .camp: return NTColor.sage
        case .danger: return NTColor.hard
        case .other: return NTColor.milk(0.7)
        }
    }

    /// Matches `tint` above — stored alongside a POI so it renders with the
    /// same color on read.
    var dbHex: String {
        switch self {
        case .foot: return "#5FA777"
        case .vehicle: return "#E8743B"
        case .water: return "#3E92CC"
        case .viewpoint: return "#E0A458"
        case .settlement: return "#C2551F"
        case .wildlife: return "#7A5FBF"
        case .camp: return "#5FA777"
        case .danger: return "#B33A2B"
        case .other: return "#FAF6EC"
        }
    }
}

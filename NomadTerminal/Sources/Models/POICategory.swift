import SwiftUI

/// What kind of thing a dropped pin marks — "here's water", "here's a
/// homestay", "here's a viewpoint". Shared between the log-a-route flow
/// (dropping pins while recording) and Route Detail (showing them on the
/// real map) so both sides agree on the same icon/color per category.
enum POICategory: String, CaseIterable, Codable {
    // Outdoor / overland
    case foot, vehicle, water, viewpoint, settlement, wildlife, camp, danger
    // Urban / any city, anywhere — logging a route isn't outdoor-only, so
    // pins shouldn't be either.
    case restaurant, cafe, hotel, landmark, shopping
    case other

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
        case .restaurant: return "fork.knife"
        case .cafe: return "cup.and.saucer.fill"
        case .hotel: return "bed.double.fill"
        case .landmark: return "building.columns.fill"
        case .shopping: return "bag.fill"
        case .other: return "mappin"
        }
    }

    /// Single source of truth for both `label` (display, translated) and
    /// `defaultTitle` (the real stored fallback in `DropPinSheet` when
    /// someone drops a pin without naming it) — kept as one switch rather
    /// than two, so the two can't quietly drift apart.
    private var rawLabel: String {
        switch self {
        case .foot: return "On foot from here"
        case .vehicle: return "By vehicle from here"
        case .water: return "Water source"
        case .viewpoint: return "Viewpoint"
        case .settlement: return "Settlement / homestay"
        case .wildlife: return "Wildlife"
        case .camp: return "Campsite"
        case .danger: return "Hazard"
        case .restaurant: return "Restaurant"
        case .cafe: return "Café"
        case .hotel: return "Hotel / lodging"
        case .landmark: return "Landmark"
        case .shopping: return "Shopping"
        case .other: return "Point of interest"
        }
    }

    var label: LocalizedStringKey { LocalizedStringKey(rawLabel) }

    /// The real fallback title stored in `route_points_of_interest.title`
    /// when someone drops a pin without typing a name — needs a plain
    /// `String` for storage, not a `LocalizedStringKey` (which has no
    /// public way to resolve back to one). Shows in whichever language the
    /// person naming the pin is using at that moment, same as any other
    /// default placeholder text would.
    var defaultTitle: String { String(localized: String.LocalizationValue(rawLabel)) }

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
        case .restaurant: return NTColor.accent
        case .cafe: return NTColor.gold
        case .hotel: return NTColor.accentDeep
        case .landmark: return NTColor.extreme
        case .shopping: return NTColor.water
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
        case .restaurant: return "#E8743B"
        case .cafe: return "#E0A458"
        case .hotel: return "#C2551F"
        case .landmark: return "#7A5FBF"
        case .shopping: return "#3E92CC"
        case .other: return "#FAF6EC"
        }
    }

    /// A convenient split for pickers that want to group outdoor vs. urban
    /// options instead of one flat list of 14.
    static var outdoorCases: [POICategory] { [.foot, .vehicle, .water, .viewpoint, .settlement, .wildlife, .camp, .danger] }
    static var urbanCases: [POICategory] { [.restaurant, .cafe, .hotel, .landmark, .shopping] }
}

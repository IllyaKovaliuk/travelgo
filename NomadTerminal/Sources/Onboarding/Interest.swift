import SwiftUI

/// The six picks on the "What kind of ground do you cover?" screen —
/// positions are lifted straight from the doc's absolute-position layout
/// (measured inside a 330×400pt canvas, i.e. 390pt width minus 30pt padding
/// each side).
enum Interest: String, CaseIterable, Identifiable {
    case overland, water, extreme, hiking, cycling, huts
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .overland: return "4×4 / Overland"
        case .water: return "Water / Kayak"
        case .extreme: return "Extreme"
        case .hiking: return "Hiking"
        case .cycling: return "Cycling"
        case .huts: return "Backcountry huts"
        }
    }

    var icon: String {
        switch self {
        case .overland: return "car.side"
        case .water: return "water.waves"
        case .extreme: return "mountain.2.fill"
        case .hiking: return "figure.hiking"
        case .cycling: return "bicycle"
        case .huts: return "tent.fill"
        }
    }

    var color: Color {
        switch self {
        case .overland: return NTColor.accent
        case .water: return NTColor.water
        case .extreme: return NTColor.extreme
        case .hiking: return NTColor.sage
        case .cycling, .huts: return NTColor.milk
        }
    }

    /// Icon/label ink color that sits on the solid fill.
    var onColor: Color {
        switch self {
        case .overland: return Color(hex: 0x231007)
        case .water: return Color(hex: 0x04202F)
        case .extreme: return Color(hex: 0xEFE9FF)
        case .hiking: return Color(hex: 0x0B2716)
        case .cycling, .huts: return NTColor.milk(0.8)
        }
    }

    /// Cycling / Huts render as dashed outline slots rather than solid fills.
    var isOutline: Bool { self == .cycling || self == .huts }

    /// (x, y, width, height) inside the 330×400 canvas.
    var frame: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        switch self {
        case .overland: return (0, 10, 154, 150)
        case .water: return (178, 0, 148, 142)
        case .extreme: return (22, 172, 142, 146)
        case .hiking: return (170, 158, 160, 154)
        case .cycling: return (6, 330, 126, 118)
        case .huts: return (174, 342, 134, 124)
        }
    }
}

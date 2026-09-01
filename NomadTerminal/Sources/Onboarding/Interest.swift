import SwiftUI

/// The six picks on the "What kind of ground do you cover?" screen —
/// positions are lifted straight from the doc's absolute-position layout
/// (measured inside a 330×400pt canvas, i.e. 390pt width minus 30pt padding
/// each side).
enum Interest: String, CaseIterable, Identifiable {
    case overland, water, extreme, hiking, cycling, huts
    var id: String { rawValue }

    var title: String {
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

    /// Exact asymmetric corner fractions, lifted 1:1 from the doc's CSS
    /// `border-radius` values for each pick (e.g. `58% 42% 48% 52% / 52% 56% 44% 48%`).
    var blobX: (topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
        switch self {
        case .overland: return (0.58, 0.42, 0.48, 0.52)
        case .water: return (0.46, 0.54, 0.60, 0.40)
        case .extreme: return (0.52, 0.48, 0.42, 0.58)
        case .hiking: return (0.60, 0.40, 0.52, 0.48)
        case .cycling: return (0.44, 0.56, 0.56, 0.44)
        case .huts: return (0.56, 0.44, 0.40, 0.60)
        }
    }
    var blobY: (topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat) {
        switch self {
        case .overland: return (0.52, 0.56, 0.44, 0.48)
        case .water: return (0.56, 0.44, 0.56, 0.44)
        case .extreme: return (0.46, 0.58, 0.42, 0.54)
        case .hiking: return (0.50, 0.46, 0.54, 0.50)
        case .cycling: return (0.58, 0.42, 0.58, 0.42)
        case .huts: return (0.48, 0.56, 0.44, 0.52)
        }
    }
}

import SwiftUI

/// Type tokens — SF Pro (system, `.default` design) for display headings,
/// Public Sans for body, IBM Plex Mono for every measured value (distance,
/// bearing, labels).
///
/// Headings used to run on Bricolage Grotesque, a rounded/editorial display
/// face that read as travel-blog rather than the tight, high-contrast
/// "terminal" look the app is moving to — replaced with the system face at
/// `.default` design (not `.rounded`) so headings render as a plain
/// geometric grotesque with no custom license to manage. `Font.system`
/// auto-selects the SF Pro Display optical size at heading sizes without
/// needing to name it explicitly the way a bundled `.custom` font would.
///
/// There used to be a `quote(_:)` case here too (Newsreader italic, for a
/// single "from the author" pull-quote in Route Detail) — dropped entirely,
/// serif italic doesn't belong in this aesthetic at all; that call site now
/// renders on `body` like any other paragraph text.
enum NTFont {
    enum HeadingWeight { case semibold, bold, extraBold
        var weight: Font.Weight {
            switch self {
            case .semibold: return .semibold
            case .bold: return .bold
            case .extraBold: return .heavy
            }
        }
    }
    enum BodyWeight { case light, regular, medium, semibold
        var psName: String {
            switch self {
            case .light: return "PublicSans-Light"
            case .regular: return "PublicSans-Regular"
            case .medium: return "PublicSans-Medium"
            case .semibold: return "PublicSans-SemiBold"
            }
        }
    }
    enum MonoWeight { case regular, medium, semibold
        var psName: String {
            switch self {
            case .regular: return "IBMPlexMono-Regular"
            case .medium: return "IBMPlexMono-Medium"
            case .semibold: return "IBMPlexMono-SemiBold"
            }
        }
    }

    static func heading(_ size: CGFloat, _ weight: HeadingWeight = .bold) -> Font {
        .system(size: size, weight: weight.weight, design: .default)
    }
    static func body(_ size: CGFloat, _ weight: BodyWeight = .regular) -> Font {
        .custom(weight.psName, size: size)
    }
    static func mono(_ size: CGFloat, _ weight: MonoWeight = .medium) -> Font {
        .custom(weight.psName, size: size)
    }
}

/// Small helper so `Text("…").ntTracking(.16)` reads like the doc's
/// letter-spacing tokens (em-based, applied as SwiftUI tracking in points).
extension View {
    func ntTracking(_ em: CGFloat, size: CGFloat) -> some View {
        self.tracking(em * size)
    }
}

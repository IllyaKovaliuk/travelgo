import SwiftUI

/// Type tokens — Bricolage Grotesque for display, Public Sans for body,
/// IBM Plex Mono for every measured value (distance, bearing, labels),
/// Newsreader italic for the rare editorial quote. Matches the doc 1:1.
enum NTFont {
    enum HeadingWeight { case semibold, bold, extraBold
        var psName: String {
            switch self {
            case .semibold: return "BricolageGrotesque-SemiBold"
            case .bold: return "BricolageGrotesque-Bold"
            case .extraBold: return "BricolageGrotesque-ExtraBold"
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
        .custom(weight.psName, size: size)
    }
    static func body(_ size: CGFloat, _ weight: BodyWeight = .regular) -> Font {
        .custom(weight.psName, size: size)
    }
    static func mono(_ size: CGFloat, _ weight: MonoWeight = .medium) -> Font {
        .custom(weight.psName, size: size)
    }
    static func quote(_ size: CGFloat) -> Font {
        .custom("Newsreader-LightItalic", size: size)
    }
}

/// Small helper so `Text("…").ntTracking(.16)` reads like the doc's
/// letter-spacing tokens (em-based, applied as SwiftUI tracking in points).
extension View {
    func ntTracking(_ em: CGFloat, size: CGFloat) -> some View {
        self.tracking(em * size)
    }
}

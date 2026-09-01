import SwiftUI
import Foundation

/// A closed shape with four independently asymmetric rounded corners —
/// the SwiftUI equivalent of the CSS 8-value `border-radius` trick every
/// blob in the design doc uses (e.g. `58% 42% 46% 54% / 52% 48% 55% 45%`).
/// Corner values are fractions of the bounding box's width/height (0...1).
struct OrganicBlob: Shape {
    var topLeftX: CGFloat
    var topRightX: CGFloat
    var bottomRightX: CGFloat
    var bottomLeftX: CGFloat
    var topLeftY: CGFloat
    var topRightY: CGFloat
    var bottomRightY: CGFloat
    var bottomLeftY: CGFloat

    /// Bezier control-point factor that approximates a quarter ellipse.
    private let kappa: CGFloat = 0.5523

    init(
        _ x: (topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat),
        _ y: (topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat)
    ) {
        topLeftX = x.topLeft; topRightX = x.topRight; bottomRightX = x.bottomRight; bottomLeftX = x.bottomLeft
        topLeftY = y.topLeft; topRightY = y.topRight; bottomRightY = y.bottomRight; bottomLeftY = y.bottomLeft
    }

    /// Convenience for a gently organic, near-circular blob with light asymmetry.
    static func soft(seed: CGFloat = 0) -> OrganicBlob {
        func j(_ base: CGFloat, _ o: CGFloat) -> CGFloat { base + o * sin(seed + base * 7) * 0.06 }
        return OrganicBlob(
            (topLeft: j(0.55, 1), topRight: j(0.45, -1), bottomRight: j(0.5, 1), bottomLeft: j(0.52, -1)),
            (topLeft: j(0.52, -1), topRight: j(0.5, 1), bottomRight: j(0.55, -1), bottomLeft: j(0.45, 1))
        )
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x, y: rect.minY + y) }

        let tlx = topLeftX * w, trx = topRightX * w, brx = bottomRightX * w, blx = bottomLeftX * w
        let tly = topLeftY * h, try_ = topRightY * h, bry = bottomRightY * h, bly = bottomLeftY * h

        var p = Path()
        p.move(to: pt(tlx, 0))
        p.addLine(to: pt(w - trx, 0))
        p.addCurve(to: pt(w, try_), control1: pt(w - trx * (1 - kappa), 0), control2: pt(w, try_ * (1 - kappa)))
        p.addLine(to: pt(w, h - bry))
        p.addCurve(to: pt(w - brx, h), control1: pt(w, h - bry * (1 - kappa)), control2: pt(w - brx * (1 - kappa), h))
        p.addLine(to: pt(blx, h))
        p.addCurve(to: pt(0, h - bly), control1: pt(blx * (1 - kappa), h), control2: pt(0, h - bly * (1 - kappa)))
        p.addLine(to: pt(0, tly))
        p.addCurve(to: pt(tlx, 0), control1: pt(0, tly * (1 - kappa)), control2: pt(tlx * (1 - kappa), 0))
        p.closeSubpath()
        return p
    }
}

/// Faint topographic contour lines — the wavy background texture behind
/// the onboarding hero art.
struct TopoLines: Shape {
    var lineCount: Int = 5
    var spacing: CGFloat = 30

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let baseY = rect.height * 0.35
        for i in 0..<lineCount {
            let y = baseY + CGFloat(i) * spacing
            var line = Path()
            line.move(to: CGPoint(x: -20, y: y))
            line.addCurve(
                to: CGPoint(x: rect.width * 0.49, y: y - 10),
                control1: CGPoint(x: rect.width * 0.15, y: y - 40),
                control2: CGPoint(x: rect.width * 0.33, y: y + 20)
            )
            line.addCurve(
                to: CGPoint(x: rect.width + 20, y: y - 20),
                control1: CGPoint(x: rect.width * 0.67, y: y - 60),
                control2: CGPoint(x: rect.width * 0.88, y: y + 10)
            )
            p.addPath(line)
        }
        return p
    }
}

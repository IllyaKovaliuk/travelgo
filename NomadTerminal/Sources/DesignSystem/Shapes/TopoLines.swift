import SwiftUI
import Foundation

/// Faint topographic contour lines — the wavy background texture behind
/// the onboarding hero art, and (at low opacity) the flat terrain-fallback
/// backgrounds in Route Detail/Record Track. Replaced `OrganicBlob` (a
/// closed shape with four independently asymmetric rounded corners, the
/// SwiftUI equivalent of the CSS 8-value `border-radius` trick the old
/// "organic travel journal" design doc used everywhere) across the app —
/// those soft decorative shapes were pure decoration with no data
/// function and didn't fit the tighter, high-contrast look the app moved
/// to; this straight-line pattern is the one texture element that survived
/// that pass.
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

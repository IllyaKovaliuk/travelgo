import SwiftUI

/// Stands in for real photography on a route that doesn't have a cover
/// photo yet. Layered radial glow + a faint topographic contour motif
/// (echoes the brand's compass/terrain language) reads as "this route is
/// waiting for a photo" rather than a flat, generic gradient block.
struct ImagePlaceholder: View {
    var caption: String? = nil
    var tint: Color = NTColor.pineRaised

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint, NTColor.pineShadow],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [tint.opacity(0.55), .clear],
                center: UnitPoint(x: 0.28, y: 0.24), startRadius: 0, endRadius: 220
            )
            contourLines

            VStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(NTColor.milk(0.55))
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                if let caption {
                    Text(caption)
                        .font(NTFont.mono(9, .medium))
                        .tracking(0.5)
                        .foregroundStyle(NTColor.milk(0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
        .clipped()
    }

    /// Three faint contour-map lines, echoing the elevation-line motif
    /// used elsewhere in the app rather than an arbitrary decoration.
    private var contourLines: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                ContourLine(seed: i)
                    .stroke(NTColor.milk(0.06), lineWidth: 1.5)
            }
        }
    }
}

private struct ContourLine: Shape {
    let seed: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let yBase = rect.height * (0.35 + Double(seed) * 0.22)
        let amplitude = rect.height * 0.09
        path.move(to: CGPoint(x: 0, y: yBase))
        let steps = 5
        for i in 1...steps {
            let x = rect.width * Double(i) / Double(steps)
            let phase = Double(seed) * 1.3
            let y = yBase + amplitude * sin(Double(i) * 1.1 + phase)
            let prevX = rect.width * Double(i - 1) / Double(steps)
            let midX = (prevX + x) / 2
            path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: midX, y: y))
        }
        return path
    }
}

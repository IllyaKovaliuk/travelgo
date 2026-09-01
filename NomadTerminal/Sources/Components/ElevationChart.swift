import SwiftUI

/// A filled line chart for the elevation profile — normalized 0...1
/// samples, drawn left to right, with a peak callout.
struct ElevationChart: View {
    let samples: [Double]
    let peakLabel: String
    var accent: Color = NTColor.accent

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let points = plotPoints(w: w, h: h)
            let peakIndex = samples.indices.max(by: { samples[$0] < samples[$1] }) ?? 0

            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle().fill(NTColor.milk(0.1)).frame(height: 1)
                        Spacer(minLength: 0)
                    }
                }

                fillPath(points, height: h).fill(
                    LinearGradient(colors: [accent.opacity(0.55), accent.opacity(0)], startPoint: .top, endPoint: .bottom)
                )
                linePath(points).stroke(accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                if points.indices.contains(peakIndex) {
                    let p = points[peakIndex]
                    Path { path in
                        path.move(to: CGPoint(x: p.x, y: p.y))
                        path.addLine(to: CGPoint(x: p.x, y: h))
                    }
                    .stroke(NTColor.milk(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                    Circle().fill(NTColor.milk).frame(width: 7, height: 7).position(p)

                    Text(peakLabel)
                        .font(NTFont.mono(9.5, .semibold))
                        .foregroundStyle(NTColor.ink)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(NTColor.milk, in: RoundedRectangle(cornerRadius: 8))
                        .position(x: min(max(p.x, 28), w - 28), y: max(p.y - 16, 10))
                }
            }
        }
        .frame(height: 112)
    }

    private func plotPoints(w: CGFloat, h: CGFloat) -> [CGPoint] {
        guard samples.count > 1 else { return [] }
        let stepX = w / CGFloat(samples.count - 1)
        return samples.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX, y: h - CGFloat(v) * h)
        }
    }

    private func linePath(_ points: [CGPoint]) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        return p
    }

    private func fillPath(_ points: [CGPoint], height: CGFloat) -> Path {
        var p = linePath(points)
        guard let last = points.last, let first = points.first else { return p }
        p.addLine(to: CGPoint(x: last.x, y: height))
        p.addLine(to: CGPoint(x: first.x, y: height))
        p.closeSubpath()
        return p
    }
}

import SwiftUI

/// A real draggable min/max range slider — two thumbs on one track. Used by
/// Search's Distance/Ascent filters, which used to be a static filled bar
/// with a hardcoded fraction and no gesture behind it at all.
struct DualRangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double
    let bounds: ClosedRange<Double>
    var tint: Color = NTColor.sage

    private let thumbSize: CGFloat = 22
    private let minGap: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - thumbSize
            let lowX = position(for: low, width: w)
            let highX = position(for: high, width: w)

            ZStack(alignment: .leading) {
                Capsule().fill(NTColor.milk(0.15)).frame(height: 6)
                Capsule().fill(tint).frame(width: max(0, highX - lowX), height: 6).offset(x: lowX)

                thumb.offset(x: lowX)
                    .gesture(DragGesture().onChanged { drag in
                        let v = value(forX: drag.location.x, width: w)
                        low = min(max(bounds.lowerBound, v), high - minGap)
                    })

                thumb.offset(x: highX)
                    .gesture(DragGesture().onChanged { drag in
                        let v = value(forX: drag.location.x, width: w)
                        high = max(min(bounds.upperBound, v), low + minGap)
                    })
            }
            .frame(height: thumbSize)
        }
        .frame(height: thumbSize)
    }

    private var thumb: some View {
        Circle()
            .fill(NTColor.milk)
            .overlay(Circle().stroke(tint, lineWidth: 3))
            .shadow(radius: 3)
            .frame(width: thumbSize, height: thumbSize)
    }

    private func position(for value: Double, width: CGFloat) -> CGFloat {
        let range = bounds.upperBound - bounds.lowerBound
        guard range > 0 else { return 0 }
        return width * CGFloat((value - bounds.lowerBound) / range)
    }

    private func value(forX x: CGFloat, width: CGFloat) -> Double {
        let range = bounds.upperBound - bounds.lowerBound
        let fraction = max(0, min(1, x / max(width, 1)))
        return bounds.lowerBound + Double(fraction) * range
    }
}

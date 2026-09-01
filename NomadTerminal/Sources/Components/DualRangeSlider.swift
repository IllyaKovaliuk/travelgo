import SwiftUI

/// A real draggable min/max range slider — two thumbs on one track. Used by
/// Search's Distance/Ascent filters, which used to be a static filled bar
/// with a hardcoded fraction and no gesture behind it at all.
///
/// Drag math uses `translation` (delta since the gesture began) rather than
/// `location` — `location` on a gesture attached to the thumb itself is in
/// the thumb's own tiny local coordinate space, not the track, so the
/// numbers barely moved: dragging felt like the slider didn't work at all.
/// `translation` doesn't have that problem since it's a delta, not an
/// absolute position.
struct DualRangeSlider: View {
    @Binding var low: Double
    @Binding var high: Double
    let bounds: ClosedRange<Double>
    var tint: Color = NTColor.sage

    @State private var dragStartLow: Double?
    @State private var dragStartHigh: Double?

    private let thumbSize: CGFloat = 28
    private let hitAreaSize: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - thumbSize
            let lowX = position(for: low, width: w)
            let highX = position(for: high, width: w)

            ZStack(alignment: .leading) {
                Capsule().fill(NTColor.milk(0.15)).frame(height: 6)
                Capsule().fill(tint).frame(width: max(0, highX - lowX), height: 6).offset(x: lowX)

                thumbHitArea
                    .offset(x: lowX - (hitAreaSize - thumbSize) / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                if dragStartLow == nil { dragStartLow = low }
                                let range = bounds.upperBound - bounds.lowerBound
                                let delta = Double(drag.translation.width / max(w, 1)) * range
                                let newValue = (dragStartLow ?? low) + delta
                                low = min(max(bounds.lowerBound, newValue), high)
                            }
                            .onEnded { _ in dragStartLow = nil }
                    )

                thumbHitArea
                    .offset(x: highX - (hitAreaSize - thumbSize) / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { drag in
                                if dragStartHigh == nil { dragStartHigh = high }
                                let range = bounds.upperBound - bounds.lowerBound
                                let delta = Double(drag.translation.width / max(w, 1)) * range
                                let newValue = (dragStartHigh ?? high) + delta
                                high = max(min(bounds.upperBound, newValue), low)
                            }
                            .onEnded { _ in dragStartHigh = nil }
                    )
            }
            .frame(height: thumbSize)
        }
        .frame(height: thumbSize)
    }

    /// A generously-sized invisible tap/drag target around the visible
    /// thumb — a bare 22pt circle is a needlessly small hit target on a
    /// real finger.
    private var thumbHitArea: some View {
        ZStack {
            Circle().fill(Color.clear).frame(width: hitAreaSize, height: hitAreaSize)
            thumb
        }
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
}

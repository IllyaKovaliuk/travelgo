import SwiftUI

/// The brand mark — a slow-spinning diamond compass needle inside a
/// breathing double ring. Matches the Welcome screen exactly
/// (26s linear spin, ~3.4s pulse).
struct CompassMark: View {
    var size: CGFloat = 96
    @State private var spin = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(NTColor.milk(0.35), lineWidth: 1.5)

            Circle()
                .stroke(NTColor.milk(0.14), lineWidth: 1)
                .padding(-size * 0.125)
                .scaleEffect(pulse ? 1.12 : 1)
                .opacity(pulse ? 0.7 : 0.25)
                .animation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true), value: pulse)

            NeedleHalf(mirrored: false)
                .fill(NTColor.accent)
            NeedleHalf(mirrored: true)
                .fill(NTColor.milk.opacity(0.9))
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(spin ? 360 : 0))
        .animation(.linear(duration: 26).repeatForever(autoreverses: false), value: spin)
        .onAppear {
            spin = true
            pulse = true
        }
    }
}

/// One triangular half of the compass needle diamond, drawn on a 96×96
/// canvas to match the doc's SVG coordinates — right half (accent) or
/// mirrored left half (milk).
private struct NeedleHalf: Shape {
    var mirrored: Bool

    func path(in rect: CGRect) -> Path {
        let s = rect.width / 96
        let sideX: CGFloat = mirrored ? 38 : 58
        var p = Path()
        p.move(to: CGPoint(x: 48 * s, y: 16 * s))
        p.addLine(to: CGPoint(x: sideX * s, y: 48 * s))
        p.addLine(to: CGPoint(x: 48 * s, y: 80 * s))
        p.closeSubpath()
        return p
    }
}

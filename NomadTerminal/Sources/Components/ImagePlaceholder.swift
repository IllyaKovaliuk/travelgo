import SwiftUI

/// Stands in for real photography on a route that doesn't have a cover
/// photo yet. A solid dark fill with a small centered route-line glyph —
/// deliberately quiet (no gradient wash, no decorative texture) so it
/// reads as "this route is waiting for a photo," a neutral placeholder,
/// not a second thing competing for attention next to the real photography
/// everywhere else in the app. The glyph picks up a hint of the route's
/// own category color (`tint`, typically `route.transport.color`) so it's
/// not perfectly anonymous, without turning into a bright color block.
struct ImagePlaceholder: View {
    var caption: String? = nil
    var tint: Color = NTColor.pineRaised

    var body: some View {
        ZStack {
            NTColor.pineShadow

            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(NTColor.milk(0.06))
                    RouteLineGlyph()
                        .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 22, height: 22)
                }
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(NTColor.milk(0.12), lineWidth: 1))

                if let caption {
                    Text(caption)
                        .font(NTFont.mono(9, .medium))
                        .tracking(0.5)
                        .foregroundStyle(NTColor.milk(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
            }
        }
        .clipped()
    }
}

/// A simple switchback line — three straight legs, the same shape language
/// as a route logged on a map, standing in for an actual track when there
/// isn't a photo to show instead.
private struct RouteLineGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX * 0.9, y: rect.minY + rect.height * 0.35))
        p.addLine(to: CGPoint(x: rect.midX * 1.1, y: rect.maxY * 0.55))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

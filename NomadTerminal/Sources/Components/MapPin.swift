import SwiftUI

/// Route-waypoint pin — a teardrop carrying the transport-mode icon
/// (car/foot/water/flag), distinct from `POIPin` below. See the Route
/// Detail map: pin *shape* encodes meaning, not a step number.
struct MapPin: View {
    var icon: String
    var tint: Color
    var iconColor: Color = NTColor.pine
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            TeardropShape()
                .fill(tint)
                .overlay(TeardropShape().stroke(NTColor.milk, lineWidth: 2))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 5)
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(iconColor)
                .offset(y: -size * 0.12)
        }
        .frame(width: size, height: size * 1.2)
    }
}

/// POI pin — a separate family from route waypoints (homestay, water
/// source, viewpoint, hazard). Circular so it never reads as "next stop".
struct POIPin: View {
    var icon: String
    var tint: Color = NTColor.gold
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(tint)
            Circle().stroke(NTColor.milk, lineWidth: 2)
            Image(systemName: icon)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(Color(hex: 0x2B1B05))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 8, y: 5)
    }
}

private struct TeardropShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let r = w / 2
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.minY + r), radius: r, startAngle: .degrees(-135), endAngle: .degrees(135), clockwise: false)
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

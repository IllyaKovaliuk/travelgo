import SwiftUI

/// 06 · Compass mode — live bearing/distance to the next waypoint.
struct CompassView: View {
    var waypointName: String = "Enguri ford crossing"
    var waypointIndex: Int = 3
    var waypointTotal: Int = 4
    var onClose: () -> Void

    @State private var bearing: Double = 46
    @State private var distanceKM: Double = 1.42
    @State private var showSOS = false
    private let timer = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            NTColor.pineDeep.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                dial
                Spacer(minLength: 0)
                footer
            }
        }
        .foregroundStyle(NTColor.milk)
        .fullScreenCover(isPresented: $showSOS) {
            SOSView(onClose: { showSOS = false })
        }
        .onReceive(timer) { _ in
            withAnimation(.easeInOut(duration: 0.9)) {
                bearing = 46 + sin(Date().timeIntervalSinceReferenceDate / 2.6) * 13
                distanceKM = max(0.08, distanceKM - 0.03)
                if distanceKM < 0.1 { distanceKM = 1.42 }
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 5) {
                Text("WAYPOINT \(waypointIndex) OF \(waypointTotal)")
                    .font(NTFont.mono(10, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.5))
                Text(waypointName)
                    .font(NTFont.body(14, .semibold))
            }

            Spacer()

            Button { showSOS = true } label: {
                Image(systemName: "sos")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xE58272))
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var dial: some View {
        ZStack {
            dialFace

            ZStack {
                needleGlyph
                Circle()
                    .fill(RadialGradient(colors: [NTColor.accent.opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 30))
                    .frame(width: 60, height: 60)
                    .offset(y: -142)
            }
            .rotationEffect(.degrees(bearing))

            readoutCard
        }
        .frame(width: 342, height: 342)
    }

    private var dialFace: some View {
        ZStack {
            Circle().stroke(NTColor.milk(0.1), lineWidth: 1)
            Circle().stroke(NTColor.milk(0.14), lineWidth: 1).padding(24)
            Circle().stroke(NTColor.milk(0.08), lineWidth: 1).padding(58)

            ForEach(0..<16, id: \.self) { i in
                Rectangle()
                    .fill(NTColor.milk(i % 4 == 0 ? 0.5 : 0.22))
                    .frame(width: i % 4 == 0 ? 1.6 : 1, height: i % 4 == 0 ? 12 : 7)
                    .offset(y: -163)
                    .rotationEffect(.degrees(Double(i) * 22.5))
            }

            Group {
                Text("N").offset(y: -152)
                Text("E").offset(x: 152).foregroundStyle(NTColor.milk(0.4))
                Text("S").offset(y: 152).foregroundStyle(NTColor.milk(0.4))
                Text("W").offset(x: -152).foregroundStyle(NTColor.milk(0.4))
            }
            .font(NTFont.mono(13, .semibold))
        }
    }

    private var needleGlyph: some View {
        VStack(spacing: 0) {
            CompassNeedleTip()
                .fill(NTColor.accent)
                .frame(width: 36, height: 46)
            Spacer()
        }
        .frame(height: 342)
    }

    private var readoutCard: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [NTColor.pineLine, NTColor.pineDeep], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 0, endRadius: 130))
                .overlay(Circle().stroke(NTColor.milk(0.12), lineWidth: 1))

            VStack(spacing: 12) {
                Text("TO WAYPOINT")
                    .font(NTFont.mono(10, .medium)).tracking(1.6).foregroundStyle(NTColor.milk(0.5))

                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(String(format: "%.2f", distanceKM))
                        .font(NTFont.mono(58, .semibold))
                        .contentTransition(.numericText())
                    Text("KM").font(NTFont.mono(16, .medium)).foregroundStyle(NTColor.milk(0.55))
                }

                Text("BEARING \(Int(bearing.rounded()))° NE")
                    .font(NTFont.mono(11, .semibold)).tracking(0.6)
                    .foregroundStyle(Color(hex: 0xF1A47C))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(NTColor.accent.opacity(0.16)))
                    .overlay(Capsule().stroke(NTColor.accent.opacity(0.4), lineWidth: 1))

                HStack(spacing: 16) {
                    readoutStat("1840", "ALT M")
                    Rectangle().fill(NTColor.milk(0.14)).frame(width: 1, height: 26)
                    readoutStat("4.2", "KM/H")
                    Rectangle().fill(NTColor.milk(0.14)).frame(width: 1, height: 26)
                    readoutStat("21m", "ETA")
                }
                .padding(.top, 4)
            }
        }
        .frame(width: 228, height: 228)
    }

    private func readoutStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value).font(NTFont.mono(14, .semibold))
            Text(label).font(NTFont.mono(8.5, .medium)).tracking(1.1).foregroundStyle(NTColor.milk(0.45))
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(NTColor.sage).frame(width: 7, height: 7)
                Text("GPS FIX 4 M · OFFLINE MAP LOADED")
                    .font(NTFont.mono(11, .medium)).tracking(0.4)
                    .foregroundStyle(NTColor.milk(0.7))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 13)
            .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))

            HStack(spacing: 10) {
                Button {} label: {
                    Text("Waypoints")
                        .font(NTFont.body(14, .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .overlay(Capsule().stroke(NTColor.milk(0.4), lineWidth: 1.4))
                }
                .buttonStyle(.plain).ntPressable()

                Button {} label: {
                    Text("Log a note")
                        .font(NTFont.body(14, .semibold))
                        .foregroundStyle(NTColor.pine)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain).ntPressable()
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }
}

private struct CompassNeedleTip: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: 0))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.7))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    CompassView(onClose: {})
}

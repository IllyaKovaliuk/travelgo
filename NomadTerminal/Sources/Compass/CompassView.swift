import SwiftUI
import CoreLocation

/// 06 · Compass mode — real device heading via CoreLocation. With a
/// `targetCoordinate` (a route's recorded track end point), also computes
/// real live bearing/distance/ETA to it; without one, it's an honest plain
/// compass instead of faking a waypoint that doesn't exist.
struct CompassView: View {
    var waypointName: String = "Next waypoint"
    var waypointIndex: Int = 1
    var waypointTotal: Int = 1
    var targetCoordinate: CLLocationCoordinate2D? = nil
    var onClose: () -> Void

    @State private var tracker = CompassTracker()
    @State private var showSOS = false
    /// Compass used to have its own bottom-tab entry for a "no route"
    /// plain compass; that tab is gone now, so this lets the same screen
    /// (opened from a route's Navigate button) drop its waypoint target
    /// and act as a plain compass without leaving the screen.
    @State private var showingPlain = false
    /// The needle's actual on-screen rotation — unwrapped (not clamped to
    /// 0..<360) so it always animates the short way around. Animating the
    /// raw 0..<360 `needleRotation` directly makes the needle spin almost
    /// all the way around every time it crosses the 0°/360° seam, which on
    /// a real device (where heading updates constantly) looked jerky.
    @State private var displayRotation: Double = 0

    /// nil while showing the plain compass, even if a real target exists.
    private var activeTarget: CLLocationCoordinate2D? { showingPlain ? nil : targetCoordinate }
    private var hasTarget: Bool { activeTarget != nil && distanceKM != nil }
    private var distanceKM: Double? { activeTarget.flatMap { tracker.distanceKM(to: $0) } }
    private var bearingToTarget: Double? { activeTarget.flatMap { tracker.bearing(to: $0) } }
    /// Needle rotation relative to the top of the screen: points at the
    /// target bearing (adjusted for which way the phone itself is facing)
    /// when there's a target, otherwise just points at true north.
    private var needleRotation: Double {
        let target = bearingToTarget ?? 0
        let r = target - tracker.headingDegrees
        return r < 0 ? r + 360 : r
    }
    private var etaMinutes: Int? {
        guard let distanceKM, tracker.speedKMH > 0.5 else { return nil }
        return Int((distanceKM / tracker.speedKMH * 60).rounded())
    }

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
            SOSView(
                onClose: { showSOS = false },
                onTriggered: { LiveActivityManager.shared.triggerSOS() },
                onCancelled: { LiveActivityManager.shared.cancelSOS() }
            )
        }
        .onAppear {
            tracker.start()
            displayRotation = needleRotation
        }
        .onDisappear { tracker.stop() }
        .onChange(of: needleRotation) { _, newValue in
            var delta = (newValue - displayRotation.truncatingRemainder(dividingBy: 360)).truncatingRemainder(dividingBy: 360)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            withAnimation(.easeInOut(duration: 0.25)) {
                displayRotation += delta
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
                Text(activeTarget != nil ? "WAYPOINT \(waypointIndex) OF \(waypointTotal)" : "NO ACTIVE ROUTE")
                    .font(NTFont.mono(10, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.5))
                Text(activeTarget != nil ? waypointName : "Plain compass")
                    .font(NTFont.body(14, .semibold))
            }

            Spacer()

            if targetCoordinate != nil {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation { showingPlain.toggle() }
                } label: {
                    Image(systemName: showingPlain ? "location.north.line.fill" : "location.slash")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(showingPlain ? NTColor.accent : NTColor.milk(0.8))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }

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
            .rotationEffect(.degrees(displayRotation))

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
                Text(hasTarget ? "TO WAYPOINT" : "HEADING")
                    .font(NTFont.mono(10, .medium)).tracking(1.6).foregroundStyle(NTColor.milk(0.5))

                if hasTarget, let distanceKM {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(String(format: "%.2f", distanceKM))
                            .font(NTFont.mono(58, .semibold))
                            .contentTransition(.numericText())
                        Text("KM").font(NTFont.mono(16, .medium)).foregroundStyle(NTColor.milk(0.55))
                    }
                } else {
                    Text(String(format: "%03d°", Int(tracker.headingDegrees.rounded())))
                        .font(NTFont.mono(52, .semibold))
                        .contentTransition(.numericText())
                }

                Text(hasTarget ? "BEARING \(Int((bearingToTarget ?? 0).rounded()))° \(compassPoint(bearingToTarget ?? 0))" : compassPoint(tracker.headingDegrees) + " · TRUE NORTH")
                    .font(NTFont.mono(11, .semibold)).tracking(0.6)
                    .foregroundStyle(Color(hex: 0xF1A47C))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(NTColor.accent.opacity(0.16)))
                    .overlay(Capsule().stroke(NTColor.accent.opacity(0.4), lineWidth: 1))

                HStack(spacing: 16) {
                    readoutStat(tracker.altitudeM > 0 ? "\(Int(tracker.altitudeM))" : "—", "ALT M")
                    Rectangle().fill(NTColor.milk(0.14)).frame(width: 1, height: 26)
                    readoutStat(String(format: "%.1f", tracker.speedKMH), "KM/H")
                    Rectangle().fill(NTColor.milk(0.14)).frame(width: 1, height: 26)
                    readoutStat(etaMinutes.map { "\($0)m" } ?? "—", "ETA")
                }
                .padding(.top, 4)
            }
        }
        .frame(width: 228, height: 228)
    }

    private var gpsStatusText: String {
        if tracker.authorizationDenied { return "LOCATION ACCESS DENIED — ENABLE IN SETTINGS" }
        if tracker.horizontalAccuracyM < 0 { return "ACQUIRING GPS FIX…" }
        return "GPS FIX \(Int(tracker.horizontalAccuracyM.rounded())) M"
    }

    private var gpsStatusColor: Color {
        if tracker.authorizationDenied { return Color(hex: 0xE58272) }
        if tracker.horizontalAccuracyM < 0 { return NTColor.gold }
        return NTColor.sage
    }

    private func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return points[max(0, min(7, index))]
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
                Circle().fill(gpsStatusColor).frame(width: 7, height: 7)
                Text(gpsStatusText)
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

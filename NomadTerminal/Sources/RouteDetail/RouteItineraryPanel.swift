import SwiftUI

/// Typical cruising speed per transport, used only to *estimate* a leg's
/// duration and cumulative elapsed time — this app has no real per-point
/// timestamps anywhere (`TrackPoint` is just lat/lng), so there is no real
/// recorded duration to fall back to. Every number this produces is
/// clearly labeled "Est." rather than presented as if it were measured.
enum LegPaceModel {
    static func kmh(for transport: Transport?) -> Double {
        switch transport {
        case .overland: return 22
        case .foot: return 4
        case .water: return 6
        case .bike: return 16
        // `distanceKM` on a climb leg is real trail-equivalent distance
        // covered (a segment like "scramble to col" mixes hiking and
        // technical sections, not pure vertical pitch length), so this
        // needs a slow-but-moving pace, not a near-static vertical-rock
        // speed — that produced nonsense (16km at 1.1km/h ≈ 14 real
        // hours for what the route's own metadata lists as one day of a
        // 2-day trip).
        case .climb: return 2.2
        // Paragliding is airborne, not on-foot — real cruising speed,
        // not a hiking pace.
        case .paraglide: return 28
        case nil: return 4
        }
    }

    static func duration(km: Double, transport: Transport?) -> TimeInterval {
        let speed = kmh(for: transport)
        guard speed > 0 else { return 0 }
        return (km / speed) * 3600
    }

    static func format(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int(seconds / 60), 1)
        let h = totalMinutes / 60, m = totalMinutes % 60
        if h == 0 { return "\(m)M" }
        return m == 0 ? "\(h)H" : "\(h)H \(m)M"
    }
}

/// The leg-by-leg breakdown below Route Detail's map — a real trip-planner
/// timeline, not just a flat list: each row is a real transport-type leg
/// with a distance, an estimated duration, and a cumulative elapsed-time
/// marker, connected by a color-matched stepper line so a glance at the
/// list and a glance at the map above read as the same route. Tapping a
/// row reframes the map to that one leg — the two pieces of UI are one
/// connected experience, not two disconnected ones.
///
/// Gated behind Pro (`isPro`) — free accounts see the route overview map
/// and a locked teaser of this panel, not the full breakdown; this is the
/// strongest single showcase of what Pro actually buys, so it's the
/// natural place to put the wall.
struct RouteItineraryPanel: View {
    let stretches: [MapSegmentStretch]
    let isPro: Bool
    var onSelect: (MapSegmentStretch) -> Void
    var onUnlockTapped: () -> Void

    private var totalDuration: TimeInterval {
        stretches.reduce(0) { $0 + LegPaceModel.duration(km: $1.distanceKM, transport: $1.transport) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Itinerary").font(NTFont.heading(18, .bold)).foregroundStyle(NTColor.milk)
                Spacer()
                Text("EST. \(LegPaceModel.format(totalDuration).uppercased())")
                    .font(NTFont.mono(10.5, .semibold))
                    .tracking(0.6)
                    .foregroundStyle(NTColor.milk(0.5))
            }
            .padding(.bottom, 14)

            if isPro {
                rows
            } else {
                ZStack {
                    rows.opacity(0.001) // keeps layout height identical to the unlocked state, never shown
                    lockedTeaser
                }
            }
        }
    }

    /// (stretch, elapsed time *before* this leg starts, this leg's own
    /// duration) — computed once as a plain value, not inside the view
    /// builder, so the running total is a real sequential sum rather than
    /// a mutable var captured by a `ForEach` closure (which SwiftUI may
    /// re-evaluate more than once per row while diffing).
    private var legTimings: [(stretch: MapSegmentStretch, startElapsed: TimeInterval, duration: TimeInterval)] {
        var elapsed: TimeInterval = 0
        return stretches.map { stretch in
            let duration = LegPaceModel.duration(km: stretch.distanceKM, transport: stretch.transport)
            let entry = (stretch: stretch, startElapsed: elapsed, duration: duration)
            elapsed += duration
            return entry
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(legTimings.enumerated()), id: \.element.stretch.id) { i, entry in
                row(entry.stretch, index: i, isLast: i == stretches.count - 1, startElapsed: entry.startElapsed, duration: entry.duration)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onSelect(entry.stretch)
                    }
            }
        }
    }

    private func row(_ stretch: MapSegmentStretch, index: Int, isLast: Bool, startElapsed: TimeInterval, duration: TimeInterval) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(stretch.tint)
                    Image(systemName: stretch.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                }
                .frame(width: 30, height: 30)
                if !isLast {
                    Rectangle().fill(stretch.tint.opacity(0.4)).frame(width: 2)
                        .frame(minHeight: 28)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(stretch.label)
                    .font(NTFont.body(14.5, .semibold))
                    .foregroundStyle(NTColor.milk)
                HStack(spacing: 6) {
                    Text(String(format: "%.1f KM", stretch.distanceKM))
                    Text("·")
                    Text("EST. \(LegPaceModel.format(duration))")
                }
                .font(NTFont.mono(10.5, .medium))
                .tracking(0.3)
                .foregroundStyle(NTColor.milk(0.55))
            }

            Spacer(minLength: 8)

            Text("+\(LegPaceModel.format(startElapsed))")
                .font(NTFont.mono(10, .semibold))
                .tracking(0.3)
                .foregroundStyle(NTColor.milk(0.4))
                .padding(.top, 6)
        }
        .padding(.bottom, isLast ? 0 : 16)
    }

    /// A real, honestly-blurred preview (the actual rows, just not
    /// legible) rather than a generic placeholder — makes it obvious
    /// there's a real breakdown underneath, not just a locked blank.
    private var lockedTeaser: some View {
        VStack(spacing: 14) {
            rows
                .allowsHitTesting(false)
                .blur(radius: 6)
                .mask(LinearGradient(colors: [.black, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom))

            Button(action: onUnlockTapped) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                    Text("Unlock the full leg-by-leg breakdown with Pro")
                        .font(NTFont.body(13, .semibold))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(Color(hex: 0x231007))
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(NTColor.accent, in: Capsule())
                .shadow(color: NTColor.accent.opacity(0.4), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .ntPressable(haptic: nil)
        }
    }
}

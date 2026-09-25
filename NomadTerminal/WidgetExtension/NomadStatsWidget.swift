import WidgetKit
import SwiftUI

/// Home Screen (small/medium) + Lock Screen (accessory circular/rectangular)
/// widgets, all one `WidgetSnapshot`-driven kind — real streak/km/countries/
/// heatmap, the exact same numbers `ProfileView` computes and displays,
/// just handed over via the shared App Group container (see
/// `Sources/Shared/WidgetSnapshot.swift`) since this process has no DB
/// session of its own.
///
/// Same font tradeoff `NomadTripLiveActivity` already made and documented:
/// system `.monospaced` design instead of the app's real IBM Plex Mono
/// (which isn't duplicated into this extension's bundle) — staying
/// consistent with that existing decision rather than reintroducing the
/// bundling question a second time.
struct NomadStatsWidget: Widget {
    let kind = "NomadStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StatsTimelineProvider()) { entry in
            StatsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Nomad Stats")
        .description("Your streak, km logged and recent activity.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct StatsEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct StatsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatsEntry {
        StatsEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatsEntry) -> Void) {
        completion(StatsEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    /// One entry, refreshed daily. The app itself pushes a fresh snapshot
    /// and calls `WidgetCenter.reloadAllTimelines()` every time `ProfileView`
    /// loads (real session-based cadence, not a timer) — this daily policy
    /// is just the floor, so a streak/heatmap doesn't sit frozen for a week
    /// straight if the person stops opening the app.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StatsEntry>) -> Void) {
        let entry = StatsEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        let nextRefresh = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date().addingTimeInterval(86400)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

// MARK: - Entry view (family switch)

struct StatsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatsEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: SmallStatsView(snapshot: entry.snapshot)
            case .systemMedium: MediumStatsView(snapshot: entry.snapshot)
            case .accessoryRectangular: RectangularStatsView(snapshot: entry.snapshot)
            case .accessoryCircular: CircularStreakView(snapshot: entry.snapshot)
            default: SmallStatsView(snapshot: entry.snapshot)
            }
        }
        .containerBackground(for: .widget) { NTColor.pine }
    }
}

// MARK: - Shared bits

private func formatKM(_ km: Double) -> String {
    km >= 1000 ? String(format: "%.0f", km) : String(format: "%.1f", km)
}

/// A real, honest empty state — a fresh install or a session that's never
/// opened Profile yet has no snapshot at all (`WidgetSnapshotStore.load()`
/// returns nil), so this shows "open the app" rather than a fake `0`
/// dressed up as a real stat.
private struct EmptySnapshotState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "location.north.line.fill")
                .font(.system(size: 14))
                .foregroundStyle(NTColor.accent)
            Text("Open NomadTerminal\nto sync your stats")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(NTColor.milk(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private func heroStat(_ value: String, _ label: LocalizedStringKey, size: CGFloat = 22) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(value).font(.system(size: size, weight: .semibold, design: .monospaced)).foregroundStyle(NTColor.milk)
        Text(label).font(.system(size: 8, weight: .semibold)).tracking(1).foregroundStyle(NTColor.milk(0.5))
    }
}

private func heatColor(_ count: Int) -> Color {
    switch count {
    case 0: return NTColor.milk(0.08)
    case 1: return NTColor.sage.opacity(0.35)
    case 2: return NTColor.sage.opacity(0.65)
    default: return NTColor.sage
    }
}

/// Same `[week][weekday]` grid `ProfileView.heatmapWeeks` builds, trimmed
/// to however many weeks actually fit at widget scale.
private func heatmapGrid(_ weeks: [[Int]], weeksShown: Int, cell: CGFloat) -> some View {
    HStack(alignment: .top, spacing: 2) {
        ForEach(Array(weeks.suffix(weeksShown).enumerated()), id: \.offset) { _, week in
            VStack(spacing: 2) {
                ForEach(Array(week.enumerated()), id: \.offset) { _, count in
                    RoundedRectangle(cornerRadius: cell > 6 ? 2 : 1, style: .continuous)
                        .fill(heatColor(count))
                        .frame(width: cell, height: cell)
                }
            }
        }
    }
}

// MARK: - Home Screen: small

/// Streak + total km, the same big-mono-number "stats header" language
/// `ProfileView`'s own hero uses — just two of its four numbers, the two
/// that read best glanceably.
private struct SmallStatsView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "location.north.line.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(NTColor.accent)
                Text("NOMADTERMINAL")
                    .font(.system(size: 7.5, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(NTColor.milk(0.4))
            }
            Spacer(minLength: 8)
            if let snapshot, snapshot.lastUpdated != .distantPast {
                VStack(alignment: .leading, spacing: 12) {
                    heroStat("\(snapshot.streakWeeks)W", "STREAK")
                    heroStat(formatKM(snapshot.totalKM), "KM LOGGED")
                }
            } else {
                Spacer()
                EmptySnapshotState()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Home Screen: medium

/// Heatmap on the left (reusing the profile screen's own grid design, just
/// fewer weeks to fit), km/countries stats on the right.
private struct MediumStatsView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            if let snapshot, snapshot.lastUpdated != .distantPast {
                VStack(alignment: .leading, spacing: 14) {
                    heroStat(formatKM(snapshot.totalKM), "KM LOGGED", size: 20)
                    heroStat("\(snapshot.countriesVisited)", "COUNTRIES", size: 20)
                }
                .frame(width: 92, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVITY")
                        .font(.system(size: 7.5, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(NTColor.milk(0.4))
                    heatmapGrid(snapshot.heatmapWeeks, weeksShown: 12, cell: 8)
                    Spacer(minLength: 0)
                    Text("\(snapshot.streakWeeks)W STREAK")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NTColor.milk(0.6))
                }
            } else {
                EmptySnapshotState()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Lock Screen: rectangular

private struct RectangularStatsView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot, snapshot.lastUpdated != .distantPast {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(formatKM(snapshot.totalKM)).font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("KM LOGGED").font(.system(size: 7, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(snapshot.streakWeeks)W").font(.system(size: 16, weight: .semibold, design: .monospaced))
                    Text("STREAK").font(.system(size: 7, weight: .medium))
                }
            }
        } else {
            Text("Open NomadTerminal").font(.system(size: 11, weight: .medium))
        }
    }
}

// MARK: - Lock Screen: circular

private struct CircularStreakView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        Gauge(value: min(Double(snapshot?.streakWeeks ?? 0), 12), in: 0...12) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(snapshot?.streakWeeks ?? 0)")
        }
        .gaugeStyle(.accessoryCircular)
    }
}

import Foundation

/// The Home Screen/Lock Screen widgets' only data source. Compiled into
/// both the app target and the widget extension target (`Sources/Shared`
/// is listed in both targets' `sources:` in project.yml) — the widget
/// process has no DB session or network access of its own, so it can only
/// ever render whatever the app last wrote here, via the shared App Group
/// container (`WidgetSnapshotStore`).
///
/// Written by `ProfileView.load()` — real numbers only, same computations
/// (`totalKM`/`countriesVisited`/`currentStreak`/heatmap) the profile
/// screen itself already does and already displays, just handed off so the
/// widget doesn't need to (and can't) recompute them from `myRoutes`. A
/// fresh app launch or profile view refresh keeps this reasonably current;
/// there's no live-live requirement here (see the widgets' own timeline
/// providers), so "last time the app was open" freshness is intentional,
/// not a compromise.
struct WidgetSnapshot: Codable {
    var totalKM: Double
    var countriesVisited: Int
    /// Consecutive weeks with at least one real recorded route —
    /// `ProfileView.computeStreak(_:)`'s own output, not recomputed here.
    var streakWeeks: Int
    /// `[week][weekday]` route-count grid, oldest week first — the exact
    /// same shape `ProfileView.heatmapWeeks` builds, just persisted so the
    /// medium widget can redraw the same grid without a database.
    var heatmapWeeks: [[Int]]
    var displayName: String
    var lastUpdated: Date

    static let empty = WidgetSnapshot(totalKM: 0, countriesVisited: 0, streakWeeks: 0, heatmapWeeks: [], displayName: "", lastUpdated: .distantPast)
}

/// Thin wrapper over `UserDefaults(suiteName:)` in the shared App Group
/// container — the standard, Apple-recommended way to hand a small,
/// infrequently-changing payload from an app to its widget extension
/// without either process needing to reach the network.
enum WidgetSnapshotStore {
    static let appGroupID = "group.io.nomadterminal.app"
    private static let key = "widgetSnapshot.v1"

    /// Called from the app whenever a real, fresher snapshot exists (see
    /// `ProfileView.load()`). Silently no-ops if the App Group container
    /// isn't reachable for some reason — a widget just keeps showing
    /// whatever it last had rather than crashing the caller.
    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    /// Called from the widget extension's own `TimelineProvider`. `nil`
    /// means "the app has never written a snapshot yet" (fresh install,
    /// never signed in) — every widget view has a real empty state for
    /// that, not a fabricated placeholder number.
    static func load() -> WidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

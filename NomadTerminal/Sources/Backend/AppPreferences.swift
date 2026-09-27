import Foundation

/// Plain-UserDefaults settings whose real effect lives outside the Settings
/// screen itself — `OfflineRouteStore` reads `wifiOnlyDownloads` at download
/// time, not through any view binding. Same lightweight persistence
/// `ThemeManager` (`Sources/DesignSystem/NTColor.swift`) already uses.
enum AppPreferences {
    private static let wifiOnlyKey = "io.nomadterminal.wifiOnlyDownloads"
    private static let visitsMonitoringKey = "io.nomadterminal.visitsMonitoringEnabled"

    static var wifiOnlyDownloads: Bool {
        get { UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: wifiOnlyKey) }
    }

    /// Off by default (opt-in, not opt-out) — passive Visits monitoring is
    /// its own separate decision from "Background location" (which just
    /// covers an active LogRoute recording continuing while backgrounded);
    /// nobody should end up with always-on passive tracking just because
    /// they approved Always location for a totally different reason.
    static var visitsMonitoringEnabled: Bool {
        get { UserDefaults.standard.object(forKey: visitsMonitoringKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: visitsMonitoringKey) }
    }
}

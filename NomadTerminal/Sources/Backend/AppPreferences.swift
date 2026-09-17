import Foundation

/// Plain-UserDefaults settings whose real effect lives outside the Settings
/// screen itself — `OfflineRouteStore` reads `wifiOnlyDownloads` at download
/// time, not through any view binding. Same lightweight persistence
/// `ThemeManager` (`Sources/DesignSystem/NTColor.swift`) already uses.
enum AppPreferences {
    private static let wifiOnlyKey = "io.nomadterminal.wifiOnlyDownloads"

    static var wifiOnlyDownloads: Bool {
        get { UserDefaults.standard.object(forKey: wifiOnlyKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: wifiOnlyKey) }
    }
}

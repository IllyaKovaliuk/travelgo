import SwiftUI

/// A real in-app language override, separate from just following the
/// device's own iOS-wide language (Settings > General > Language & Region,
/// or per-app language) — which is all this app relied on before. Mirrors
/// `ThemeManager` exactly: an `@Observable` singleton, its `current` value
/// persisted to `UserDefaults`, read by `RootView` and applied as a real
/// SwiftUI `.environment(\.locale, ...)` at the very top of the view tree
/// so it cascades live to every `Text(LocalizedStringKey)` in the app —
/// including the Localizable.xcstrings catalog — without needing an app
/// relaunch, the same way `.preferredColorScheme` already applies Pine/Milk
/// live.
@Observable
final class LanguageManager {
    static let shared = LanguageManager()

    /// nil = follow the device's own language (the original, only
    /// behavior before this setting existed). A concrete code pins the
    /// whole app to that language regardless of what iOS is set to.
    var current: String? {
        didSet { UserDefaults.standard.set(current, forKey: defaultsKey) }
    }

    var locale: Locale { current.map(Locale.init(identifier:)) ?? Locale.autoupdatingCurrent }

    /// Only the languages this app actually ships translations for (see
    /// Resources/Localizable.xcstrings) — not every locale iOS supports.
    static let supportedCodes = ["en", "uk", "es"]

    private let defaultsKey = "io.nomadterminal.appLanguage"

    private init() {
        let saved = UserDefaults.standard.string(forKey: defaultsKey)
        current = saved.flatMap { Self.supportedCodes.contains($0) ? $0 : nil }
    }
}

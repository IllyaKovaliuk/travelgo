import SwiftUI
import Observation

/// Which of Settings' two appearance tiles is active. Persisted so the
/// choice survives relaunch, and drives every `NTColor.pine`/`.milk`-family
/// lookup below — the whole app is theme-reactive through those tokens
/// alone, no per-screen wiring needed.
///
/// Deliberately NOT `@MainActor`: `NTColor` (and therefore this) gets read
/// from plain, actor-agnostic model code too (`Route.swift`'s mock data,
/// `POICategory`'s tint, `RouteDTO`) — not just SwiftUI view bodies —  so
/// isolating it would cascade `@MainActor` requirements into all of those.
/// In practice every real read/write still happens on the main thread
/// (UI-driven), same as `NTColor`'s old plain `static let` constants.
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    enum AppTheme: String { case pine, milk }

    private let defaultsKey = "io.nomadterminal.theme"
    var current: AppTheme {
        didSet { UserDefaults.standard.set(current.rawValue, forKey: defaultsKey) }
    }

    /// For the handful of call sites (`.preferredColorScheme`,
    /// `.toolbarColorScheme`) that need SwiftUI's own `ColorScheme` rather
    /// than our token enum.
    var colorScheme: ColorScheme { current == .milk ? .light : .dark }

    private init() {
        let saved = UserDefaults.standard.string(forKey: defaultsKey).flatMap(AppTheme.init(rawValue:))
        current = saved ?? .pine
    }
}

/// NomadTerminal color tokens — mirrors the palette baked into the design doc
/// (`design_extracted/NomadTerminal.dc.html`). Keep this file as the single
/// source of truth; never hard-code a hex outside of it.
///
/// Elevation model (both themes): `pine` (ground) → `pineRaised` (card
/// surface) → `pineElevated` (modals/sheets/the active tab pill) is the
/// real 3-step depth ramp — each step is a deliberately distinct fill, not
/// a near-identical shade of the last, so a card actually reads as sitting
/// on top of the screen instead of blending into it. `pineDeep`/
/// `pineShadow`/`pineLine` are utility tones off that same ramp (gradient/
/// scrim endpoints, hairlines) rather than a 4th/5th/6th elevation step in
/// their own right. Light (Milk) mode is its own independently-tuned ramp,
/// not an inversion of the dark one — it still runs dusky→bright as
/// elevation increases (matching how real elevated surfaces catch more
/// light regardless of base theme), just within a warm off-white band
/// instead of a near-black one, topping out at true white for the highest
/// layer.
///
/// The "Ground" tokens (`pine`/`pineDeep`/`pineRaised`/`pineElevated`/
/// `pineShadow`/`pineLine`/`milk`) are `static var`, not `static let` —
/// they read `ThemeManager.shared.current` on every access, so every one of
/// their ~50 call sites across the app picks up a theme change automatically
/// just by SwiftUI re-rendering, with zero per-screen code. `milkSurface`/
/// `ink` and every accent/status color stay fixed in both themes on purpose
/// — they're either an explicitly-light local surface (a badge, a swatch
/// preview) or a brand/status color that shouldn't shift with light/dark.
enum NTColor {
    // MARK: Ground — theme-reactive
    static var pine: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xF0EBDC) : Color(hex: 0x0A0F0D) }
    static var pineDeep: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xE3DAC5) : Color(hex: 0x05080A) }
    static var pineRaised: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xF8F5EA) : Color(hex: 0x151B18) }
    /// The 3rd, topmost elevation step — new. Modals/sheets/the active tab
    /// bar pill should sit on this, one clear step lighter than
    /// `pineRaised`'s cards, so a sheet presented over a card still reads
    /// as "higher," not the same surface repeated.
    static var pineElevated: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xFFFFFF) : Color(hex: 0x212A25) }
    static var pineShadow: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xE7DFCB) : Color(hex: 0x080B09) }
    static var pineLine: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xFCFAF3) : Color(hex: 0x1C2420) }

    /// Primary foreground (text/icons) — cream-on-dark in Pine, ink-on-light
    /// in Milk. Also doubles as most primary-CTA button fills, which is why
    /// this flipping (not staying literally "cream") is correct: it keeps
    /// "readable foreground against the current ground" as the actual
    /// semantic, not a literal color name.
    static var milk: Color { ThemeManager.shared.current == .milk ? Color(hex: 0x0B2A1D) : Color(hex: 0xFAF6EC) }

    // MARK: Ground — fixed regardless of theme
    static let milkSurface = Color(hex: 0xF2ECDD)    // an explicitly-light local surface (badge, swatch preview)
    static let ink = Color(hex: 0x0B2A1D)            // text on an explicitly-light local surface

    // MARK: Accents — fixed regardless of theme
    static let accent = Color(hex: 0xE8743B)         // terracotta — primary CTA / record
    static let accentDeep = Color(hex: 0xC2551F)
    static let sage = Color(hex: 0x5FA777)           // success / foot / on-toggles
    static let water = Color(hex: 0x3E92CC)          // water / kayak
    static let extreme = Color(hex: 0x7A5FBF)        // climb / extreme
    static let gold = Color(hex: 0xE0A458)           // moderate / POI / warnings
    static let hard = Color(hex: 0xB33A2B)           // hard / SOS / destructive
    static let hardBright = Color(hex: 0xE58272)

    // MARK: Foreground at reduced opacity, theme-aware since `milk` is
    static func milk(_ opacity: Double) -> Color { milk.opacity(opacity) }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

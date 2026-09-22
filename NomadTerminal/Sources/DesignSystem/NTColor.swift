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

/// NomadTerminal color tokens.
///
/// Rebuilt around a monochrome UI shell — real route/landscape photography
/// is the only place color should come from now, so the chrome (grounds,
/// cards, text) is a tight neutral grayscale ramp with no hue in it at all,
/// not even the pine green this used to carry. `pine` (ground) →
/// `pineRaised` (card surface) → `pineElevated` (modals/sheets/the active
/// tab pill) is the real 3-step depth ramp — each step a clearly distinct,
/// truly neutral gray, so a card reads as sitting on top of the screen
/// instead of blending into it, and a photo laid on top of any of these
/// pops instead of competing with a tinted background. `pineDeep`/
/// `pineShadow`/`pineLine` are utility tones off that same neutral ramp
/// (gradient/scrim endpoints, hairlines), not additional elevation steps.
/// Light (Milk) mode is its own independently-tuned neutral ramp, not an
/// inversion of the dark one — same dusky→bright direction as elevation
/// increases, just within a true white/light-gray band instead of a
/// near-black one.
///
/// Names keep their old "pine/milk" identity on purpose — renaming ~50
/// call sites across the app to something like `ground`/`surface` would
/// touch every screen for zero visual difference; the token *values* below
/// are what actually changed.
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
    // MARK: Ground — theme-reactive, true neutral grayscale
    static var pine: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xFFFFFF) : Color(hex: 0x0A0A0A) }
    static var pineDeep: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xE8E8E8) : Color(hex: 0x000000) }
    static var pineRaised: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xF5F5F5) : Color(hex: 0x1A1A1A) }
    /// The 3rd, topmost elevation step. Modals/sheets/the active tab bar
    /// pill sit on this, one clear step lighter than `pineRaised`'s cards.
    static var pineElevated: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xEBEBEB) : Color(hex: 0x262626) }
    static var pineShadow: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xE2E2E2) : Color(hex: 0x050505) }
    static var pineLine: Color { ThemeManager.shared.current == .milk ? Color(hex: 0xF8F8F8) : Color(hex: 0x2E2E2E) }

    /// Primary foreground (text/icons) — near-white on dark Pine, near-black
    /// on light Milk. Also doubles as most primary-CTA button fills, which
    /// is why this flipping (not staying literally one color) is correct:
    /// it keeps "readable foreground against the current ground" as the
    /// actual semantic. Secondary/tertiary text doesn't get its own
    /// separate gray token — `milk(_:)` below, alpha-blending this
    /// near-white/near-black against a truly neutral ground, already lands
    /// on the same mid-gray a dedicated token would (e.g. `milk(0.55)` on
    /// dark Pine ≈ 0x8C8C8C), so the existing opacity-based call sites
    /// (~200 of them) needed no changes to get there.
    static var milk: Color { ThemeManager.shared.current == .milk ? Color(hex: 0x0A0A0A) : Color(hex: 0xF5F5F5) }

    // MARK: Ground — fixed regardless of theme
    static let milkSurface = Color(hex: 0xF5F5F5)    // an explicitly-light local surface (badge, swatch preview)
    static let ink = Color(hex: 0x0A0A0A)            // text on an explicitly-light local surface

    // MARK: Accents — fixed regardless of theme
    // Terracotta stays the one accent — kept over a pure white/black accent
    // (the spec's other option) because it's already load-bearing brand
    // identity (the compass mark, the app icon) that a monochrome accent
    // would have meant re-deriving from scratch for no real gain; the
    // discipline the brief actually wants is about *usage* (CTA/record/
    // active-state only), which is what the accent audit below enforces.
    static let accent = Color(hex: 0xE8743B)         // terracotta — primary CTA / record
    static let accentDeep = Color(hex: 0xC2551F)
    // Status/category hues (difficulty tags, transport icons, the map's
    // per-segment line colors) — a real, direct reversal: an earlier pass
    // muted these down on the theory that photography/map imagery should
    // be the only vivid thing on screen, but that read as flatly gray on
    // the actual route map, which is exactly the opposite of "premium."
    // Real color-coded data (which leg is which transport) needs to
    // actually pop, not apologize for existing — vivid, saturated hues,
    // not the desaturated versions from that pass.
    static let sage = Color(hex: 0x2FBF71)           // success / foot / on-toggles
    static let water = Color(hex: 0x1E9DE3)          // water / kayak
    static let extreme = Color(hex: 0x9B4DEB)        // climb / extreme
    static let gold = Color(hex: 0xF5A623)           // moderate / POI / warnings
    static let hard = Color(hex: 0xE8382B)           // hard / SOS / destructive
    static let hardBright = Color(hex: 0xFF5C46)

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

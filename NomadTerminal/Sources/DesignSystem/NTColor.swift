import SwiftUI

/// NomadTerminal color tokens — mirrors the palette baked into the design doc
/// (`design_extracted/NomadTerminal.dc.html`). Keep this file as the single
/// source of truth; never hard-code a hex outside of it.
enum NTColor {
    // MARK: Ground
    static let pine = Color(hex: 0x00311F)          // primary dark surface
    static let pineDeep = Color(hex: 0x001B10)       // feed / compass / recording backgrounds
    static let pineRaised = Color(hex: 0x0A4A2F)     // lighter blob / raised surface
    static let pineShadow = Color(hex: 0x04261A)     // map / card shadow tone
    static let pineLine = Color(hex: 0x06301F)

    static let milk = Color(hex: 0xFAF6EC)           // light ground / primary button fill
    static let milkSurface = Color(hex: 0xF2ECDD)    // Milk-theme card surface
    static let ink = Color(hex: 0x0B2A1D)            // text on Milk

    // MARK: Accents
    static let accent = Color(hex: 0xE8743B)         // terracotta — primary CTA / record
    static let accentDeep = Color(hex: 0xC2551F)
    static let sage = Color(hex: 0x5FA777)           // success / foot / on-toggles
    static let water = Color(hex: 0x3E92CC)          // water / kayak
    static let extreme = Color(hex: 0x7A5FBF)        // climb / extreme
    static let gold = Color(hex: 0xE0A458)           // moderate / POI / warnings
    static let hard = Color(hex: 0xB33A2B)           // hard / SOS / destructive
    static let hardBright = Color(hex: 0xE58272)

    // MARK: Text on dark
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

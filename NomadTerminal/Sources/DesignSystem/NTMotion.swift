import SwiftUI

/// The one navigation-level motion curve — every tab switch, sheet-driven
/// state change, and list-content transition should use this instead of
/// its own one-off `.spring(response:dampingFraction:)` literal, so the app
/// has a single consistent "feel" instead of a dozen very-slightly-different
/// springs nobody could tell apart individually but that add up to feeling
/// inconsistent. Distinct from `ntPressable`'s own press-feedback curve
/// (`NTButtonStyles.swift`) on purpose — that one is deliberately snappier
/// (a finger lifting expects an instant response), this one is for content
/// actually moving/appearing on screen.
enum NTMotion {
    static let spring: Animation = .spring(response: 0.35, dampingFraction: 0.86)
}

import SwiftUI

/// Grid columns that follow the horizontal size class instead of assuming a
/// phone-width screen. Compact (every existing iPhone, and the Duo's outer
/// display) keeps the original column count, so nothing changes there; regular
/// (the Duo's inner display, iPad-style widths) gets more columns rather than
/// two stretched ones. Reads the size class, not the idiom or orientation —
/// Apple's guidance for the Duo.
enum AdaptiveColumns {
    static func grid(compact: Int = 2, regular: Int = 3, spacing: CGFloat, sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        let count = sizeClass == .regular ? regular : compact
        return Array(repeating: GridItem(.flexible(), spacing: spacing), count: count)
    }
}

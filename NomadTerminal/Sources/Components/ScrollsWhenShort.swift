import SwiftUI

extension View {
    /// Lays the content out exactly as before when it fits (so `Spacer()`s
    /// still pin things to the bottom), and makes it scrollable when it
    /// doesn't — an iPhone app on iPad's short compatibility window, large
    /// Dynamic Type, landscape. Without this, anything below the fold (the
    /// Terms / Privacy links, the primary button) is simply unreachable,
    /// which App Review rejected under Guideline 4.
    func scrollsWhenShort() -> some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                self.frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

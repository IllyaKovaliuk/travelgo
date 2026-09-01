import SwiftUI

/// Onboarding progress dots — the active one stretches into a pill with a
/// spring, matching the doc's `26px / 8px` step indicator.
struct PageDots: View {
    let count: Int
    let index: Int
    var activeColor: Color = NTColor.milk
    var inactiveColor: Color = NTColor.milk(0.3)

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? activeColor : inactiveColor)
                    .frame(width: i == index ? 26 : 8, height: 4)
                    .animation(.spring(response: 0.45, dampingFraction: 0.75), value: index)
            }
        }
    }
}
